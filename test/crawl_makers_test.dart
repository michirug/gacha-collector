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

  group('ケンエレファント', () {
    test('LINEUP ブロックからラインナップ名、カプセル価格、og:image を取る', () {
      final entry = KenElephantCrawler().parseDetail(
        fixture('kenelephant_item.html'),
        (id: 'kenele:gc0733', url: 'https://kenelestore.jp/products/gc0733c'),
      )!;
      expect(entry['title'], '冷蔵庫専用フィギュア たまごのふりして');
      expect(entry['price'], '500円');
      expect(entry['num_types'], '全6種');
      expect(entry['lineup_unknown'], false);
      expect(entry['image_url'], 'https://kenelestore.jp/cdn/shop/files/gc0733-01.jpg?v=1783669940');
      final items = entry['items'] as List;
      // 「※…」の注記は名前から落とす
      expect(items.map((i) => i['title']).toList(), ['ニンゲン', 'ヒグマ', 'ペンギン', 'シロクマ', 'イエティ', 'ニワトリ']);
    });

    test('古いページの本文「■ラインナップ 全N種 ・名前(サイズ)」からも取れ、次の見出しで止まる', () {
      final lines = [
        '恐怖と笑いの天才のグッズコレクション！第2弾！',
        '■ラインナップ 全6種',
        '・ハンカチ（約W400×H400mm）',
        '・小銭入れ（約H72mm）',
        '・缶ミラー（約W63mmmm）',
        '・3連アクリルキーホルダー（約W35~41mm）',
        '・アクリルキーホルダー (約H62mm)',
        '・エコバッグ（約H280mm）※色は選べません',
        '■ 作家',
        '・作家の紹介行(拾わない)',
        '★ 中身につきまして',
        '・全種類揃うコンプリートBOXです。',
      ];
      final result = KenElephantCrawler.parseLineupLines(lines, requireHeading: true);
      expect(result.typeCount, 6);
      expect(result.names, ['ハンカチ', '小銭入れ', '缶ミラー', '3連アクリルキーホルダー', 'アクリルキーホルダー', 'エコバッグ']);
      // 見出しが無い本文からは拾わない
      expect(KenElephantCrawler.parseLineupLines(['・注意事項A', '・注意事項B'], requireHeading: true).names, isEmpty);
    });

    test('発売月は tag の mcatem__N月発売 と公開日から年月を組む', () {
      expect(KenElephantCrawler.releaseDateFrom(['GC', 'mcatem__9月発売'], DateTime(2026, 6, 10)), '2026年9月');
      // 公開が10月で発売タグが1月 → 翌年
      expect(KenElephantCrawler.releaseDateFrom(['mcatem__1月発売'], DateTime(2026, 10, 1)), '2027年1月');
      // 発売月が公開月の直前(発売後に公開)は同年
      expect(KenElephantCrawler.releaseDateFrom(['mcatem__6月発売'], DateTime(2026, 7, 1)), '2026年6月');
      // タグが無ければ公開年月
      expect(KenElephantCrawler.releaseDateFrom(['GC'], DateTime(2026, 7, 1)), '2026年7月');
      expect(KenElephantCrawler.releaseDateFrom(const [], null), '');
      // 2023年1月の一括移行分は発売時期不明
      expect(KenElephantCrawler.releaseDateFrom(['GC'], DateTime(2023, 1, 20)), '');
    });
  });

  group('トイズキャビン', () {
    test('Project 行から商品名と価格、Client 行から発売月、本文から種類数を取る', () {
      final entry = ToysCabinCrawler().parseDetail(
        fixture('toyscabin_item.html'),
        (id: 'tc:20260904_1488', url: 'https://toyscabin.com/product/20260904_1488.php'),
      )!;
      expect(entry['title'], 'YAMAHA バイクラバーキーホルダー レジェンド編');
      expect(entry['price'], '400円');
      expect(entry['release_date'], '2026年12月');
      expect(entry['num_types'], '全6種');
      expect(entry['lineup_unknown'], true);
      expect(entry['image_url'], startsWith('https://toyscabin.com/product/upfiles/2026/09/'));
      expect((entry['items'] as List).length, 6);
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
