import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gacha_collector/backup.dart';
import 'package:gacha_collector/models.dart';

void main() {
  final collection = {
    'kitan:a::フクロウ': CollectionEntry(
      itemId: 'kitan:a::フクロウ',
      acquiredAt: DateTime(2026, 9, 1),
      paidPrice: 300,
      count: 2,
    ),
    '123::No.1': CollectionEntry(itemId: '123::No.1'),
  };

  test('書き出したバックアップを同じ内容で読み戻せる', () {
    final json = jsonEncode(
        BackupService.buildBackup(collection, {'kitan:a', '123'}, DateTime(2026, 9, 4)));
    final parsed = BackupService.parseBackup(json);
    expect(parsed.wishlist, {'kitan:a', '123'});
    expect(parsed.collection.length, 2);
    expect(parsed.collection['kitan:a::フクロウ']!.count, 2);
    expect(parsed.collection['kitan:a::フクロウ']!.paidPrice, 300);
    expect(parsed.collection['kitan:a::フクロウ']!.acquiredAt, DateTime(2026, 9, 1));
  });

  test('別アプリのJSONや壊れたJSONは拒否する', () {
    expect(() => BackupService.parseBackup('{"app":"other","collection":{}}'),
        throwsFormatException);
    expect(() => BackupService.parseBackup('{"app":"gacha_collector","collection":[]}'),
        throwsFormatException);
    expect(() => BackupService.parseBackup('not json'), throwsFormatException);
  });

  test('マージは既存を残し、所持数は大きい方を採用する', () {
    final incoming = {
      'kitan:a::フクロウ': CollectionEntry(itemId: 'kitan:a::フクロウ', count: 1),
      'new::x': CollectionEntry(itemId: 'new::x', count: 3),
    };
    final merged = BackupService.merge(collection, incoming);
    expect(merged.length, 3);
    expect(merged['kitan:a::フクロウ']!.count, 2);
    expect(merged['new::x']!.count, 3);
    expect(merged.containsKey('123::No.1'), isTrue);
  });
}
