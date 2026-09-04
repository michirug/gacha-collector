import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/crawl_makers.dart';

String fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('タカラトミーアーツ', () {
    test('詳細ページからラインナップ名を抽出できる', () {
      final entry = TakaraTomyArtsCrawler().parseDetail(
        fixture('takaratomy_arts_item.html'),
        (id: 'tta:Y909498', url: 'https://www.takaratomy-arts.co.jp/items/item.html?n=Y909498'),
      )!;
      expect(entry['id'], 'tta:Y909498');
      expect(entry['maker'], 'takaratomy_arts');
      expect(entry['title'], 'サンリオキャラクターズ ふわわフロッキーマスコット2 ～ハンサムブルー～');
      expect(entry['price'], '300円(税込)');
      expect(entry['release_date'], '2026年8月（8月31日週発売）');
      expect(entry['num_types'], '全6種');
      expect(entry['lineup_unknown'], false);
      final items = entry['items'] as List;
      expect(items.map((i) => i['title']).toList(), [
        'ポチャッコ', 'けろけろけろっぴ', 'バッドばつ丸', 'ハンギョドン', 'タキシードサム', 'あひるのペックル',
      ]);
      expect(entry['image_url'], contains('Y909498_b.jpg'));
    });
  });

  group('キタンクラブ', () {
    test('詳細ページから個別画像付きのラインナップを抽出できる', () {
      final entry = KitanCrawler().parseDetail(
        fixture('kitan_item.html'),
        (id: 'kitan:fkfkowl_flocky', url: 'https://kitan.jp/products/fkfkowl_flocky/'),
      )!;
      expect(entry['title'], 'ふっくら福福フクロウ フロッキー');
      expect(entry['price'], '300円');
      expect(entry['release_date'], '2026年9月上旬');
      expect(entry['num_types'], '全6種');
      expect(entry['lineup_unknown'], false);
      final items = entry['items'] as List;
      expect(items.length, 6);
      expect(items.first['title'], 'フクロウ');
      expect(items.first['image_url'], contains('fukurou.jpg'));
    });
  });

  group('ブシロードクリエイティブ', () {
    test('ラインナップ名が無い場合は種類数ぶんの仮アイテムを生成する', () {
      final entry = BushiroadCrawler().parseDetail(
        fixture('bushiroad_item.html'),
        (id: 'bushi:10165', url: 'https://capsule.bushiroad-creative.com/product/10165/'),
      )!;
      expect(entry['title'], 'ジョジョの奇妙な冒険 ダイヤモンドは砕けない コレクションフィギュアRICH');
      expect(entry['price'], '500円 (税込)');
      expect(entry['release_date'], '2026年12月下旬発売予定');
      expect(entry['target_age'], '15歳以上');
      expect(entry['lineup_unknown'], true);
      final items = entry['items'] as List;
      expect(items.map((i) => i['title']).toList(), ['No.1', 'No.2', 'No.3', 'No.4', 'No.5']);
    });
  });

  group('SO-TA', () {
    test('サムネイルを個別画像として割り当て、店頭POP画像は除外する', () {
      final entry = SotaCrawler().parseDetail(
        fixture('sota_item.html'),
        (id: 'sota:kaimu_no_sei', url: 'https://www.so-ta.com/products_detail/capsuletoy/kaimu_no_sei/'),
      )!;
      expect(entry['title'], '海霧の精');
      expect(entry['price'], '500円');
      expect(entry['release_date'], '2026年8月');
      expect(entry['lineup_unknown'], true);
      final items = entry['items'] as List;
      expect(items.length, 4);
      expect(items[0]['image_url'], contains('img_ao.png'));
      for (final item in items) {
        expect(item['image_url'], isNot(contains('CPtenpo')));
      }
    });
  });

  group('extractQuotedNames', () {
    test('作品名の引用はラインナップとして拾わない', () {
      const text = 'TVアニメ「その着せ替え人形は恋をする」より、マスコットが登場！';
      expect(extractQuotedNames(text, 5), isEmpty);
    });
    test('「A、B、C」形式を分割する', () {
      const text = 'ラインナップは「フクロウ、メンフクロウ、シロフクロウ」の全3種。';
      expect(extractQuotedNames(text, 3), ['フクロウ', 'メンフクロウ', 'シロフクロウ']);
    });
    test('引用が種類数より多い場合は末尾から採用する', () {
      const text = '「シリーズ名」が登場。ラインナップは「A」「B」「C」の全3種。';
      expect(extractQuotedNames(text, 3), ['A', 'B', 'C']);
    });
  });
}
