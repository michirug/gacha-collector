# Supabase セットアップ手順(段階B: 写真共有)

設計の背景は `store/photo_sharing_design.md`。ここは実際に手を動かす手順のみ。

## 1. プロジェクト作成(ユーザー作業)

1. https://supabase.com にサインアップ(GitHubアカウント可)→ New project
   - Name: `gacha-pocket`(検証用に `gacha-pocket-dev` も作ると安全)
   - Region: **Northeast Asia (Tokyo)**
   - Database password: パスワードマネージャーに保存
2. Project Settings → API から以下を控える
   - `Project URL`(例: `https://xxxx.supabase.co`)
   - `anon public` キー(アプリに埋め込む。公開されても RLS で守られる前提のキー)
   - `service_role` キー(**絶対にアプリやリポジトリに入れない**。Edge Function だけが使う)
3. Authentication → Providers → **Anonymous sign-ins を ON**
4. Authentication → Rate Limits: 匿名サインインの上限はデフォルトのままで可

## 2. スキーマ適用

SQL Editor に `supabase/migrations/0001_photos.sql` を貼り付けて Run。
テーブル `posters / photos / approvals / reports / likes / blocks`、RPC 4本、Storage バケット2つ(`photos-pending` 非公開、`photos-approved` 公開)ができる。

## 3. アプリへの接続情報の渡し方

鍵はリポジトリに入れず、ビルド時の `--dart-define` で渡す:

```powershell
flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...
flutter build appbundle --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

未指定の場合、アプリは「写真共有なし」で動く(段階Aと同じ挙動)。`lib/community/community_service.dart` の `CommunityService.isConfigured` で判定している。

## 4. Edge Function(B-2)

事前に SQL Editor で `supabase/migrations/0002_judge_support.sql` を実行(`item_label` 列の追加、`approve_photo` の条件緩和)。

### 4-1. デプロイ(ユーザーのターミナルで実行。ログインはブラウザ認証なので手元で)

```powershell
cd <リポジトリ>/gacha_collector
npx supabase login                                  # ブラウザが開く → Authorize
npx supabase link --project-ref atficwbsfffthcorjnod  # DBパスワードを聞かれたら入力(空Enterでも link は通る)
$secret = -join ((1..40) | % { '{0:x}' -f (Get-Random -Max 16) })   # Webhook 用ランダム文字列
$secret                                              # ← 表示された値を控える(次の 4-2 で使う)
npx supabase secrets set WEBHOOK_SECRET=$secret
npx supabase functions deploy judge-photo --no-verify-jwt
```

任意(後から追加可):
- `npx supabase secrets set MATCH_MODEL_API_KEY=<Gemini APIキー>` — 一致度判定。Google AI Studio(https://aistudio.google.com/apikey)で無料枠のキーを作る。未設定なら一致度 0.5 固定(承認任せ)
- `npx supabase secrets set GOOGLE_VISION_API_KEY=<Cloud Vision キー>` — SafeSearch。未設定なら不適切判定をスキップ

**`npx supabase login` は一度やればトークンがPCに保存され、以後は Devin 側のシェルからも `npx supabase ...` が使える**
(`functions deploy` / `secrets set` / `db query --linked` など。`db query --linked` は Management API 経由なので DB パスワード不要。
1回の呼び出しに1文だけ渡す。複数文をまとめると黙って失敗する)。

### 4-2. Webhook

Integrations → Database Webhooks → Install(pg_net 有効化、初回のみ)。その後はダッシュボードのフォームでも、
次の SQL(フォームが裏で作るトリガーと同じ)でも作れる:

```sql
create trigger judge_photo after insert or update on public.photos
for each row execute function supabase_functions.http_request(
  'https://<project-ref>.supabase.co/functions/v1/judge-photo', 'POST',
  '{"Content-type":"application/json","x-webhook-secret":"<WEBHOOK_SECRET>"}', '{}', '10000');
```

(2026-09-20 に作成済み。secret を変えたら `drop trigger judge_photo on photos` して作り直す)

### 4-3. 動作確認

アプリから写真を共有 → Table Editor の `photos` で `auto_score` / `auto_detail` が数秒後に入る。
Edge Functions → judge-photo → Logs / Invocations でエラーを確認できる。
手で `status` を `approved` にすると publish が走り `public_url` が入り、`photos-approved` バケットにファイルが現れる。

## 5. 配信スナップショット(B-2)

`approved_photo_snapshot` ビューを GitHub Actions(`.github/workflows/update-community-photos.yml`、毎時15分)が
`tool/export_community_photos.dart` で `assets/community_photos.json` に書き出してコミットする(既存の `gacha_data.json` と同じ配信経路。
**別ファイルなので v1.0 アプリとの互換は壊れない**)。採用写真は RLS で誰でも読めるので publishable キーで足りる。

**ユーザー作業(初回のみ)**: GitHub リポジトリ → Settings → Secrets and variables → Actions に以下を登録
- `SUPABASE_URL` = `https://<project-ref>.supabase.co`
- `SUPABASE_PUBLISHABLE_KEY` = `sb_publishable_...`

手動実行: Actions タブ → 「みんなの図鑑 写真スナップショット更新」→ Run workflow。ローカルでは

```powershell
$env:SUPABASE_URL="https://xxxx.supabase.co"; $env:SUPABASE_KEY="sb_publishable_..."
dart run tool/export_community_photos.dart
```

アプリ側は `lib/community_photos.dart`(`CommunityPhotos`)が 同梱→端末キャッシュ→raw URL の順で読み、
`GachaImage` が 自分の写真 → みんなの写真 → 公式画像 → プレースホルダー の優先順で表示する。

## 5-2. 承認・通報(B-2、`0003_review.sql` 適用済み)

- 承認候補は RPC `pending_photos_for_review(series_id, limit)`。アプリはシリーズ詳細に `PhotoReviewCard` を出し、「合ってる」→`approve_photo`、「違う」→`report_photo('wrong_item')`
- pending バケットは authenticated 全員が読める(署名URL 1時間)。パスは RPC 経由でのみ分かる
- ブロックは `blocks` テーブル + 端末側キャッシュ。ブロック済み投稿者の写真は候補にも図鑑にも出ない

## 6. 運用(モデレーション)

- 保留(`held`)・通報の多い投稿は Table Editor で `photos` を `status = held` で絞って確認し、`approved` / `rejected` を手で更新
- 悪質な投稿者は `posters.blocked = true`(以後の投稿は RLS で弾かれる)
- 権利者からの申し出: `photos` を `series_id` / `maker` で絞って `removed` に一括更新。公式画像の非表示は既存の `assets/app_config.json`

## 7. 費用の目安

- Free プランで開始可(DB 500MB / Storage 1GB / 帯域 5GB/月)
- 採用写真 150KB × 1万枚 = 1.5GB で Pro($25/月)が必要になる。目安として採用 5,000枚を超えたら移行
