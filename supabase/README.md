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

## 4. Edge Function(B-2 で有効化)

```powershell
npm i -g supabase
supabase login
supabase link --project-ref xxxx
supabase secrets set WEBHOOK_SECRET=<ランダム文字列> GOOGLE_VISION_API_KEY=<任意> MATCH_MODEL_API_KEY=<任意>
supabase functions deploy judge-photo --no-verify-jwt
```

Database → Webhooks で `photos` テーブルの INSERT / UPDATE を `judge-photo` に送る Webhook を作成し、HTTP ヘッダ `x-webhook-secret` に同じ値を設定する。

## 5. 配信スナップショット(B-2)

`approved_photo_snapshot` ビューを1時間ごとに JSON へ書き出して配布する。方法は2択:
- GitHub Actions から `service_role` キーでビューを読み、`assets/community_photos.json` にコミット(既存の `gacha_data.json` と同じ配信経路。**別ファイルにするので v1.0 アプリとの互換は壊れない**)
- Supabase の pg_cron + Storage に JSON を書く

## 6. 運用(モデレーション)

- 保留(`held`)・通報の多い投稿は Table Editor で `photos` を `status = held` で絞って確認し、`approved` / `rejected` を手で更新
- 悪質な投稿者は `posters.blocked = true`(以後の投稿は RLS で弾かれる)
- 権利者からの申し出: `photos` を `series_id` / `maker` で絞って `removed` に一括更新。公式画像の非表示は既存の `assets/app_config.json`

## 7. 費用の目安

- Free プランで開始可(DB 500MB / Storage 1GB / 帯域 5GB/月)
- 採用写真 150KB × 1万枚 = 1.5GB で Pro($25/月)が必要になる。目安として採用 5,000枚を超えたら移行
