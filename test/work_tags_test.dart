import 'package:flutter_test/flutter_test.dart';
import 'package:gacha_collector/models.dart';
import 'package:gacha_collector/work_tags.dart';

GachaSeries s(String id, String title) => GachaSeries.fromJson({
      'jan_code': id,
      'category': 'station',
      'title': title,
      'price': '300円',
      'items': [{'title': 'a', 'image_url': ''}],
    });

void main() {
  group('作品名候補の抽出', () {
    test('先頭トークン、引用、英字連結、接頭辞・末尾数字の除去', () {
      expect(leadingWorkCandidate('鬼滅の刃　滅！カプセルラバーマスコット2'), '鬼滅の刃');
      expect(leadingWorkCandidate('ポケモン　つみポーチコレクション'), 'ポケモン');
      expect(leadingWorkCandidate('TOM and JERRY ミニ貯金箱'), 'TOM and JERRY');
      expect(leadingWorkCandidate('Polly Pocket ミニチュアコレクション'), 'Polly Pocket');
      expect(leadingWorkCandidate('豆ガシャ本「地球の歩き方」第四弾'), '地球の歩き方');
      expect(leadingWorkCandidate('【推しの子】 ポーチコレクション'), 'ポーチコレクション');
      expect(leadingWorkCandidate('いぬぱん8'), 'いぬぱん');
      expect(leadingWorkCandidate('#ハッシュタグつける５'), '#ハッシュタグつける');
      expect(leadingWorkCandidate('原神 カプセルコレクションフィギュア vol.2'), '原神');
      expect(leadingWorkCandidate('モブサイコ100 Ⅲ コレクションフィギュア'), 'モブサイコ');
      expect(leadingWorkCandidate('From TV animation ONE PIECE Gasha Portraits'), 'ONE PIECE');
      expect(leadingWorkCandidate('劇場版ハイキュー!! ラバーマスコット'), 'ハイキュー!!');
      expect(leadingWorkCandidate('“ディズニーキャラクター” ふかふか'), 'ディズニーキャラクター');
      expect(leadingWorkCandidate('ピーターラビット™ マスコット'), 'ピーターラビット');
    });

    test('一般語・スケール表記は候補にしない', () {
      expect(leadingWorkCandidate('カプセル トルソー'), isNull);
      expect(leadingWorkCandidate('1/24旗ポールコレクション'), isNull);
      expect(leadingWorkCandidate('ミニチュア 昭和の台所'), isNull);
    });

    test('末尾トークン(タカラトミーアーツ式)', () {
      expect(trailingWorkCandidate('肩ズンFig. ハイキュー!!'), 'ハイキュー!!');
      expect(trailingWorkCandidate('ムーミン'), isNull);
    });
  });

  group('WorkTagIndex', () {
    final all = [
      s('1', 'ポケモン つみポーチ'),
      s('2', 'ポケモン カプセルラバーマスコット'),
      s('3', 'ポケモン フィギュア3'),
      s('4', 'ハイキュー!! ラバーマスコット'),
      s('5', 'ハイキュー!! アクリルスタンド'),
      s('6', 'ハイキュー!! 缶バッジ'),
      s('7', '肩ズンFig. ハイキュー!!'),
      s('8', 'ドラえもん きゃらっぷっぷ'),
      s('9', 'ドラえもん ふかふか'),
      s('10', 'めじるしアクセサリー'),
    ];

    test('3シリーズ以上に現れる先頭トークンだけが作品タグになり、末尾一致も拾う', () {
      final index = WorkTagIndex.build(all);
      expect(index.tags.map((t) => t.name).toList(), ['ハイキュー!!', 'ポケモン']);
      expect(index.byName('ハイキュー!!')!.count, 4); // 肩ズンFig. も含む
      expect(index.tagOf(all[6])?.name, 'ハイキュー!!');
      expect(index.tagOf(all[7]), isNull); // ドラえもんは2件なのでタグ化しない
      expect(index.tagOf(all[9]), isNull);
    });
  });

  group('検索の正規化', () {
    test('かな・全角半角・大文字小文字・記号の違いを無視し、複数語はAND', () {
      expect(normalizeForSearch('ＭＯＯＭＩＮ　つまんで'), 'moominつまんで');
      expect(normalizeForSearch('チイカワ'), 'ちいかわ');
      expect(matchesSearch('ちいかわ', ['チイカワ ハチワレ']), isTrue);
      expect(matchesSearch('moomin マスコット', ['MOOMIN　つまんでつなげてマスコット2']), isTrue);
      expect(matchesSearch('moomin ぬいぐるみ', ['MOOMIN　つまんでつなげてマスコット2']), isFalse);
      expect(matchesSearch('ハイキュー', ['肩ズンFig. ハイキュー!!']), isTrue);
    });
  });
}
