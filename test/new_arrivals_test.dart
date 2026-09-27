import 'package:flutter_test/flutter_test.dart';
import 'package:gacha_collector/models.dart';
import 'package:gacha_collector/new_arrivals_notifier.dart';

GachaSeries s(String id, String name, {String maker = 'bandai', String release = '2026年11月'}) =>
    GachaSeries.fromJson({
      'id': id,
      'maker': maker,
      'title': name,
      'price': '300円',
      'release_date': release,
      'items': [
        {'title': 'A', 'image_url': ''},
      ],
    });

void main() {
  final existing = [
    s('1', 'ポケモン つみポーチ'),
    s('2', 'ポケモン ラバーマスコット'),
    s('3', 'ポケモン フィギュア'),
    s('4', 'ちいかわ マスコット'),
    s('5', 'ちいかわ 缶バッジ'),
    s('6', 'ちいかわ キーホルダー'),
  ];
  final added = [
    s('n1', '名探偵コナン スイング', maker: 'takaratomy_arts'),
    s('n2', 'ちいかわ ぬいぐるみ', release: '2026年12月'),
    s('n3', 'ポケモン カプセルフィギュア'),
    s('n4', 'ELLYLAND フィギュアコレクション', maker: 'kenelephant'),
    s('n5', '1/64 シビック', maker: 'toyscabin'),
  ];

  test('集めている作品の新作を先頭に置き、タップでそれを開く', () {
    final m = buildNewArrivalsMessage(
      added: added,
      allSeries: [...existing, ...added],
      ownedItemIds: {'4::A'}, // ちいかわを1つ持っている
      wishlist: {'1'}, // ポケモンをウィッシュ
    );
    expect(m.title, 'ちいかわ の新作など5件が追加されました');
    expect(m.body.split('\n'), [
      '・ちいかわ ぬいぐるみ(2026年12月)',
      '・ポケモン カプセルフィギュア(2026年11月)',
      '・名探偵コナン スイング(2026年11月)',
      'ほか2件',
    ]);
    expect(m.payloadSeriesId, 'n2');
  });

  test('該当する作品が無ければメーカー別の件数を見出しにし、payload は無し', () {
    final m = buildNewArrivalsMessage(
      added: added,
      allSeries: [...existing, ...added],
      ownedItemIds: {},
      wishlist: {},
    );
    expect(m.title, '新作5件が追加されました(バンダイ2・タカラトミーアーツ1・ケンエレファント1)');
    expect(m.payloadSeriesId, isNull);
    expect(m.body.split('\n').length, 4);
  });

  test('件数が少なければ「ほかN件」を付けない', () {
    final m = buildNewArrivalsMessage(
      added: added.take(2).toList(),
      allSeries: [...existing, ...added],
      ownedItemIds: {},
      wishlist: {},
    );
    expect(m.body.contains('ほか'), isFalse);
  });
}
