// 投稿写真の自動判定 Edge Function(段階B-2で有効化)
//
// 呼び出し: Database Webhook(photos テーブル INSERT) から POST される。
// 処理:
//   1. pending バケットから画像を取得
//   2. SafeSearch(Google Cloud Vision) で不適切判定
//   3. マルチモーダルモデルで「シリーズ名 + アイテム名」との一致度を 0..1 で採点
//   4. 画質(解像度・サイズ)を簡易採点
//   5. auto_score / auto_detail を更新。明確な違反は rejected、閾値未満は pending のまま(承認で救済可)
//   6. 承認済み(approved)になった写真を approved バケットへコピーして public_url を設定する処理は
//      別の Webhook(photos UPDATE, status=approved) で同じ関数を呼び、`mode: "publish"` で処理する
//
// 必要な環境変数(supabase secrets set):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  (自動で注入される)
//   GOOGLE_VISION_API_KEY                    (SafeSearch 用)
//   MATCH_MODEL_API_KEY                      (一致度判定用。未設定なら一致度は 0.5 固定=承認任せ)
//
// デプロイ: supabase functions deploy judge-photo --no-verify-jwt
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
  const match = await matchScore(bytes, record);
  const quality = qualityScore(bytes.byteLength);

  const detail = { safe_search: safe, match, quality };
  let status: string | undefined;
  let score = 0;
  if (safe.blocked) {
    status = "rejected";
  } else {
    score = match * 0.7 + quality * 0.3;
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

// 「シリーズ名 + アイテム名」との一致度。B-2 でマルチモーダルモデルの呼び出しを実装する。
// 未設定時は 0.5 を返し、採否をコミュニティ承認に委ねる。
async function matchScore(_bytes: Uint8Array, _record: PhotoRow): Promise<number> {
  if (!Deno.env.get("MATCH_MODEL_API_KEY")) return 0.5;
  // TODO(B-2): Gemini / GPT 系 API に画像と "series title / item title" を渡し 0..1 を返させる
  return 0.5;
}

// 画質の簡易指標: ファイルサイズ(JPEG, 長辺1200px前提)。B-2 で解像度・ブレ判定を追加
function qualityScore(byteLength: number): number {
  if (byteLength < 30_000) return 0.2;
  if (byteLength < 80_000) return 0.5;
  if (byteLength < 150_000) return 0.8;
  return 1.0;
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
