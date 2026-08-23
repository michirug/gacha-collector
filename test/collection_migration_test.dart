import 'package:flutter_test/flutter_test.dart';
import 'package:gacha_collector/collection_store.dart';
import 'package:gacha_collector/models.dart';

GachaSeries buildSeries(String janCode, List<String> itemTitles) {
  return GachaSeries.fromJson({
    'jan_code': janCode,
    'category': 'station',
    'title': 'シリーズ$janCode',
    'items': [
      for (final title in itemTitles) {'title': title, 'image_url': ''},
    ],
  });
}

void main() {
  group('GachaSeries.fromJson', () {
    test('アイテムIDがシリーズIDで名前空間化される', () {
      final series = buildSeries('111', ['たまドラ', 'ヘラ']);
      expect(series.id, '111');
      expect(series.items[0].id, '111::たまドラ');
      expect(series.items[1].id, '111::ヘラ');
    });

    test('別シリーズの同名アイテムは異なるIDになる', () {
      final a = buildSeries('111', ['たまドラ']);
      final b = buildSeries('222', ['たまドラ']);
      expect(a.items[0].id, isNot(b.items[0].id));
    });
  });

  group('migrateCollectionKeys', () {
    final allSeries = [
      buildSeries('111', ['たまドラ', 'ヘラ']),
      buildSeries('222', ['たまドラ']),
    ];

    test('旧キーは該当する全シリーズの複合IDへ展開される', () {
      final oldMap = {
        'たまドラ': {'itemId': 'たまドラ', 'isFavorite': false},
      };
      final newMap = migrateCollectionKeys(oldMap, allSeries);
      expect(newMap.keys, containsAll(['111::たまドラ', '222::たまドラ']));
      expect(newMap.containsKey('たまドラ'), isFalse);
    });

    test('isFavoriteが引き継がれる', () {
      final oldMap = {
        'ヘラ': {'itemId': 'ヘラ', 'isFavorite': true},
      };
      final newMap = migrateCollectionKeys(oldMap, allSeries);
      expect(newMap['111::ヘラ']['isFavorite'], isTrue);
    });

    test('一致しない旧キーはそのまま保持される', () {
      final oldMap = {
        '不明アイテム': {'itemId': '不明アイテム', 'isFavorite': false},
      };
      final newMap = migrateCollectionKeys(oldMap, allSeries);
      expect(newMap.containsKey('不明アイテム'), isTrue);
    });
  });
}
