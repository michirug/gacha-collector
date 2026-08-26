import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gacha_collector/main.dart';
import 'package:gacha_collector/models.dart';

GachaSeries _buildSeries() => GachaSeries(
      id: 'S1',
      name: 'テストシリーズ',
      gachaType: GachaType.station,
      releaseDate: DateTime(2026, 8, 1),
      price: 300,
      mainImage: '',
      items: [
        GachaItem(id: 'S1::a', name: 'アイテムA', image: ''),
        GachaItem(id: 'S1::b', name: 'アイテムB', image: ''),
      ],
    );

String _collectionJson(List<String> ids) => jsonEncode({
      for (final id in ids)
        id: {'itemId': id, 'isFavorite': false, 'count': 1},
    });

void main() {
  testWidgets('コンプ済みシリーズを開いただけでは演出を出さない', (tester) async {
    SharedPreferences.setMockInitialValues({
      'collection_schema_version': 2,
      'collection': _collectionJson(['S1::a', 'S1::b']),
    });
    await tester.pumpWidget(MaterialApp(home: ItemListPage(series: _buildSeries())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('シリーズコンプリート！'), findsNothing);
    expect(find.textContaining('コンプリート済み'), findsOneWidget);
  });

  testWidgets('最後のアイテムを獲得したときに演出を出す', (tester) async {
    SharedPreferences.setMockInitialValues({
      'collection_schema_version': 2,
      'collection': _collectionJson(['S1::a']),
    });
    await tester.pumpWidget(MaterialApp(home: ItemListPage(series: _buildSeries())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.ensureVisible(find.text('アイテムB'));
    await tester.pump();
    await tester.tap(find.text('アイテムB'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('シリーズコンプリート！'), findsOneWidget);
  });
}
