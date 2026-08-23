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
