// バンダイ以外のメーカー公式サイトから新商品を取得して assets/gacha_data.json に追記するクローラー
//
// 使い方:
//   dart run tool/crawl_makers.dart                       # 全メーカー、新着のみ、各メーカー最大100件
//   dart run tool/crawl_makers.dart --maker=kitan,sota    # メーカー指定
//   dart run tool/crawl_makers.dart --max=30              # 1メーカーあたりの取得上限
//   dart run tool/crawl_makers.dart --backfill            # サイトマップ/過去カレンダーから全件取得
//
// 対応メーカー: takaratomy_arts / kitan / bushiroad / sota
// 各エントリは `id`(メーカー接頭辞付き)・`maker`・`source_url` を持ち、
// 公式にラインナップ名が無い場合は「No.1」… の仮アイテムを生成して `lineup_unknown: true` を付ける。

import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

const String kDataFilePath = 'assets/gacha_data.json';
const Duration kRequestInterval = Duration(seconds: 2);
const Map<String, String> kHeaders = {
  'User-Agent':
      'GachaCollectorBot/1.0 (+https://github.com/michirug/gacha-collector)',
};

typedef Candidate = ({String id, String url});

abstract class MakerCrawler {
  String get code;
  String get label;
  Future<List<Candidate>> discover({required bool backfill});
  Map<String, dynamic>? parseDetail(String htmlBody, Candidate candidate);
}

Future<void> main(List<String> args) async {
  var makers = <String>['takaratomy_arts', 'kitan', 'bushiroad', 'sota'];
  var maxPerMaker = 100;
  var backfill = false;
  for (final arg in args) {
    if (arg.startsWith('--maker=')) {
      makers = arg.substring('--maker='.length).split(',');
    } else if (arg.startsWith('--max=')) {
      maxPerMaker = int.tryParse(arg.substring('--max='.length)) ?? maxPerMaker;
    } else if (arg == '--backfill') {
      backfill = true;
    }
  }

  final dataFile = File(kDataFilePath);
  if (!dataFile.existsSync()) {
    stderr.writeln('データファイルが見つかりません: $kDataFilePath');
    exitCode = 1;
    return;
  }
  final List<dynamic> existing = jsonDecode(await dataFile.readAsString());
  final existingIds = existing
      .map((e) => (e['id'] ?? e['jan_code']).toString())
      .toSet();
  stdout.writeln('既存データ: ${existing.length}件');

  final crawlers = <MakerCrawler>[
    TakaraTomyArtsCrawler(),
    KitanCrawler(),
    BushiroadCrawler(),
    SotaCrawler(),
  ].where((c) => makers.contains(c.code)).toList();

  final newEntries = <Map<String, dynamic>>[];
  for (final crawler in crawlers) {
    stdout.writeln('--- ${crawler.label}');
    List<Candidate> candidates;
    try {
      candidates = await crawler.discover(backfill: backfill);
    } catch (e) {
      stderr.writeln('一覧取得失敗(スキップ): $e');
      continue;
    }
    final fresh = candidates
        .where((c) => !existingIds.contains(c.id))
        .toList();
    stdout.writeln('候補${candidates.length}件 / 新規${fresh.length}件 (上限$maxPerMaker)');
    var added = 0;
    for (final candidate in fresh.take(maxPerMaker)) {
      await Future.delayed(kRequestInterval);
      final body = await fetch(candidate.url);
      if (body == null) {
        stderr.writeln('詳細取得失敗(スキップ): ${candidate.url}');
        continue;
      }
      final entry = crawler.parseDetail(body, candidate);
      if (entry == null) {
        stderr.writeln('パース失敗(スキップ): ${candidate.url}');
        continue;
      }
      newEntries.add(entry);
      existingIds.add(candidate.id);
      added++;
      stdout.writeln('取得: ${entry['title']}');
      // 長時間のバックフィルで途中終了しても取得分を失わないよう、100件ごとに保存する
      if (added % 100 == 0) await save(dataFile, existing, newEntries);
    }
    stdout.writeln('${crawler.label}: $added件追加');
    if (added > 0) await save(dataFile, existing, newEntries);
  }

  if (newEntries.isEmpty) {
    stdout.writeln('追加する新商品はありません');
    return;
  }
  stdout.writeln('${newEntries.length}件追加 → 合計${existing.length + newEntries.length}件を保存しました');
}

Future<void> save(File dataFile, List<dynamic> existing,
    List<Map<String, dynamic>> newEntries) async {
  const encoder = JsonEncoder.withIndent('  ');
  await dataFile.writeAsString(encoder.convert([...existing, ...newEntries]));
}

// ---------------------------------------------------------------------------
// 共通ヘルパー
// ---------------------------------------------------------------------------

Future<String?> fetch(String url) async {
  try {
    final response = await http.get(Uri.parse(url), headers: kHeaders);
    if (response.statusCode != 200) return null;
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  } catch (_) {
    return null;
  }
}

String normalizeWhitespace(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();

// <br> を空白に置き換えてからテキスト化する
String textWithBreaks(Element? element) {
  if (element == null) return '';
  final clone = element.clone(true);
  for (final br in clone.querySelectorAll('br')) {
    br.replaceWith(Text(' '));
  }
  return normalizeWhitespace(clone.text);
}

int? parseTypeCount(String text) {
  final match = RegExp(r'全\s*(\d+)\s*種').firstMatch(text) ??
      RegExp(r'(\d+)\s*種').firstMatch(text);
  return match == null ? null : int.tryParse(match.group(1)!);
}

// 説明文から 「A」「B」「C」 または 「A、B、C」 形式のラインナップ名を抽出する。
// 作品名などの引用と区別するため「ラインナップ」以降の部分を優先し、
// 種類数が分かっている場合は件数が一致するときだけ採用する。
List<String> extractQuotedNames(String text, int? expectedCount) {
  final lineupIndex = text.lastIndexOf('ラインナップ');
  final scope = lineupIndex >= 0 ? text.substring(lineupIndex) : text;
  var groups = RegExp(r'「([^」]+)」')
      .allMatches(scope)
      .map((m) => normalizeWhitespace(m.group(1)!))
      .toList();
  if (groups.isEmpty) return const [];
  if (groups.length == 1 && (expectedCount == null || expectedCount > 1)) {
    final split = groups.first
        .split(RegExp(r'[、,／/]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (split.length > 1) groups = split;
  }
  if (expectedCount == null) return groups.length > 1 ? groups : const [];
  if (groups.length == expectedCount) return groups;
  // 末尾に並ぶことが多いので、多い場合は末尾から種類数ぶんを採用する
  if (groups.length > expectedCount) {
    return groups.sublist(groups.length - expectedCount);
  }
  return const [];
}

List<Map<String, String>> buildItems({
  required List<String> names,
  required List<String> images,
  required String mainImage,
  required int? typeCount,
}) {
  if (names.isNotEmpty) {
    final seen = <String>{};
    final items = <Map<String, String>>[];
    for (var i = 0; i < names.length; i++) {
      final name = names[i];
      if (!seen.add(name)) continue;
      items.add({
        'title': name,
        'image_url': i < images.length ? images[i] : mainImage,
      });
    }
    return items;
  }
  final count = typeCount ?? images.length;
  if (count <= 0) return const [];
  return List.generate(
    count,
    (i) => {
      'title': 'No.${i + 1}',
      'image_url': i < images.length ? images[i] : mainImage,
    },
  );
}

// 収録するのは事実データ(商品名・価格・発売時期・種類数・ラインナップ名・画像URL)のみ。
// 説明文はメーカーの著作物なのでラインナップ抽出に使うだけで出力しない。
Map<String, dynamic> buildEntry({
  required String id,
  required String maker,
  required String sourceUrl,
  required String title,
  required String price,
  required String releaseDate,
  required int? typeCount,
  required String targetAge,
  required String mainImage,
  required List<Map<String, String>> items,
  required bool lineupUnknown,
}) {
  return {
    'id': id,
    'maker': maker,
    'source_url': sourceUrl,
    'category': 'capsule',
    'title': title,
    'price': price,
    'release_date': releaseDate,
    'num_types': typeCount == null ? '' : '全$typeCount種',
    'target_age': targetAge,
    'image_url': mainImage,
    'lineup_unknown': lineupUnknown,
    'items': items,
  };
}

Future<List<String>> fetchSitemapUrls(String sitemapUrl) async {
  final body = await fetch(sitemapUrl);
  if (body == null) return const [];
  return RegExp(r'<loc>\s*(?:<!\[CDATA\[)?([^<\]\s]+)(?:\]\]>)?\s*</loc>')
      .allMatches(body)
      .map((m) => m.group(1)!)
      .toList();
}

String absoluteUrl(String base, String href) =>
    Uri.parse(base).resolve(href).toString();

// ---------------------------------------------------------------------------
// タカラトミーアーツ
// ---------------------------------------------------------------------------

class TakaraTomyArtsCrawler extends MakerCrawler {
  static const _base = 'https://www.takaratomy-arts.co.jp/items/gacha/calendar/';
  static const _detail = 'https://www.takaratomy-arts.co.jp/items/item.html?n=';

  @override
  String get code => 'takaratomy_arts';
  @override
  String get label => 'タカラトミーアーツ';

  @override
  Future<List<Candidate>> discover({required bool backfill}) async {
    final now = DateTime.now();
    final months = <String>[];
    // 新着モード: 前月〜3か月先。バックフィル: 2020年1月〜3か月先
    var cursor = backfill ? DateTime(2020, 1) : DateTime(now.year, now.month - 1);
    final end = DateTime(now.year, now.month + 3);
    while (!cursor.isAfter(end)) {
      months.add('${cursor.year}${cursor.month.toString().padLeft(2, '0')}');
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    final seen = <String>{};
    final result = <Candidate>[];
    for (final ym in months) {
      await Future.delayed(kRequestInterval);
      final body = await fetch('$_base?ym=$ym');
      if (body == null) continue;
      for (final m in RegExp(r'item\.html\?n=([A-Za-z0-9]+)').allMatches(body)) {
        final productCode = m.group(1)!;
        if (!seen.add(productCode)) continue;
        result.add((id: 'tta:$productCode', url: '$_detail$productCode'));
      }
    }
    return result;
  }

  @override
  Map<String, dynamic>? parseDetail(String htmlBody, Candidate candidate) {
    final doc = html_parser.parse(htmlBody);
    final detail = doc.querySelector('section#detail');
    if (detail == null) return null;
    final title = textWithBreaks(detail.querySelector('.head h2'));
    if (title.isEmpty) return null;

    final meta = textWithBreaks(detail.querySelector('.head p'));
    final price = RegExp(r'価格\s*[:：]\s*([^■]+)').firstMatch(meta)?.group(1)?.trim() ?? '';
    final releaseDate =
        RegExp(r'発売時期\s*[:：]\s*([^■]+)').firstMatch(meta)?.group(1)?.trim() ?? '';
    final description = textWithBreaks(detail.querySelector('.summary'));
    final mainImage = detail.querySelector('.images img')?.attributes['src'] ?? '';
    final typeCount = parseTypeCount(description);
    final names = extractQuotedNames(description, typeCount);
    final items = buildItems(
        names: names, images: const [], mainImage: mainImage, typeCount: typeCount);
    if (items.isEmpty) return null;

    return buildEntry(
      id: candidate.id,
      maker: code,
      sourceUrl: candidate.url,
      title: title,
      price: price,
      releaseDate: releaseDate,
      typeCount: typeCount ?? items.length,
      targetAge: '',
      mainImage: mainImage,
      items: items,
      lineupUnknown: names.isEmpty,
    );
  }
}

// ---------------------------------------------------------------------------
// キタンクラブ
// ---------------------------------------------------------------------------

class KitanCrawler extends MakerCrawler {
  static const _list = 'https://kitan.jp/products/';
  static const _sitemap = 'https://kitan.jp/products-sitemap.xml';

  @override
  String get code => 'kitan';
  @override
  String get label => 'キタンクラブ';

  @override
  Future<List<Candidate>> discover({required bool backfill}) async {
    final urls = <String>[];
    if (backfill) {
      urls.addAll(await fetchSitemapUrls(_sitemap));
    } else {
      final body = await fetch(_list);
      if (body == null) return const [];
      urls.addAll(RegExp(r'href="(https://kitan\.jp/products/[^"/]+/)"')
          .allMatches(body)
          .map((m) => m.group(1)!));
    }
    final seen = <String>{};
    final result = <Candidate>[];
    for (final url in urls) {
      final slug = RegExp(r'/products/([^/]+)/?$').firstMatch(url)?.group(1);
      if (slug == null || slug == 'feed' || slug == 'page' || !seen.add(slug)) continue;
      result.add((id: 'kitan:$slug', url: 'https://kitan.jp/products/$slug/'));
    }
    return result;
  }

  @override
  Map<String, dynamic>? parseDetail(String htmlBody, Candidate candidate) {
    final doc = html_parser.parse(htmlBody);
    final title = textWithBreaks(doc.querySelector('.c-productDetail__title'));
    if (title.isEmpty) return null;

    var price = '';
    var releaseDate = '';
    int? typeCount;
    for (final dl in doc.querySelectorAll('.c-productDetail__detail-item')) {
      final dt = normalizeWhitespace(dl.querySelector('dt')?.text ?? '');
      final dd = textWithBreaks(dl.querySelector('dd'));
      if (dt.contains('発売日')) {
        releaseDate = dd;
      } else if (dt.contains('価格')) {
        price = RegExp(r'\d[\d,]*\s*円').firstMatch(dd)?.group(0) ?? dd;
        typeCount = parseTypeCount(dd);
      }
    }
    final description = textWithBreaks(doc.querySelector('.c-productDetail__text'));
    typeCount ??= parseTypeCount(description);
    final mainImage =
        doc.querySelector('.c-productDetail__thum img')?.attributes['src'] ?? '';

    final names = <String>[];
    final images = <String>[];
    for (final li in doc.querySelectorAll('.c-productDetail__pickup-item')) {
      final name = textWithBreaks(li.querySelector('.c-productDetail__pickup-text'));
      final img = li.querySelector('img')?.attributes['src'] ?? '';
      if (name.isEmpty) continue;
      names.add(name);
      images.add(img);
    }
    if (names.isEmpty) {
      names.addAll(extractQuotedNames(description, typeCount));
    }
    final items = buildItems(
        names: names, images: images, mainImage: mainImage, typeCount: typeCount);
    if (items.isEmpty) return null;

    return buildEntry(
      id: candidate.id,
      maker: code,
      sourceUrl: candidate.url,
      title: title,
      price: price,
      releaseDate: releaseDate,
      typeCount: typeCount ?? items.length,
      targetAge: '',
      mainImage: mainImage,
      items: items,
      lineupUnknown: names.isEmpty,
    );
  }
}

// ---------------------------------------------------------------------------
// ブシロードクリエイティブ(ブシカプ!)
// ---------------------------------------------------------------------------

class BushiroadCrawler extends MakerCrawler {
  static const _list = 'https://capsule.bushiroad-creative.com/product/';
  static const _sitemap =
      'https://capsule.bushiroad-creative.com/wp-sitemap-posts-product-1.xml';

  @override
  String get code => 'bushiroad';
  @override
  String get label => 'ブシロードクリエイティブ';

  @override
  Future<List<Candidate>> discover({required bool backfill}) async {
    final urls = <String>[];
    if (backfill) {
      urls.addAll(await fetchSitemapUrls(_sitemap));
    } else {
      for (final page in [1, 2]) {
        if (page > 1) await Future.delayed(kRequestInterval);
        final body = await fetch(page == 1 ? _list : '$_list?pagenum=$page');
        if (body == null) continue;
        urls.addAll(RegExp(r'href="(https://capsule\.bushiroad-creative\.com/product/\d+/)"')
            .allMatches(body)
            .map((m) => m.group(1)!));
      }
    }
    final seen = <String>{};
    final result = <Candidate>[];
    for (final url in urls) {
      final id = RegExp(r'/product/(\d+)/?$').firstMatch(url)?.group(1);
      if (id == null || !seen.add(id)) continue;
      result.add((id: 'bushi:$id', url: 'https://capsule.bushiroad-creative.com/product/$id/'));
    }
    return result;
  }

  @override
  Map<String, dynamic>? parseDetail(String htmlBody, Candidate candidate) {
    final doc = html_parser.parse(htmlBody);
    final title = textWithBreaks(doc.querySelector('.product__articleTitle'));
    if (title.isEmpty) return null;

    var price = '';
    var releaseDate = '';
    var targetAge = '';
    int? typeCount;
    for (final row in doc.querySelectorAll('.product__specList')) {
      final dt = normalizeWhitespace(row.querySelector('dt')?.text ?? '');
      final dd = textWithBreaks(row.querySelector('dd'));
      if (dt.contains('発売日')) {
        releaseDate = dd;
      } else if (dt.contains('価格')) {
        price = dd;
      } else if (dt.contains('種類')) {
        typeCount = parseTypeCount(dd);
      } else if (dt.contains('対象年齢')) {
        targetAge = dd;
      }
    }
    final description = textWithBreaks(doc.querySelector('.product__description'));
    final mainImage =
        doc.querySelector('#js-productMainimg')?.attributes['src'] ?? '';
    final thumbs = doc
        .querySelectorAll('.product__articleThumb img')
        .map((img) => img.attributes['src'] ?? '')
        .where((src) => src.isNotEmpty && src != mainImage)
        .toList();
    final names = extractQuotedNames(description, typeCount);
    final images = typeCount != null && thumbs.length == typeCount ? thumbs : <String>[];
    final items = buildItems(
        names: names, images: images, mainImage: mainImage, typeCount: typeCount);
    if (items.isEmpty) return null;

    return buildEntry(
      id: candidate.id,
      maker: code,
      sourceUrl: candidate.url,
      title: title,
      price: price,
      releaseDate: releaseDate,
      typeCount: typeCount ?? items.length,
      targetAge: targetAge,
      mainImage: mainImage,
      items: items,
      lineupUnknown: names.isEmpty,
    );
  }
}

// ---------------------------------------------------------------------------
// SO-TA
// ---------------------------------------------------------------------------

class SotaCrawler extends MakerCrawler {
  static const _list = 'https://www.so-ta.com/products/capsuletoy/';
  static const _sitemap = 'https://www.so-ta.com/products-sitemap.xml';

  @override
  String get code => 'sota';
  @override
  String get label => 'SO-TA';

  @override
  Future<List<Candidate>> discover({required bool backfill}) async {
    final urls = <String>[];
    if (backfill) {
      urls.addAll(await fetchSitemapUrls(_sitemap));
    } else {
      final body = await fetch(_list);
      if (body == null) return const [];
      urls.addAll(RegExp(r'href="(https://www\.so-ta\.com/products_detail/capsuletoy/[^"]+/)"')
          .allMatches(body)
          .map((m) => m.group(1)!));
    }
    final seen = <String>{};
    final result = <Candidate>[];
    for (final url in urls) {
      final slug =
          RegExp(r'/products_detail/capsuletoy/([^/]+)/?$').firstMatch(url)?.group(1);
      if (slug == null || !seen.add(slug)) continue;
      result.add((
        id: 'sota:$slug',
        url: 'https://www.so-ta.com/products_detail/capsuletoy/$slug/'
      ));
    }
    return result;
  }

  @override
  Map<String, dynamic>? parseDetail(String htmlBody, Candidate candidate) {
    final doc = html_parser.parse(htmlBody);
    final title = textWithBreaks(doc.querySelector('.productsName'));
    if (title.isEmpty) return null;

    var price = '';
    var releaseDate = '';
    int? typeCount;
    for (final dl in doc.querySelectorAll('.dataArea dl')) {
      final dt = normalizeWhitespace(dl.querySelector('dt')?.text ?? '');
      final dd = textWithBreaks(dl.querySelector('dd'));
      if (dt.contains('発売')) {
        releaseDate = dd;
      } else if (dt.contains('価格')) {
        price = dd;
      } else if (dt.contains('種類')) {
        typeCount = parseTypeCount(dd);
      }
    }
    final mainImage =
        doc.querySelector('.productsImg img')?.attributes['src'] ?? '';
    // サムネイル: 先頭はメイン画像、店頭POP(CPtenpo/scaled)は除外し、残りを個別画像として順に割り当てる
    final images = doc
        .querySelectorAll('.thumbList img')
        .map((img) => img.attributes['src'] ?? '')
        .where((src) =>
            src.isNotEmpty &&
            src != mainImage &&
            !src.contains('CPtenpo') &&
            !src.contains('-scaled'))
        .toList();
    final items = buildItems(
        names: const [], images: images, mainImage: mainImage, typeCount: typeCount);
    if (items.isEmpty) return null;

    return buildEntry(
      id: candidate.id,
      maker: code,
      sourceUrl: candidate.url,
      title: title,
      price: price,
      releaseDate: releaseDate,
      typeCount: typeCount ?? items.length,
      targetAge: '',
      mainImage: mainImage,
      items: items,
      lineupUnknown: true,
    );
  }
}
