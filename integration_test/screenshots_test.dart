// ストア用スクリーンショットの自動撮影。エミュレータ上で実行する:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/screenshots_test.dart \
//     --dart-define=DEMO_MODE=true -d <emulator-id>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:gacha_collector/demo_seed.dart';
import 'package:gacha_collector/gacha_repository.dart';
import 'package:gacha_collector/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture store screenshots', (tester) async {
    await app.main();
    await tester.pumpAndSettle();
    // 商品画像(ネットワーク)の読み込みを待つ
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();

    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('01_home');

    await tester.tap(find.text('マイページ'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('03_mypage');

    final myPageScrollable = find
        .descendant(of: find.byType(app.MyPage), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('ウィッシュリスト'), 300,
        scrollable: myPageScrollable);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await binding.takeScreenshot('04_wishlist');

    // コンプ済みシリーズの詳細を撮影(修正後: 開いても演出は出ない)
    await tester.scrollUntilVisible(find.text('コンプリート！').first, 300,
        scrollable: myPageScrollable);
    await tester.pumpAndSettle();
    final compTile = find
        .ancestor(
            of: find.text('コンプリート！').first, matching: find.byType(ListTile))
        .first;
    await tester.ensureVisible(compTile);
    await tester.pumpAndSettle();
    await tester.tap(compTile, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    final detailScrollable = find
        .descendant(
            of: find.byType(app.ItemListPage), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('アイテム一覧'), 300,
        scrollable: detailScrollable);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await binding.takeScreenshot('02_series_detail');

    // 収集途中のシリーズを検索から開き、残りを獲得して初回コンプ演出を撮影
    final partial =
        demoCandidateSeries(await GachaRepository.loadAll())[kDemoCompleteSeriesCount];
    final remaining = partial.items.skip(demoPartialOwnedCount(partial)).toList();

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('ホーム'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, partial.name);
    await tester.pumpAndSettle();
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    final partialScrollable = find
        .descendant(
            of: find.byType(app.ItemListPage), matching: find.byType(Scrollable))
        .first;
    for (final item in remaining) {
      final itemText = find.text(item.name).first;
      await tester.scrollUntilVisible(itemText, 250, scrollable: partialScrollable);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(itemText, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 500));
    }
    // 演出ダイアログはアニメーションが無限ループするためpumpAndSettleは使わない
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await binding.takeScreenshot('05_celebration');
  });
}
