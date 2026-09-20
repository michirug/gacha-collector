// 投稿写真の自動判定 Edge Function(段階B-2で有効化)
//
// 呼び出し: Database Webhook(photos テーブル INSERT) から POST される。
// 処理:
//   1. pending バケットから画像を取得
//   2. SafeSearch(Google Cloud Vision) で不適切判定
//   3. マルチモーダルモデルで「シリーズ名 + アイテム名」との一致度を 0..1 で採点
//   4. 画質(解像度・サイズ)を簡易採点
//   5. auto_score / auto_detail を更新。明確な違反は rejected、閾値未満は pending のまま(承認で救済可)
//   6. 同じ Webhook を photos UPDATE にも掛けておき、status が approved に変わったら approved バケットへ
//      コピーして public_url を設定(publish)、removed/rejected に変わったら Storage から物理削除する
//
// 必要な環境変数(supabase secrets set):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  (自動で注入される)
//   WEBHOOK_SECRET                           (Webhook の x-webhook-secret ヘッダと照合)
//   GOOGLE_VISION_API_KEY                    (SafeSearch 用。未設定なら不適切判定をスキップ)
//   MATCH_MODEL_API_KEY                      (一致度判定用の Gemini API キー(Google AI Studio)。未設定なら一致度は 0.5 固定=承認任せ)
//   MATCH_MODEL                              (省略時 gemini-2.5-flash)
//
// デプロイ: npx supabase functions deploy judge-photo --no-verify-jwt
// (Webhook からの呼び出しなので JWT 検証は行わず、代わりに WEBHOOK_SECRET ヘッダを照合する)

import { createClient } from "npm:@supabase/supabase-js@2";

type PhotoRow = {
  id: string;
  item_id: string;
  series_id: string;
  maker: string;
  poster_id: string;
  status: string;
  storage_path: string;
  item_label?: string | null;
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  if (req.headers.get("x-webhook-secret") !== Deno.env.get("WEBHOOK_SECRET")) {
    return new Response("forbidden", { status: 403 });
  }
  const payload = await req.json();
  const record = payload.record as PhotoRow;
  const old = payload.old_record as PhotoRow | undefined;

  // 採用時: pending → approved バケットへコピーして公開URLを付与
  if (record.status === "approved" && old?.status !== "approved") {
    return await publish(record);
  }
  // 取り消し・拒否時: pending バケットから物理削除
  if ((record.status === "removed" || record.status === "rejected") && old?.status !== record.status) {
    await supabase.storage.from("photos-pending").remove([record.storage_path]);
    if (record.status === "removed") {
      await supabase.storage.from("photos-approved").remove([record.storage_path]);
    }
    return json({ ok: true, action: "deleted" });
  }
  if (payload.type !== "INSERT") return json({ ok: true, action: "ignored" });

  return await judge(record);
});

async function judge(record: PhotoRow) {
  const { data: file, error } = await supabase.storage
    .from("photos-pending")
    .download(record.storage_path);
  if (error || !file) return json({ ok: false, error: error?.message }, 500);
  const bytes = new Uint8Array(await file.arrayBuffer());

  const safe = await safeSearch(bytes);
  const match = safe.blocked ? { score: 0 } : await matchScore(bytes, record);
  const quality = qualityScore(bytes);

  const detail = { safe_search: safe, match, quality };
  let status: string | undefined;
  let score = 0;
  if (safe.blocked) {
    status = "rejected";
  } else {
    score = match.score * 0.7 + quality.score * 0.3;
  }

  const { error: upErr } = await supabase
    .from("photos")
    .update({ auto_score: score, auto_detail: detail, ...(status ? { status } : {}) })
    .eq("id", record.id);
  if (upErr) return json({ ok: false, error: upErr.message }, 500);
  return json({ ok: true, score, status: status ?? "pending" });
}

async function publish(record: PhotoRow) {
  const { data: file, error } = await supabase.storage
    .from("photos-pending")
    .download(record.storage_path);
  if (error || !file) return json({ ok: false, error: error?.message }, 500);
  const { error: upErr } = await supabase.storage
    .from("photos-approved")
    .upload(record.storage_path, file, { contentType: "image/jpeg", upsert: true });
  if (upErr) return json({ ok: false, error: upErr.message }, 500);
  const { data: pub } = supabase.storage.from("photos-approved").getPublicUrl(record.storage_path);
  await supabase.from("photos").update({ public_url: pub.publicUrl }).eq("id", record.id);
  return json({ ok: true, action: "published", url: pub.publicUrl });
}

// Google Cloud Vision SafeSearch。adult/violence/racy が LIKELY 以上なら blocked
async function safeSearch(bytes: Uint8Array): Promise<{ blocked: boolean; raw?: unknown }> {
  const key = Deno.env.get("GOOGLE_VISION_API_KEY");
  if (!key) return { blocked: false };
  const res = await fetch(`https://vision.googleapis.com/v1/images:annotate?key=${key}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      requests: [{ image: { content: base64(bytes) }, features: [{ type: "SAFE_SEARCH_DETECTION" }] }],
    }),
  });
  if (!res.ok) return { blocked: false, raw: await res.text() };
  const data = await res.json();
  const ann = data.responses?.[0]?.safeSearchAnnotation ?? {};
  const bad = (v: string) => v === "LIKELY" || v === "VERY_LIKELY";
  return { blocked: bad(ann.adult) || bad(ann.violence) || bad(ann.racy), raw: ann };
}

// 「シリーズ名 / アイテム名」との一致度を Gemini で 0..1 に採点する。
// キー未設定・API失敗時は 0.5 を返し、採否をコミュニティ承認に委ねる。
type MatchResult = { score: number; reason?: string; error?: string; skipped?: boolean };

async function matchScore(bytes: Uint8Array, record: PhotoRow): Promise<MatchResult> {
  const key = Deno.env.get("MATCH_MODEL_API_KEY");
  if (!key) return { score: 0.5, skipped: true };
  const model = Deno.env.get("MATCH_MODEL") ?? "gemini-2.5-flash";
  // item_id は "<seriesId>::<itemTitle>" なので、旧クライアント(item_label なし)でもアイテム名は取れる
  const label = record.item_label ?? record.item_id.split("::").slice(1).join("::");
  const prompt = [
    "この写真はカプセルトイ(ガチャガチャ)のコレクション記録アプリにユーザーが投稿したものです。",
    `対象商品: 「${label}」`,
    "写真がこの商品(のアイテム)を写しているかを判定し、JSONのみを返してください。",
    "評価基準: match は 0.0〜1.0 の一致度(1.0=確実にこの商品、0.5=判断できない、0.0=明らかに別物や商品以外)。",
    "商品の公式パッケージ画像・台紙・画面のスクリーンショット・他サイトの画像の転載と思われる場合は match を 0.2 以下にし、reason に理由を書く。",
    "人物の顔が写っている場合は face を true にする。",
    '形式: {"match": number, "face": boolean, "reason": string}',
  ].join("\n");
  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          contents: [{
            role: "user",
            parts: [
              { text: prompt },
              { inline_data: { mime_type: "image/jpeg", data: base64(bytes) } },
            ],
          }],
          generationConfig: { temperature: 0, response_mime_type: "application/json" },
        }),
      },
    );
    if (!res.ok) return { score: 0.5, error: `HTTP ${res.status} ${await res.text()}` };
    const data = await res.json();
    const text = data.candidates?.[0]?.content?.parts?.[0]?.text ?? "{}";
    const parsed = JSON.parse(text);
    let score = clamp(Number(parsed.match));
    if (parsed.face === true) score = Math.min(score, 0.3);
    return { score, reason: typeof parsed.reason === "string" ? parsed.reason : undefined };
  } catch (e) {
    return { score: 0.5, error: String(e) };
  }
}

// 画質の簡易指標: JPEG ヘッダから解像度を読み、短辺と圧縮後サイズで採点する
// (アプリは長辺1200pxに縮小して送るので、極端に小さい・軽い画像だけを落とす)
function qualityScore(bytes: Uint8Array): { score: number; width?: number; height?: number; bytes: number } {
  const dim = jpegDimensions(bytes);
  let score = 1.0;
  if (dim) {
    const short = Math.min(dim.width, dim.height);
    if (short < 300) score = 0.2;
    else if (short < 600) score = 0.6;
  }
  if (bytes.byteLength < 30_000) score = Math.min(score, 0.3);
  else if (bytes.byteLength < 80_000) score = Math.min(score, 0.7);
  return { score, ...dim, bytes: bytes.byteLength };
}

// SOF マーカー(0xFFC0〜0xFFCF、C4/C8/CC を除く)から幅・高さを読む
function jpegDimensions(b: Uint8Array): { width: number; height: number } | undefined {
  if (b.length < 4 || b[0] !== 0xff || b[1] !== 0xd8) return undefined;
  let i = 2;
  while (i + 9 < b.length) {
    if (b[i] !== 0xff) { i++; continue; }
    const marker = b[i + 1];
    if (marker === 0xd8 || (marker >= 0xd0 && marker <= 0xd7) || marker === 0x01 || marker === 0xff) { i += 2; continue; }
    const len = (b[i + 2] << 8) | b[i + 3];
    if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
      return { height: (b[i + 5] << 8) | b[i + 6], width: (b[i + 7] << 8) | b[i + 8] };
    }
    if (marker === 0xda) return undefined; // SOS に到達: ヘッダ内に SOF なし
    i += 2 + len;
  }
  return undefined;
}

function clamp(n: number): number {
  return Number.isFinite(n) ? Math.max(0, Math.min(1, n)) : 0.5;
}

function base64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(s);
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}
