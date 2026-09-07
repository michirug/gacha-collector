# AGENTS.md — ガチャ活ポケット(gacha_collector)

新セッション開始時に必ず最初に読むこと。前セッション(Cascade)からの引き継ぎ資料。
ユーザーとのやり取りは **日本語**。回答は簡潔に。

---

## 1. プロダクト概要

- **アプリ名**: ガチャ活ポケット(カタカナ表記で確定)
- **ストア表記**: 「ガチャ活ポケット - カプセルトイの新作&コレクション管理」(29字)
- **開発者名**: ポケットアプリケーションズ(Play Console設定済み)
- **運営者/連絡先**: コンテンツマーケティング合同会社 / info@contentsmarketing.co.jp
- **概要**: カプセルトイ(ガチャ)の新作情報を一覧し、獲得済み/ダブり/欲しいものを管理、コンプ演出・実績・シェアカードで楽しませるコレクション管理アプリ
- **公式ハッシュタグ**: #ガチャ活ポケット + #ガチャ活(シェア文言・シェアカードに実装済み)
- **商標注意**: ブランド部分に「ガチャ」「ガチャガチャ」「ガシャポン」単体は使わない(タカラトミーアーツ/バンダイの登録商標)。「ガチャ活」は一般語化していて低リスクと判断
- **法的文書(GitHub Pages、公開確認済み)**:
  - プライバシーポリシー: https://michirug.github.io/gacha-collector/privacy/
  - 利用規約: https://michirug.github.io/gacha-collector/terms/
- **GitHubリポジトリ**: https://github.com/michirug/gacha-collector (ブランチ main)

## 2. 現在のステータス(2026-09-04時点)

**方針転換: 旧v1.0は提出せず、「v1.0再定義」として中核価値を作り直してからリリースする。** 詳細・理由は `store/strategy.md` 冒頭「v1.0再定義」を参照。

旧v1.0で完了済み(資産として維持):
- [x] Android署名設定・リリースAABビルド、アプリ名・ハッシュタグ反映、法的文書公開、ストア素材生成、コンプ演出修正、開発者名設定

v1.0再定義(リリース前に必須):
- [x] 1. マルチメーカー収録: クローラー(`tool/crawl_makers.dart`: タカラトミーアーツ/キタンクラブ/ブシロードクリエイティブ/SO-TA)、`Maker`モデル、Actions組み込み、パーサー回帰テスト。ケンエレファント/トイズキャビンはv1.1へ
  - [x] バックフィル完了(2026-09-06): バンダイ8,846 / タカラトミーアーツ2,507 / ブシロード1,503 / キタンクラブ955 / SO-TA464 = 14,275件
- [x] 2. ホーム再設計(メーカーチップ/今月の新作/ウィッシュ発売間近/あと少しでコンプ/来月/発売カレンダー、ブランドテーマ、cached_network_image)。エミュレータで表示確認済み
- [x] 3. バックアップ/復元(マイページ→JSON書き出し/復元(追加・置き換え))。エミュレータで往復確認済み
- [x] 4. 譲/求カード生成(シリーズ詳細のswapアイコン。ダブり=譲、未獲得=求)
- [x] 5. 著作権リスク低減(段階A): 説明文の配信停止(既存JSONからも削除)、トリミング廃止・画像枠を正方形に、出典表記、権利者向け削除窓口(マイページ/シリーズ詳細→mailto)、`ImagePolicy`によるメーカー単位の公式画像オフ、端末内「自分の写真」(長押しシート→撮る/アルバム)
- [x] ストア掲載文をメーカー横断訴求に更新、スクショ6枚を新UIで撮り直し(DEMO_MODEは公式画像の代わりに `DemoCapsuleArt` を描くので公式画像を含まない)。リリースAABビルド確認済(42.6MB)
- [x] 審査提出版を確定: タグ `v1.0.0`・ブランチ `release/1.0`(コミット `9c98b1e`)。提出用AABは `C:\Users\wioiw\Downloads\devin\gacha_collector\release\gacha_pocket_v1.0.0_739620B3.aab`(SHA256先頭 739620B3、リポジトリ外に保管)。以後 main は段階Bの開発に使い、v1.0の修正は release/1.0 で行う
- [ ] **Play Console提出**(`store/store_listing.md` §8〜9)。データセーフティは引き続き「収集なし」(写真は端末内のみ)。**提出は本店所在地変更の登記完了 → D-U-N-S更新 → Play Consoleのデベロッパー情報(住所・新電話番号)更新・確認完了の後**に行う(デベロッパー情報の変更が再確認を起動して公開が止まるのを避ける)
- **重要(段階B開発中の制約)**: 公開済みアプリ(v1.0)は `main` ブランチの `assets/gacha_data.json` と `assets/app_config.json` をraw URLで直接読む。main側でこれらのスキーマを変える場合は**後方互換(フィールド追加のみ)**にすること。互換を壊す変更が必要なら配信URLをバージョン付きパスに分ける
- 段階B(v1.1・サーバー導入、設計: `store/photo_sharing_design.md`)。決定: Supabase / 初期はニックネーム無し / 承認3人固定
  - [x] B-0: スキーマ `supabase/migrations/0001_photos.sql`(テーブル・RLS・RPC・Storageバケット)、Edge Function骨格 `supabase/functions/judge-photo`、手順書 `supabase/README.md`、法的文書改定案 `store/legal_drafts_phase_b.md`(**docs/ は段階Bリリース時まで書き換えない**)
  - [x] B-1(アプリ側): `CommunityService`(匿名サインイン/同意/アップロード/取り消し/承認・通報・ブロックRPC)、同意ダイアログ、長押しシートに「みんなの図鑑に共有」、マイページに自動共有トグルと匿名ID。`--dart-define=SUPABASE_URL/SUPABASE_ANON_KEY` 未指定なら全て無効(v1.0と同じ挙動)。写真は保存時に `sanitizeJpeg` でEXIF除去・長辺1200px
  - [ ] **ユーザー作業**: Supabaseプロジェクト作成→SQL適用→anonキーを `--dart-define` で渡して実機確認(`supabase/README.md` §1〜3)
  - [ ] B-2: 採用写真の配信(スナップショットJSON → `GachaImage` の優先順位に組み込み)、承認UI、通報UI、Edge Functionの一致度判定、Webhook設定
  - [ ] B-3: いいね・差し替え・実績・クレジット
- Publishing API: `tool/publish_release.dart` + 手順書 `tool/PUBLISHING.md` 作成済(2回目以降のアップデート用。サービスアカウント作成はユーザー作業)。リリースノートは `store/release_notes.txt`

Play Console側(コードと無関係、先行して実施):
- [ ] 組織アカウントの確認状況チェック。2026-09-30期限「Androidデベロッパーの確認」リマインダー(Google Play一斉送信)が届いている → Play Consoleホームで未登録アプリ・アカウント確認状態を確認

v1.1以降: ウィッシュリスト新作のローカル通知、獲得時の写真・メモ・場所、メーカー/作品名タグ検索、Pro買い切り、iOS。

## 3. 技術スタック・環境

- Flutter 3.35.5 / Dart 3.9.2、Windows(PowerShell)。`grep`コマンドは無いので `Select-String` を使う
- 主要パッケージ: shared_preferences(全データ端末内保存)、http、share_plus、cached_network_image(画像キャッシュ)、file_picker(バックアップ復元)、flutter_launcher_icons(dev)、integration_test(dev)
- Androidエミュレータ: `emulator-5554`(Pixel 9 Pro XL、物理1344x2992)。`adb` はPATHに無いので `$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe`。`flutter run` のstdinにはこのツールから書けない(ホットリロード不可→再起動する)
- ガチャデータはGitHub Actions(`.github/workflows/update-gacha-data.yml`、毎週月曜21:00 UTC)が `tool/crawl_gashapon.dart`(バンダイ)と `tool/crawl_makers.dart`(タカラトミーアーツ/キタンクラブ/ブシロードクリエイティブ/SO-TA)で更新し `assets/gacha_data.json` にコミット。アプリは `https://raw.githubusercontent.com/michirug/gacha-collector/main/assets/gacha_data.json` から取得(`lib/gacha_repository.dart`)
- **データJSONのスキーマ**: バンダイは `jan_code` がID(旧形式、`maker`省略=bandai)。他メーカーは `id`(`tta:Y909498` / `kitan:<slug>` / `bushi:<id>` / `sota:<slug>`)、`maker`、`source_url`、`lineup_unknown`(公式にラインナップ名が無く `No.1`〜 の仮アイテムを生成した場合 true)を持つ。アイテムIDは `<seriesId>::<itemTitle>` なので、ラインナップ名を後から変えるとユーザーの記録が外れる
- **メーカーサイトの構造メモ**(2026-09-04確認、robots.txtは全社許可):
  - タカラトミーアーツ: カレンダー `items/gacha/calendar/?ym=YYYYMM` → `items/item.html?n=<code>`。`section#detail .head h2/p`、`.summary` の「」からラインナップ名(個別画像なし)。年齢確認ページ(みまもりフィルター)に飛ぶ商品はパース失敗として捨てる
  - キタンクラブ: `products-sitemap.xml` / `/products/`(新着8件のみ、ページングなし) → `.c-productDetail__*`、`.c-productDetail__pickup-item` に個別名+画像
  - ブシロードクリエイティブ: `wp-sitemap-posts-product-1.xml` / `/product/?pagenum=N` → `.product__specList` dt/dd。ラインナップ名なし
  - SO-TA: `products-sitemap.xml` / `/products/capsuletoy/page/N/` → `.dataArea dl`、`.thumbList img`(先頭=メイン、`CPtenpo`/`-scaled`はPOP画像で除外)。ラインナップ名なし
  - 未対応: ケンエレファント(Shopify、発売月がトピック記事側)、トイズキャビン(BASEショップのみ)
- サーバー・ログイン・広告・課金なし。ユーザーデータは一切収集しない(データセーフティは「収集なし・共有なし」で申告)

## 4. ディレクトリ構成(重要ファイル)

```
lib/
  main.dart               アプリ骨格(GachaCollectorApp/MainScreen、DEMO_MODE分岐)。home_page/my_page/series_page をexport
  home_page.dart          ホーム(メーカーチップ/今月の新作/ウィッシュ発売間近/あと少しでコンプ/来月/発売カレンダー)
  browse_page.dart        検索・メーカー絞り込み一覧。month指定で発売カレンダー(月送り)として動作
  series_page.dart        ItemListPage(シリーズ詳細、_checkCompletion、譲/求カード、公式サイトリンク)
  my_page.dart            マイページ(サマリー/実績/最近の獲得/ウィッシュ/獲得中/バックアップ/法的文書)
  widgets.dart            GachaImage(キャッシュ画像)/MakerBadge/SeriesTile/SeriesPosterCard/SectionHeader/EmptyHint、formatYen
  theme.dart              ブランドテーマ(紫#7C4DFF×ピンク#FF7BAC、クリーム背景)
  backup.dart             BackupService(JSON書き出し→share_plus、file_pickerで復元、追加/置き換え。写真本体は含まない)
  image_policy.dart       ImagePolicy(assets/app_config.json をリモート取得し、メーカー/シリーズ単位で公式画像を非表示)
  user_photo_store.dart   UserPhotoStore(image_pickerで撮影/選択→sanitizeJpegでEXIF除去・縮小→端末内 photos/ に保存、CollectionEntry.photoPath)
  community_service.dart  CommunityService(Supabase: 匿名認証・写真アップロード・取り消し・承認/通報/ブロックRPC。--dart-define未設定なら無効)
  community_consent_dialog.dart  写真共有の初回同意ダイアログ(UGCポリシーの規約同意)
  models.dart             GachaType/Maker/GachaSeries/GachaItem/CollectionEntry、parseJapaneseReleaseDate、parsePriceYen
  gacha_repository.dart   データ取得(raw.githubusercontent)
  collection_store.dart   SharedPreferences永続化・マイグレーション(schema v2)
  achievements.dart       実績定義・評価(12種)
  celebration.dart        コンプ演出ダイアログ(無限アニメ → テストではpumpAndSettle禁止)
  share_card.dart         シェアカード描画(シリーズ/サマリー/譲・求、#ガチャ活ポケット)
  demo_seed.dart          DEMO_MODE用見本データ投入(39アイテム/5シリーズコンプ/17,600円/実績6/12)
android/
  app/build.gradle.kts    key.properties があればrelease署名、無ければdebug署名にフォールバック
  key.properties          ※gitignore。storePassword/keyPassword/keyAlias=upload/storeFile
  upload-keystore.jks     ※gitignore。PKCS12、alias=upload、有効期限10000日
docs/                     GitHub Pages(Jekyll): index.md, privacy_policy.md, terms_of_service.md, _config.yml
store/
  store_listing.md        ストア掲載文・素材パス・提出手順・チェックリスト(Play Console貼り付け元)
  strategy.md             ターゲット/ペルソナ/マネタイズ戦略メモ
  assets/                 icon_512.png, icon_master_1024.png, icon_adaptive_{fg,bg}_1024.png,
                          feature_graphic_1024x500.png, screenshots/01〜05(1080x2400), fonts/MPLUSRounded1c-Bold.ttf
test/
  store_assets/           CustomPainter(store_asset_painters.dart)+ゴールデンテストで素材を生成(通常はskip)
  completion_celebration_test.dart  コンプ演出の回帰テスト(開くだけでは出ない/最後の1個獲得で出る)
  crawl_makers_test.dart  各メーカーのパーサー回帰テスト(test/fixtures/*.html が実ページの保存物)
  backup_test.dart        バックアップのラウンドトリップ/不正ファイル拒否/マージ
  image_policy_test.dart  リモート設定の解析、photoPathの往復
  その他 achievements/collection_migration/release_date(価格・メーカー解析含む)/spend_wishlist/widget_test
integration_test/screenshots_test.dart  + test_driver/integration_test.dart  スクショ自動撮影
tool/crawl_gashapon.dart  バンダイ(gashapon.jp)クローラー
tool/crawl_makers.dart    他メーカークローラー(--maker= --max= --backfill)
tool/publish_release.dart Play Publishing APIで配信(AAB/掲載文/スクショ)。手順: tool/PUBLISHING.md
supabase/                 段階Bのバックエンド定義(migrations/ functions/ README.md)
```

## 5. よく使うコマンド

```powershell
flutter analyze
flutter test                                   # 42テスト(素材生成テストはskip)
flutter build appbundle --release              # → build/app/outputs/bundle/release/app-release.aab

# データ取得(新着のみ / 全件バックフィル。2秒間隔、100件ごとに保存、再実行は既存IDをスキップ)
dart run tool/crawl_gashapon.dart 100
dart run tool/crawl_makers.dart --max=100
dart run tool/crawl_makers.dart --backfill --max=5000 --maker=takaratomy_arts,kitan,bushiroad,sota

# ストア素材の再生成(アイコン・フィーチャーグラフィック)
flutter test test/store_assets --dart-define=GENERATE_ASSETS=true --update-goldens
dart run flutter_launcher_icons                # ランチャーアイコン全密度再生成

# スクリーンショット再撮影(エミュレータ起動後)
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/screenshots_test.dart --dart-define=DEMO_MODE=true -d emulator-5554
```

## 6. 設計上の決定・注意点

- **コンプ演出**: `_checkCompletion(celebrate: false)` を初期ロード時に呼び、既コンプ状態を同期。演出は最後の1個を獲得した瞬間のみ。壊さないこと(`test/completion_celebration_test.dart`が守る)
- **DEMO_MODE**: `--dart-define=DEMO_MODE=true` のときだけ `seedDemoData()` が走る。本番ビルドには影響なし
- **テストでのcelebration.dart**: アニメが無限ループなので `pumpAndSettle` ではなく固定時間 `pump` を使う
- **ウィジェットテストのタップ**: デフォルト画面800x600で下部要素は画面外 → `ensureVisible` してからタップ
- **ターゲット年齢**: 子ども向けUXは作らない(ファミリーポリシー回避)。Play Consoleのターゲット層は13歳以上
- **著作権方針(2026-09-04決定、詳細は store/strategy.md「著作権方針」)**: 「直リンクだから安全」とは考えない(漫画村事件の規範的主体論)。配信データは事実(商品名/価格/発売時期/種類数/ラインナップ名/画像URL)のみで、**説明文は収録しない**(クローラーも出力しない)。公式画像は `BoxFit.contain` で**トリミングせず**©表記を落とさない(リツイート事件の氏名表示権論点)。`GachaImage` には必ず `maker:` を渡し、`ImagePolicy`(`assets/app_config.json` をリモート取得)でメーカー単位/シリーズ単位に即時非表示できる。ストアのスクショに公式画像を入れない。ユーザー写真(`UserPhotoStore`、端末内 photos/)を公式画像より優先表示し、将来は投稿写真で公式画像を置き換えていく(v1.1でサーバー導入)

## 7. 戦略メモ要点(詳細は store/strategy.md)

- **ターゲット**: A層=20-30代女性ガチャ活勢(コア、iOS展開後に本格化)、B層=30-40代コレクター(Android初期主力)。C層(親)は副次的受益者で設計対象外
- **マネタイズ**: v1.0 完全無料・広告なし → v1.x Pro買い切り(¥500-900、B層) → テーマ小課金(A層) → 将来デジタルガチャ(確率表示義務に留意)。競合「ガチャログ」は月額480円サブスクなので買い切りが差別化
- **今後の候補**: iOS展開、Pro機能設計、シェア導線強化

## 8. 次セッションでまずやること

1. このファイルと `store/strategy.md` 冒頭「v1.0再定義」を読む
2. ユーザーにPlay Console提出の進捗を確認(掲載文・スクショ・AABはすべて準備済)
3. 段階B(`store/photo_sharing_design.md`)の未決事項を確認して着手、または v1.1 の他項目(ウィッシュ発売通知・ケンエレファント/トイズキャビン収録)
