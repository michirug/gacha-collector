import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gacha_collector/community_photos.dart';
import 'package:gacha_collector/image_policy.dart';
import 'package:gacha_collector/widgets.dart';

import '../tool/export_community_photos.dart';

void main() {
  tearDown(() {
    CommunityPhotos.snapshot.value = const CommunityPhotoSnapshot();
    CommunityPhotos.blockedPosters.value = {};
    ImagePolicy.hiddenSeries.value = {};
  });

  group('配信スナップショットの生成(tool/export_community_photos.dart)', () {
    final rows = <Map<String, dynamic>>[
      {'id': 'ph1', 'item_id': 'kitan:owl::フクロウ', 'series_id': 'kitan:owl', 'maker': 'kitan', 'public_url': 'https://cdn/a.jpg', 'poster_id': 'p1', 'likes': 0, 'auto_score': 0.9, 'approved_at': '2026-09-01T00:00:00Z'},
      {'item_id': 'kitan:owl::ミミズク', 'series_id': 'kitan:owl', 'maker': 'kitan', 'public_url': 'https://cdn/b.jpg', 'poster_id': 'p2', 'likes': 40, 'auto_score': 0.7, 'approved_at': '2026-09-02T00:00:00Z'},
      {'item_id': 'sota:cat::No.1', 'series_id': 'sota:cat', 'maker': 'sota', 'public_url': null, 'poster_id': 'p3', 'likes': 0, 'auto_score': null, 'approved_at': null},
    ];

    test('アイテムごとのURLと、シリーズ代表(最良スコア)を出力し、URLの無い行は捨てる', () {
      final snapshot = buildSnapshot(rows);
      final items = snapshot['items'] as Map;
      final series = snapshot['series'] as Map;
      expect(items.keys, ['kitan:owl::フクロウ', 'kitan:owl::ミミズク']);
      expect(items['kitan:owl::フクロウ'], {'url': 'https://cdn/a.jpg', 'poster': 'p1', 'id': 'ph1'});
      // 0.7*0.5 + 40/100 = 0.75 > 0.9*0.5 = 0.45 なのでミミズクが代表
      expect(series, {'kitan:owl': {'url': 'https://cdn/b.jpg', 'poster': 'p2'}});
      expect(snapshot['generated_at'], isA<String>());
    });

    test('generated_at だけの差分は変更とみなさない', () {
      final snapshot = buildSnapshot(rows);
      final existing = Map<String, dynamic>.from(snapshot)..['generated_at'] = '2000-01-01T00:00:00Z';
      expect(hasContentChanged(jsonEncode(existing), snapshot), isFalse);
      expect(hasContentChanged(jsonEncode({'items': {}, 'series': {}}), snapshot), isTrue);
      expect(hasContentChanged('broken', snapshot), isTrue);
    });
  });

  group('アプリ側の読み込み(CommunityPhotos)', () {
    test('items/series を解析し、URLの無いエントリは無視する', () {
      CommunityPhotos.apply(jsonEncode({
        'generated_at': 'x',
        'items': {'a::1': {'url': 'https://cdn/1.jpg', 'poster': 'p1'}, 'a::2': {'url': ''}, 'a::3': 'https://cdn/3.jpg'},
        'series': {'a': {'url': 'https://cdn/1.jpg'}},
      }));
      expect(CommunityPhotos.forItem('a::1')?.url, 'https://cdn/1.jpg');
      expect(CommunityPhotos.forItem('a::1')?.posterId, 'p1');
      expect(CommunityPhotos.forItem('a::2'), isNull);
      expect(CommunityPhotos.forItem('a::3')?.url, 'https://cdn/3.jpg');
      expect(CommunityPhotos.forSeries('a')?.url, 'https://cdn/1.jpg');
      expect(CommunityPhotos.forSeries('b'), isNull);
      expect(CommunityPhotos.forItem(null), isNull);
    });

    test('壊れたJSONは無視して直前の状態を保つ', () {
      CommunityPhotos.apply('{"items":{"a::1":{"url":"https://cdn/1.jpg"}}}');
      CommunityPhotos.apply('not json');
      expect(CommunityPhotos.forItem('a::1'), isNotNull);
    });

    test('GachaImage はアイテム写真を優先し、無ければシリーズ代表、非表示シリーズなら出さない', () {
      CommunityPhotos.apply('{"items":{"a::1":{"url":"https://cdn/item.jpg"}},"series":{"a":{"url":"https://cdn/series.jpg"}}}');
      expect(GachaImage.communityPhotoFor(itemId: 'a::1', seriesId: 'a')?.url, 'https://cdn/item.jpg');
      expect(GachaImage.communityPhotoFor(itemId: 'a::2', seriesId: 'a'), isNull);
      expect(GachaImage.communityPhotoFor(seriesId: 'a')?.url, 'https://cdn/series.jpg');
      ImagePolicy.apply('{"hide_series":["a"]}');
      expect(GachaImage.communityPhotoFor(itemId: 'a::1', seriesId: 'a'), isNull);
    });

    test('ブロックした投稿者の写真は端末側で除外され、photo id も読める', () {
      CommunityPhotos.apply('{"items":{"a::1":{"url":"https://cdn/1.jpg","poster":"bad","id":"ph1"},"a::2":{"url":"https://cdn/2.jpg","poster":"good"}}}');
      expect(CommunityPhotos.forItem('a::1')?.photoId, 'ph1');
      CommunityPhotos.blockedPosters.value = {'bad'};
      expect(CommunityPhotos.forItem('a::1'), isNull);
      expect(CommunityPhotos.forItem('a::2')?.url, 'https://cdn/2.jpg');
      CommunityPhotos.blockedPosters.value = {};
      expect(CommunityPhotos.forItem('a::1'), isNotNull);
    });
  });
}
