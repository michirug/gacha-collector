import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gacha_collector/gacha_repository.dart';
import 'package:gacha_collector/models.dart';

void main() {
  group('parseJapaneseReleaseDate', () {
    test('上旬・中旬・下旬を日付に変換する', () {
      expect(parseJapaneseReleaseDate('2014年03月上旬'), DateTime(2014, 3, 5));
      expect(parseJapaneseReleaseDate('2014年03月中旬'), DateTime(2014, 3, 15));
      expect(parseJapaneseReleaseDate('2014年03月下旬'), DateTime(2014, 3, 25));
    });

    test('未定・第N週表記を扱える', () {
      expect(parseJapaneseReleaseDate('2026年11月未定'), DateTime(2026, 11, 1));
      expect(parseJapaneseReleaseDate('2026年8月第5週'), DateTime(2026, 8, 28));
      expect(parseJapaneseReleaseDate('2025年1月第1週'), DateTime(2025, 1, 1));
    });

    test('年のみ・不正な文字列', () {
      expect(parseJapaneseReleaseDate('2026年未定'), DateTime(2026));
      expect(parseJapaneseReleaseDate('未定'), isNull);
      expect(parseJapaneseReleaseDate(''), isNull);
    });

    test('他メーカーの表記(週発売・発売予定)を扱える', () {
      expect(parseJapaneseReleaseDate('2026年8月（8月31日週発売）'), DateTime(2026, 8, 28));
      expect(parseJapaneseReleaseDate('2026年9月（9月14日週発売）'), DateTime(2026, 9, 14));
      // 再発売の括弧内は元の発売月と異なるので日付には使わない
      expect(parseJapaneseReleaseDate('2025年6月（2026年8月10日週再発売）'), DateTime(2025, 6, 1));
      expect(parseJapaneseReleaseDate('2026年12月下旬発売予定'), DateTime(2026, 12, 25));
      expect(parseJapaneseReleaseDate('2026年8月'), DateTime(2026, 8, 1));
    });
  });

  group('parsePriceYen', () {
    test('各メーカーの価格表記から金額を取り出す', () {
      expect(parsePriceYen('300円'), 300);
      expect(parsePriceYen('300円(税込)'), 300);
      expect(parsePriceYen('500円 (税込)'), 500);
      expect(parsePriceYen('1回400円'), 400);
      expect(parsePriceYen('¥1,000'), 1000);
      expect(parsePriceYen(''), 0);
      expect(parsePriceYen(null), 0);
    });
  });

  group('GachaSeries.fromJson', () {
    test('他メーカーのエントリはidとmakerを読み取る', () {
      final series = GachaSeries.fromJson({
        'id': 'kitan:fkfkowl_flocky',
        'maker': 'kitan',
        'source_url': 'https://kitan.jp/products/fkfkowl_flocky/',
        'category': 'capsule',
        'title': 'ふっくら福福フクロウ フロッキー',
        'price': '300円',
        'release_date': '2026年9月上旬',
        'lineup_unknown': true,
        'items': [
          {'title': 'No.1', 'image_url': ''},
        ],
      });
      expect(series.id, 'kitan:fkfkowl_flocky');
      expect(series.maker, Maker.kitan);
      expect(series.price, 300);
      expect(series.lineupUnknown, isTrue);
      expect(series.sourceUrl, contains('kitan.jp'));
      expect(series.items.single.id, 'kitan:fkfkowl_flocky::No.1');
    });

    test('バンダイの既存エントリはjan_codeがidになりmakerはバンダイ', () {
      final series = GachaSeries.fromJson({
        'jan_code': 4543112873057000,
        'category': 'station',
        'title': 'テスト',
        'price': '200円',
        'release_date': '2014年03月下旬',
        'items': [],
      });
      expect(series.id, '4543112873057000');
      expect(series.maker, Maker.bandai);
      expect(series.gachaType, GachaType.station);
      expect(series.lineupUnknown, isFalse);
    });
  });

  group('parseGachaSeriesList', () {
    test('発売日の新しい順にソートされる', () {
      final jsonString = jsonEncode([
        {
          'jan_code': '111',
          'category': 'station',
          'title': '古い',
          'release_date': '2014年03月下旬',
          'items': [],
        },
        {
          'jan_code': '222',
          'category': 'station',
          'title': '新しい',
          'release_date': '2026年08月上旬',
          'items': [],
        },
        {
          'jan_code': '333',
          'category': 'station',
          'title': '中間',
          'release_date': '2020年01月中旬',
          'items': [],
        },
      ]);
      final result = parseGachaSeriesList(jsonString);
      expect(result.map((s) => s.name).toList(), ['新しい', '中間', '古い']);
    });

    test('同日付は元データの後方(新規追加分)が先に来る', () {
      final jsonString = jsonEncode([
        {
          'jan_code': '111',
          'category': 'station',
          'title': '先頭',
          'release_date': '2020年01月上旬',
          'items': [],
        },
        {
          'jan_code': '222',
          'category': 'station',
          'title': '末尾',
          'release_date': '2020年01月上旬',
          'items': [],
        },
      ]);
      final result = parseGachaSeriesList(jsonString);
      expect(result.map((s) => s.name).toList(), ['末尾', '先頭']);
    });
  });
}
