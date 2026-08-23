// gashapon.jp から新商品を取得して assets/gacha_data.json に追記するクローラー
// 使い方: dart run tool/crawl_gashapon.dart [最大取得件数(デフォルト100)]

import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

const String kListUrl =
    'https://gashapon.jp/products/result.php?free=&sale_sort=1';
const String kDetailUrlBase =
    'https://gashapon.jp/products/detail.php?jan_code=';
const String kDataFilePath = 'assets/gacha_data.json';
const Duration kRequestInterval = Duration(seconds: 2);
const Map<String, String> kHeaders = {
  'User-Agent':
      'GachaCollectorBot/1.0 (+https://github.com/michirug/gacha-collector)',
};

Future<void> main(List<String> args) async {
  final maxNew = args.isNotEmpty ? (int.tryParse(args[0]) ?? 100) : 100;

  final dataFile = File(kDataFilePath);
  if (!dataFile.existsSync()) {
    stderr.writeln('データファイルが見つかりません: $kDataFilePath');
    exitCode = 1;
    return;
  }
  final List<dynamic> existing = jsonDecode(await dataFile.readAsString());
  final existingJanCodes =
      existing.map((e) => e['jan_code'].toString()).toSet();
  stdout.writeln('既存データ: ${existing.length}件');

  final listResponse = await http.get(Uri.parse(kListUrl), headers: kHeaders);
  if (listResponse.statusCode != 200) {
    stderr.writeln('一覧の取得に失敗: HTTP ${listResponse.statusCode}');
    exitCode = 1;
    return;
  }
  final listDoc = html_parser.parse(listResponse.body);
  final cards = listDoc.querySelectorAll('.pg-result__list a.c-card__link');
  stdout.writeln('一覧から${cards.length}件検出');

  final newProducts = <({String janCode, String category})>[];
  for (final card in cards) {
    final href = card.attributes['href'] ?? '';
    final match = RegExp(r'jan_code=(\d+)').firstMatch(href);
    if (match == null) continue;
    final janCode = match.group(1)!;
    if (existingJanCodes.contains(janCode)) continue;
    if (newProducts.any((p) => p.janCode == janCode)) continue;
    final categoryElement = card.querySelector('[data-category]');
    final category = categoryElement?.attributes['data-category'] ?? 'other';
    newProducts.add((janCode: janCode, category: category));
  }
  stdout.writeln('新商品: ${newProducts.length}件 (今回の取得上限: $maxNew件)');

  final newEntries = <Map<String, dynamic>>[];
  for (final product in newProducts.take(maxNew)) {
    await Future.delayed(kRequestInterval);
    final detailUrl = '$kDetailUrlBase${product.janCode}';
    final response = await http.get(Uri.parse(detailUrl), headers: kHeaders);
    if (response.statusCode != 200) {
      stderr.writeln('詳細取得失敗(スキップ): ${product.janCode} HTTP ${response.statusCode}');
      continue;
    }
    final entry = parseDetailPage(response.body, product.janCode, product.category);
    if (entry == null) {
      stderr.writeln('パース失敗(スキップ): ${product.janCode}');
      continue;
    }
    newEntries.add(entry);
    stdout.writeln('取得: ${entry['title']}');
  }

  if (newEntries.isEmpty) {
    stdout.writeln('追加する新商品はありません');
    return;
  }

  final merged = [...existing, ...newEntries];
  const encoder = JsonEncoder.withIndent('  ');
  await dataFile.writeAsString(encoder.convert(merged));
  stdout.writeln('${newEntries.length}件追加 → 合計${merged.length}件を保存しました');
}

Map<String, dynamic>? parseDetailPage(
    String htmlBody, String janCode, String category) {
  final Document doc = html_parser.parse(htmlBody);

  final title = doc.querySelector('h1.pg-heading')?.text.trim() ?? '';
  if (title.isEmpty) return null;

  final description =
      doc.querySelector('.pg-detail__description')?.text.trim() ?? '';

  String price = '';
  String releaseDate = '';
  String numTypes = '';
  String targetAge = '';
  for (final dl in doc.querySelectorAll('dl.pg-detailDefinition')) {
    final dtText = dl.querySelector('dt')?.text.trim() ?? '';
    final ddText = _normalizeWhitespace(dl.querySelector('dd')?.text ?? '');
    if (dtText.contains('発売時期')) {
      releaseDate = ddText;
    } else if (dtText.contains('価格')) {
      price = ddText;
    } else if (dtText.contains('種類数')) {
      numTypes = ddText;
    } else if (dtText.contains('対象年齢')) {
      targetAge = ddText;
    }
  }

  final mainImage = doc
          .querySelector('meta[property="og:image"]')
          ?.attributes['content'] ??
      '';

  final items = <Map<String, String>>[];
  final seenTitles = <String>{};
  for (final img in doc.querySelectorAll('li.pg-detail__thumb img')) {
    final itemTitle = _normalizeWhitespace(img.attributes['title'] ?? '');
    final src = img.attributes['src'] ?? '';
    if (itemTitle.isEmpty || src.isEmpty) continue;
    if (!seenTitles.add(itemTitle)) continue;
    items.add({'title': itemTitle, 'image_url': src});
  }

  return {
    'jan_code': int.tryParse(janCode) ?? janCode,
    'category': category,
    'title': _normalizeWhitespace(title),
    'price': price,
    'release_date': releaseDate,
    'num_types': numTypes,
    'target_age': targetAge,
    'description': description,
    'special_site_name': '',
    'additional_notes': '',
    'image_url': mainImage,
    'items': items,
  };
}

String _normalizeWhitespace(String text) {
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
