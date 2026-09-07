# Play ストアへの配信自動化(Publishing API)

`tool/publish_release.dart` で AAB のアップロード・トラック配置・掲載文・スクリーンショットの更新を行う。
**初回リリースは Console で手作業**(アプリ作成・各種申告フォームは API 非対応)。2回目以降のアップデートから使う。

## 1. サービスアカウントの準備(初回のみ、ユーザー作業)

1. Google Cloud Console(https://console.cloud.google.com)で任意のプロジェクトを選択(なければ作成。Play Console と同じ Google アカウントで)
2. 「APIとサービス」→「ライブラリ」→ **Google Play Android Developer API** を有効化
3. 「IAMと管理」→「サービスアカウント」→ 作成。名前は `play-publisher` 等。ロールは付けなくてよい
4. 作成したサービスアカウント → 「キー」→「鍵を追加」→ JSON → ダウンロード
   - 保存先は**リポジトリ外**(例: `C:\Users\wioiw\Downloads\devin\gacha_collector\secrets\play-service-account.json`)
5. Play Console → 「ユーザーと権限」→「新しいユーザーを招待」→ サービスアカウントのメールアドレス(`...@...iam.gserviceaccount.com`)
   - アプリの権限: ガチャ活ポケットに対して **「アプリ情報の管理」「製品版リリースの管理」「テスト版トラックの管理」** を付与
   - 招待後、反映まで最大24時間かかることがある

## 2. 実行

```powershell
$env:PLAY_SERVICE_ACCOUNT_JSON = "C:\Users\wioiw\Downloads\devin\gacha_collector\secrets\play-service-account.json"

# 1) バージョンを上げてビルド(pubspec.yaml の version: x.y.z+N の N を必ず増やす)
flutter build appbundle --release

# 2) まず内部テストトラックへ(自分の端末で確認)
dart run tool/publish_release.dart --aab=build/app/outputs/bundle/release/app-release.aab --track=internal --status=completed --notes=store/release_notes.txt

# 3) 問題なければ製品版へ。draft で置いて Console で「公開」を押すか、completed で即審査送信
dart run tool/publish_release.dart --aab=build/app/outputs/bundle/release/app-release.aab --track=production --status=completed --notes=store/release_notes.txt

# 掲載文だけ / スクショだけの更新
dart run tool/publish_release.dart --listing
dart run tool/publish_release.dart --screenshots

# commit せず検証だけ
dart run tool/publish_release.dart --aab=... --track=internal --dry-run
```

- `--status=inProgress --rollout=0.2` で段階的公開(20%)
- リリースノートは `store/release_notes.txt`(ja-JP、500字以内)。バージョンごとに書き換える
- 段階B(Supabase)を含むビルドは `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` を付けてビルドすること(supabase/README.md)

## 3. 注意

- サービスアカウント鍵は `.gitignore` 対象外の場所に置かないこと(リポジトリ外を推奨)。漏えいしたら Cloud Console で鍵を削除して再発行
- API でできないこと: アプリの新規作成、データセーフティ・コンテンツレーティング・対象年齢等の申告、デベロッパー情報の変更。これらは Console で行う
- 申告内容が変わるリリース(段階Bの UGC 追加など)は、AAB を上げる前に Console 側の申告フォームを更新しておく
