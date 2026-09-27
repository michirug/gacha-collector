import 'models.dart';

// 作品名タグ: 商品名から作品(キャラクター/ブランド)名を推定し、複数シリーズにまたがるものだけをタグにする。
// サーバーも手作業のタグ付けも要らないように、データ全体の統計から決める。
//   1. 「作品名」『作品名』の引用があればそれ
//   2. 無ければ 商品名の先頭トークン(英字が続く場合は連結。「【…】」の接頭辞や末尾の数字・弾数は除く)
//   3. 先頭トークンとして3シリーズ以上に現れるものを作品名とみなす(商品種別を表す一般語は除外)
//   4. タカラトミーアーツ式の「肩ズンFig. ハイキュー!!」のように末尾に作品名が来る場合も、
//      末尾トークンが 3 で決まった作品名なら拾う

const int kWorkTagMinSeries = 3;

final RegExp _bracketPrefix = RegExp(r'^[【\[][^】\]]*[】\]]\s*');
// 「From TV animation ONE PIECE」「TVアニメ『…』」「劇場版 …」の媒体接頭辞
final RegExp _mediaPrefix = RegExp(r'^(From TV animation|TVアニメ|TVアニメーション|劇場版|映画|アニメ)[\s\u3000]*', caseSensitive: false);
final RegExp _quoted = RegExp(r'[「『]([^」』]{1,30})[」』]');
final RegExp _trailingNumber = RegExp(
    r'(\s*(vol\.?|Vol\.?|VOL\.?|第|その|Part|part|PART|#)?\s*[0-9０-９]+(弾|巻|期|st|nd|rd|th)?|\s*[ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩ]+)$');
final RegExp _latin = RegExp(r'^[A-Za-z0-9&.\-]+$');
final RegExp _separator = RegExp(r'[\s\u3000／/]+');

// 商品種別・形容の一般語(先頭に来ても作品名ではない)
const Set<String> _genericWords = {
  'カプセル', 'capsule', 'ミニチュア', 'ミニ', 'フィギュア', 'マスコット', 'コレクション', 'ガシャポン', 'ガチャ',
  'プレミアム', 'ビッグ', 'でか', 'リアル', 'ソフビ', 'まるごと', '豆ガシャ本', 'アクリル', 'ラバー', 'ぬいぐるみ',
  'ミニチュアコレクション', 'カプセルトイ', 'あつまれ', 'ざ', 'the', 'new', 'いきもの', '動物', 'ねこ', 'いぬ',
  'かわいい', '劇場版', '映画', '限定', 'バンダイナムコアミューズメント限定', 'ガシャポン限定', '数量限定', 'アニメ',
  // メーカーの商品ライン名。「ハグコット サンリオキャラクターズ」のように作品名が後ろに来るので先頭からは外し、
  // 末尾トークンで作品名を拾わせる(2026-09-27。タグ一覧の上位に商品ラインが並んでいたため)
  'めじるしアクセサリー', 'カプセルラバーマスコット', 'ラバーマスコット', 'カプキャラ', 'ハグコット', 'はぐこっとーと',
  '肩ズンfig.', '肩ズンfig', 'putitto', 'まちぼうけ', 'ならぶんです。', 'ならぶんです', 'ringcolle!', 'ringcolle',
  'gasha', 'gasha portraits', 'gashabox', 'でふぉラバ!', 'でふぉラバ！', 'コレキャラ！', 'コレキャラ!', 'ぴた！でふぉめ',
  'ぴた!でふぉめ', 'かぷばっぐ', 'アニコラ', 'ガシャポン！コレクション', 'ガシャポン!コレクション', 'ホビーガチャ',
  'hg', 'aip', 'カプセルプラレール', 'アルティメットルミナス', 'ガシャポンライダー', 'ガシャポン戦士',
};

// 同じ作品の別表記をひとつのタグにまとめる(正規化キー → 表示名)
const Map<String, String> _aliases = {
  'ぽけっともんすたー': 'ポケモン',
  'onepiece': 'ONE PIECE',
  'わんぴーす': 'ONE PIECE',
  'moomin': 'ムーミン',
  'tomandjerry': 'トムとジェリー',
  'disney': 'ディズニー',
  'でぃずにーきゃらくたー': 'ディズニー',
  'bang': 'バンドリ！',
  'bangdream': 'バンドリ！',
  'どらごんぼーる超': 'ドラゴンボール',
  'kamenrider': '仮面ライダー',
  '仮面らいだーしりーず': '仮面ライダー',
  'sanrio': 'サンリオキャラクターズ',
  'さんりお': 'サンリオキャラクターズ',
  'あんぱんまん': 'それいけ！アンパンマン',
  'すぬーぴー': 'PEANUTS',
  'peanuts': 'PEANUTS',
};

// タグをまとめるためのキー。全角/半角・カナ/かな・記号の違いを無視し、別名を寄せる
String workTagKey(String name) {
  final key = normalizeForSearch(name);
  return normalizeForSearch(_aliases[key] ?? name);
}

// 英字作品名の連結を止める、商品種別を表す英単語
const Set<String> _latinProductWords = {
  'gasha', 'portraits', 'fig', 'fig.', 'collection', 'capsule', 'figure', 'figures', 'mascot', 'series',
  'vol', 'vol.', 'ver', 'ver.', 'mini', 'dx', 'ex', 'set', 'box', 'plus', 'keychain', 'charm', 'pins', 'badge',
  'rubber', 'acrylic', 'stand', 'strap', 'pouch', 'light', 'edition', 'special', 'premium',
};

// 商品名から作品名の候補(先頭トークン)を取り出す。該当なしは null
String? leadingWorkCandidate(String title) {
  var text = title.replaceFirst(_bracketPrefix, '').replaceFirst(_mediaPrefix, '').trim();
  if (text.isEmpty) return null;
  final quoted = _quoted.firstMatch(text);
  if (quoted != null) return _clean(quoted.group(1)!);
  final tokens = text.split(_separator).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return null;
  var head = tokens.first;
  // 「Polly Pocket」「TOM and JERRY」のように英単語が続く間は連結する
  if (_latin.hasMatch(head)) {
    var i = 1;
    while (i < tokens.length &&
        _latin.hasMatch(tokens[i]) &&
        !_latinProductWords.contains(tokens[i].toLowerCase()) &&
        i < 5) {
      head = '$head ${tokens[i]}';
      i++;
    }
  }
  return _clean(head);
}

// 末尾トークン(タカラトミーアーツ式で作品名が末尾に来る場合の候補)
String? trailingWorkCandidate(String title) {
  final text = title.replaceFirst(_bracketPrefix, '').trim();
  final tokens = text.split(_separator).where((t) => t.isNotEmpty).toList();
  if (tokens.length < 2) return null;
  return _clean(tokens.last);
}

String? _clean(String token) {
  var t = token.trim().replaceAll(RegExp(r'^[“”"‘’]+|[“”"‘’™®]+$'), '');
  // 末尾の数字・弾数は繰り返し落とす(「ハグコット3」「vol.2」)
  for (var i = 0; i < 2; i++) {
    t = t.replaceFirst(_trailingNumber, '').trim();
  }
  t = t.replaceAll(RegExp(r'[　\s]+$'), '');
  if (t.length < 2) return null;
  if (_genericWords.contains(t.toLowerCase())) return null;
  if (RegExp(r'^[0-9０-９/／.:：]+$').hasMatch(t)) return null; // 「1/24」などのスケール表記
  return t;
}

class WorkTag {
  final String name;
  final List<GachaSeries> series;
  const WorkTag(this.name, this.series);
  int get count => series.length;
}

class WorkTagIndex {
  final Map<String, WorkTag> _byName;
  final Map<String, String> _seriesToTag;
  const WorkTagIndex._(this._byName, this._seriesToTag);

  // 出現シリーズ数の多い順
  List<WorkTag> get tags {
    final list = _byName.values.toList()..sort((a, b) => b.count.compareTo(a.count));
    return list;
  }

  WorkTag? tagOf(GachaSeries series) {
    final name = _seriesToTag[series.id];
    return name == null ? null : _byName[name];
  }

  WorkTag? byName(String name) => _byName[name];

  // アプリ内で共有するキャッシュ(データは起動中は同じリストなので1回だけ作る)
  static WorkTagIndex? _cached;
  static List<GachaSeries>? _cachedSource;
  static Future<WorkTagIndex> buildAsync(List<GachaSeries> allSeries) async {
    if (_cached != null && identical(_cachedSource, allSeries)) return _cached!;
    // 描画を止めないよう1フレーム譲ってから構築する(15,000件で数十ms)
    await Future<void>.delayed(Duration.zero);
    _cachedSource = allSeries;
    return _cached = build(allSeries);
  }

  static WorkTagIndex build(List<GachaSeries> allSeries) {
    // 先頭トークンの出現回数(同じシリーズは1回)。表記ゆれ・別名は workTagKey でまとめる
    final leadingCounts = <String, int>{};
    final surfaceCounts = <String, Map<String, int>>{};
    final leading = <String, String?>{};
    void countSurface(String key, String surface) {
      final m = surfaceCounts.putIfAbsent(key, () => {});
      m[surface] = (m[surface] ?? 0) + 1;
    }
    for (final s in allSeries) {
      final head = leadingWorkCandidate(s.name);
      final key = head == null ? null : workTagKey(head);
      leading[s.id] = key;
      if (key != null && head != null) {
        leadingCounts[key] = (leadingCounts[key] ?? 0) + 1;
        countSurface(key, head);
      }
    }
    final accepted = {
      for (final e in leadingCounts.entries)
        if (e.value >= kWorkTagMinSeries) e.key,
    };
    final groupedByKey = <String, List<GachaSeries>>{};
    for (final s in allSeries) {
      var key = leading[s.id];
      if (key == null || !accepted.contains(key)) {
        final tail = trailingWorkCandidate(s.name);
        final tailKey = tail == null ? null : workTagKey(tail);
        key = tailKey != null && accepted.contains(tailKey) ? tailKey : null;
        if (key != null && tail != null) countSurface(key, tail);
      }
      if (key == null) continue;
      groupedByKey.putIfAbsent(key, () => []).add(s);
    }
    // 表示名: 別名表に登録があればそれ、無ければ最も多く使われた表記
    final displayName = <String, String>{};
    final aliasByKey = {for (final e in _aliases.entries) normalizeForSearch(e.value): e.value};
    for (final key in groupedByKey.keys) {
      final surfaces = surfaceCounts[key]!.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      displayName[key] = aliasByKey[key] ?? surfaces.first.key;
    }
    final byName = <String, WorkTag>{};
    final seriesToTag = <String, String>{};
    for (final e in groupedByKey.entries) {
      final name = displayName[e.key]!;
      byName[name] = WorkTag(name, e.value);
      for (final s in e.value) {
        seriesToTag[s.id] = name;
      }
    }
    return WorkTagIndex._(byName, seriesToTag);
  }
}

// 検索用の正規化: 小文字化、全角英数→半角、カタカナ→ひらがな、空白・記号を除く。
// 「ちいかわ」「チイカワ」「ＭＯＯＭＩＮ」「moomin」を同じものとして扱うため
final RegExp _ignorable = RegExp(r'[\s\p{P}\p{S}]', unicode: true);

String normalizeForSearch(String text) {
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    var c = rune;
    if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0; // 全角英数記号 → 半角
    if (c >= 0x30A1 && c <= 0x30F6) c -= 0x60; // カタカナ → ひらがな
    final ch = String.fromCharCode(c);
    if (_ignorable.hasMatch(ch)) continue;
    buffer.write(ch);
  }
  return buffer.toString();
}

// 空白区切りの複数語は AND 検索
bool matchesSearch(String keyword, Iterable<String> fields) {
  final terms = keyword.split(RegExp(r'[\s\u3000]+')).map(normalizeForSearch).where((t) => t.isNotEmpty);
  final haystack = fields.map(normalizeForSearch).join('\n');
  return terms.every(haystack.contains);
}
