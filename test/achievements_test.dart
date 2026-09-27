import 'package:flutter_test/flutter_test.dart';
import 'package:gacha_collector/achievements.dart';
import 'package:gacha_collector/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

GachaSeries buildSeries(String janCode, List<String> itemTitles) {
  return GachaSeries.fromJson({
    'jan_code': janCode,
    'category': 'station',
    'title': 'シリーズ$janCode',
    'price': '300円',
    'items': [
      for (final title in itemTitles) {'title': title, 'image_url': ''},
    ],
  });
}

void main() {
  group('みんなの図鑑への貢献(実績)', () {
    test('採用枚数と「全アイテムが自分の写真」のシリーズ数を集計し、実績判定に使える', () {
      final allSeries = [buildSeries('111', ['a', 'b']), buildSeries('222', ['c', 'd', 'e'])];
      final stats = computeAchievementStats({}, allSeries, contribution: {'111': 2, '222': 1, 'unknown': 5});
      expect(stats.approvedPhotos, 8);
      expect(stats.photoCompletedSeries, 1);
      final byId = {for (final a in allAchievements) a.id: a};
      expect(byId['photo_1']!.isSatisfied(stats), isTrue);
      expect(byId['photo_20']!.isSatisfied(stats), isFalse);
      expect(byId['photo_series']!.isSatisfied(stats), isTrue);
      // 未参加(既定値)なら写真系の実績は付かない
      final none = computeAchievementStats({}, allSeries);
      expect(byId['photo_1']!.isSatisfied(none), isFalse);
    });
  });

  group('computeAchievementStats', () {
    test('獲得数・コンプ数・支出・ダブり数を集計する', () {
      final allSeries = [
        buildSeries('111', ['a', 'b']),
        buildSeries('222', ['c']),
      ];
      final collection = {
        '111::a': CollectionEntry(itemId: '111::a', paidPrice: 300),
        '111::b': CollectionEntry(itemId: '111::b', paidPrice: 300, count: 2),
      };
      final stats = computeAchievementStats(collection, allSeries);
      expect(stats.totalItems, 2);
      expect(stats.completedSeries, 1);
      expect(stats.totalSpend, 300 + 600);
      expect(stats.duplicateCount, 1);
    });

    test('アイテムが空のシリーズはコンプ扱いしない', () {
      final stats = computeAchievementStats({}, [buildSeries('111', [])]);
      expect(stats.completedSeries, 0);
    });

    test('種類数が公式未掲載(lineup_unknown かつ num_types 空)のシリーズは仮アイテムを全部持ってもコンプ扱いしない', () {
      final unknownCount = GachaSeries.fromJson({
        'id': 'tc:1',
        'maker': 'toyscabin',
        'title': '仮アイテムだけのシリーズ',
        'price': '500円',
        'num_types': '',
        'lineup_unknown': true,
        'items': [{'title': 'No.1', 'image_url': ''}],
      });
      final knownCount = GachaSeries.fromJson({
        'id': 'sota:1',
        'maker': 'sota',
        'title': '種類数あり',
        'price': '300円',
        'num_types': '全2種',
        'lineup_unknown': true,
        'items': [{'title': 'No.1', 'image_url': ''}, {'title': 'No.2', 'image_url': ''}],
      });
      expect(unknownCount.lineupCountKnown, isFalse);
      expect(knownCount.lineupCountKnown, isTrue);
      final collection = {
        for (final s in [unknownCount, knownCount])
          for (final i in s.items) i.id: CollectionEntry(itemId: i.id),
      };
      expect(unknownCount.isCompletedBy(collection), isFalse);
      expect(knownCount.isCompletedBy(collection), isTrue);
      expect(computeAchievementStats(collection, [unknownCount, knownCount]).completedSeries, 1);
    });
  });

  group('AchievementService.evaluate', () {
    test('新規解除を返して永続化し、2回目は返さない', () async {
      SharedPreferences.setMockInitialValues({});
      const stats = AchievementStats(
        totalItems: 12,
        completedSeries: 1,
        totalSpend: 0,
        duplicateCount: 0,
      );
      final newly = await AchievementService.evaluate(stats);
      expect(newly.map((a) => a.id),
          containsAll(['first_item', 'items_10', 'comp_1']));

      final second = await AchievementService.evaluate(stats);
      expect(second, isEmpty);

      final unlocked = await AchievementService.loadUnlocked();
      expect(unlocked, containsAll(['first_item', 'items_10', 'comp_1']));
    });

    test('一度解除した実績は条件を満たさなくなっても保持される', () async {
      SharedPreferences.setMockInitialValues({
        'unlocked_achievements': ['comp_1'],
      });
      const stats = AchievementStats(
        totalItems: 0,
        completedSeries: 0,
        totalSpend: 0,
        duplicateCount: 0,
      );
      await AchievementService.evaluate(stats);
      final unlocked = await AchievementService.loadUnlocked();
      expect(unlocked, contains('comp_1'));
    });
  });
}
