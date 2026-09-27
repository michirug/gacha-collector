// 別タブで変えたユーザーデータが、IndexedStack で生きているホーム/マイページに反映されることの回帰テスト。
// 以前はホーム→シリーズ詳細で獲得してもマイページが 0 件のままだった。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gacha_collector/collection_store.dart';
import 'package:gacha_collector/gacha_repository.dart';
import 'package:gacha_collector/main.dart';
import 'package:gacha_collector/models.dart';

GachaSeries _series() => GachaSeries(
      id: 's1',
      name: 'テストシリーズ',
      gachaType: GachaType.other,
      maker: Maker.bandai,
      releaseDate: DateTime(2026, 9),
      releaseDateText: '2026年9月',
      price: 300,
      mainImage: '',
      items: [
        GachaItem(id: 's1::A', name: 'A', image: ''),
        GachaItem(id: 's1::B', name: 'B', image: ''),
      ],
    );

void main() {
  testWidgets('マイページは別タブでの獲得を反映する', (tester) async {
    SharedPreferences.setMockInitialValues({});
    GachaRepository.setForTesting([_series()]);

    await tester.pumpWidget(const GachaCollectorApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // ホームにいる間に(シリーズ詳細での獲得に相当)保存される
    await CollectionStore.save({
      's1::A': CollectionEntry(itemId: 's1::A', acquiredAt: DateTime(2026, 9, 27)),
    });
    await tester.pump();
    expect(find.text('最近の獲得'), findsNothing, reason: '非表示のマイページは重い再集計をしない');

    await tester.tap(find.text('マイページ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('最近の獲得'), findsOneWidget);
    expect(find.text('1'), findsWidgets, reason: '収集アイテム数 1');
  });
}
