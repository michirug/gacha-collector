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

**コード側の作業はすべて完了・push済み(最新コミット `3d5cf3c`)。残作業はPlay Console上の手動操作のみ。**

- [x] Android署名設定・リリースAABビルド(`build/app/outputs/bundle/release/app-release.aab`、42MB)
- [x] アプリ名・ハッシュタグの全体反映
- [x] プライバシーポリシー・利用規約のGitHub Pages公開
- [x] ストア素材(アイコン/フィーチャーグラフィック/スクショ5枚)生成
- [x] コンプ演出を「初回コンプ時のみ」に修正(回帰テスト付き)
- [x] 開発者名をPlay Consoleに設定
- [ ] **Play Consoleに掲載文を入力**(貼り付け元: `store/store_listing.md`)
- [ ] **AABをアップロードして審査提出**
- [ ] 審査結果に応じた対応(データセーフティ・画像著作権指摘など)

Play Console提出手順の詳細は `store/store_listing.md` §8〜9 を参照。

## 3. 技術スタック・環境

- Flutter 3.35.5 / Dart 3.9.2、Windows(PowerShell)。`grep`コマンドは無いので `Select-String` を使う
- 主要パッケージ: shared_preferences(全データ端末内保存)、http、share_plus、flutter_launcher_icons(dev)、integration_test(dev)
- Androidエミュレータ: `emulator-5554`(スクショ撮影に使用)
- ガチャデータはGitHub Actions(`.github/workflows/update-gacha-data.yml`、毎週月曜21:00 UTC)が `tool/crawl_gashapon.dart` で更新し `assets/gacha_data.json` にコミット。アプリは `https://raw.githubusercontent.com/michirug/gacha-collector/main/assets/gacha_data.json` から取得(`lib/gacha_repository.dart`)
- サーバー・ログイン・広告・課金なし。ユーザーデータは一切収集しない(データセーフティは「収集なし・共有なし」で申告)

## 4. ディレクトリ構成(重要ファイル)

```
lib/
  main.dart               UI本体(MainScreen/HomePage/ItemListPage/MyPage、_checkCompletion、DEMO_MODE分岐)
  models.dart             GachaType/GachaSeries/GachaItem/CollectionEntry、parseJapaneseReleaseDate
  gacha_repository.dart   データ取得(raw.githubusercontent)
  collection_store.dart   SharedPreferences永続化・マイグレーション(schema v2)
  achievements.dart       実績定義・評価(12種)
  celebration.dart        コンプ演出ダイアログ(無限アニメ → テストではpumpAndSettle禁止)
  share_card.dart         シェアカード描画(#ガチャ活ポケット)
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
  その他 achievements/collection_migration/release_date/spend_wishlist/widget_test
integration_test/screenshots_test.dart  + test_driver/integration_test.dart  スクショ自動撮影
tool/crawl_gashapon.dart  クローラー
```

## 5. よく使うコマンド

```powershell
flutter analyze
flutter test                                   # 22テスト(素材生成テストはskip)
flutter build appbundle --release              # → build/app/outputs/bundle/release/app-release.aab

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
- **画像**: 商品画像はメーカー公式サイトから取得して表示(著作権指摘が来たら対応が必要)

## 7. 戦略メモ要点(詳細は store/strategy.md)

- **ターゲット**: A層=20-30代女性ガチャ活勢(コア、iOS展開後に本格化)、B層=30-40代コレクター(Android初期主力)。C層(親)は副次的受益者で設計対象外
- **マネタイズ**: v1.0 完全無料・広告なし → v1.x Pro買い切り(¥500-900、B層) → テーマ小課金(A層) → 将来デジタルガチャ(確率表示義務に留意)。競合「ガチャログ」は月額480円サブスクなので買い切りが差別化
- **今後の候補**: iOS展開、Pro機能設計、シェア導線強化

## 8. 次セッションでまずやること

1. このファイルと `store/store_listing.md` §9チェックリストを読む
2. ユーザーにPlay Console提出の進捗(掲載文入力/AABアップロード/審査結果)を確認
3. 審査指摘があれば対応、なければ次フェーズ(iOS・Pro機能など)の相談へ
