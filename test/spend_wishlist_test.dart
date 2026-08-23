import 'package:flutter_test/flutter_test.dart';
import 'package:gacha_collector/collection_store.dart';
import 'package:gacha_collector/models.dart';

void main() {
  group('CollectionEntry', () {
    test('JSONラウンドトリップ(支出情報あり)', () {
      final entry = CollectionEntry(
        itemId: '111::たまドラ',
        isFavorite: true,
        acquiredAt: DateTime(2026, 8, 23, 12, 0),
        paidPrice: 300,
      );
      final restored = CollectionEntry.fromJson(entry.toJson());
      expect(restored.itemId, entry.itemId);
      expect(restored.isFavorite, isTrue);
      expect(restored.acquiredAt, entry.acquiredAt);
      expect(restored.paidPrice, 300);
    });

    test('旧形式JSON(支出情報なし)も読み込める', () {
      final restored =
          CollectionEntry.fromJson({'itemId': 'a', 'isFavorite': false});
      expect(restored.acquiredAt, isNull);
      expect(restored.paidPrice, isNull);
    });
  });

  group('computeSpendSummary', () {
    test('総額と今月分を計算する', () {
      final now = DateTime(2026, 8, 23);
      final entries = [
        CollectionEntry(
            itemId: '111::a',
            acquiredAt: DateTime(2026, 8, 1),
            paidPrice: 300),
        CollectionEntry(
            itemId: '111::b',
            acquiredAt: DateTime(2026, 7, 31),
            paidPrice: 200),
        CollectionEntry(itemId: '222::c'),
      ];
      final priceBySeriesId = {'111': 300, '222': 500};
      final summary = computeSpendSummary(entries, priceBySeriesId, now);
      expect(summary.total, 300 + 200 + 500);
      expect(summary.thisMonth, 300);
    });

    test('価格情報がないアイテムは0円として扱う', () {
      final summary = computeSpendSummary(
        [CollectionEntry(itemId: '999::x')],
        {},
        DateTime(2026, 8, 23),
      );
      expect(summary.total, 0);
      expect(summary.thisMonth, 0);
    });
  });
}
