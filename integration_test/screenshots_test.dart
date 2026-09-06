// ストア用スクリーンショットの自動撮影。エミュレータ上で実行する:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/screenshots_test.dart \
//     --dart-define=DEMO_MODE=true -d <emulator-id>
// DEMO_MODE では公式画像の代わりに自前の見本イラスト(DemoCapsuleArt)が描かれるため、
// 生成されるスクリーンショットにメーカーの画像は含まれない。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:gacha_collector/demo_seed.dart';
import 'package:gacha_collector/gacha_repository.dart';
import 'package:gacha_collector/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, [int seconds = 2]) async {
    await tester.pumpAndSettle();
    await tester.pump(Duration(seconds: seconds));
    await tester.pumpAndSettle();
  }

  testWidgets('capture store screenshots', (tester) async {
    await app.main();
    await settle(tester, 4);

    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('01_home');

    // マイページ(サマリー・実績)
    await tester.tap(find.text('マイページ'));
    await settle(tester, 3);
    await binding.takeScreenshot('03_mypage');

    final myPageScrollable = find
        .descendant(of: find.byType(app.MyPage), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('ウィッシュリスト'), 300,
        scrollable: myPageScrollable);
    await settle(tester);
    await binding.takeScreenshot('04_wishlist');

    // コンプ済みシリーズ(見本データの先頭)の詳細を撮影(開いても演出は出ない)
    final candidates = demoCandidateSeries(await GachaRepository.loadAll());
    final completed = candidates.first;
    await tester.scrollUntilVisible(find.text(completed.name).first, 300,
        scrollable: myPageScrollable);
    await settle(tester, 1);
    await tester.tap(find.text(completed.name).first, warnIfMissed: false);
    await settle(tester, 3);
    final detailScrollable = find
        .descendant(
            of: find.byType(app.ItemListPage), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('アイテム一覧'), 300,
        scrollable: detailScrollable);
    await settle(tester);
    await binding.takeScreenshot('02_series_detail');

    // 収集途中のシリーズを検索から開く
    final partial = candidates[kDemoCompleteSeriesCount];
    final remaining = partial.items.skip(demoPartialOwnedCount(partial)).toList();

    await tester.pageBack();
    await settle(tester, 1);
    await tester.tap(find.text('ホーム'));
    await settle(tester, 1);
    await tester.tap(find.byIcon(Icons.search).first);
    await settle(tester, 1);
    await tester.enterText(find.byType(TextField).first, partial.name);
    await settle(tester, 1);
    tester.binding.focusManager.primaryFocus?.unfocus();
    await settle(tester, 1);
    await tester.tap(find.text(partial.name).last, warnIfMissed: false);
    await settle(tester, 3);

    // 譲/求カード(ダブりなし・未獲得あり)
    await tester.tap(find.byIcon(Icons.swap_horiz));
    await settle(tester, 1);
    await binding.takeScreenshot('06_trade_card');
    await tester.tap(find.text('閉じる'));
    await settle(tester, 1);

    // 残りを獲得して初回コンプ演出を撮影
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
