// Supabase の approved_photo_snapshot ビュー(採用済みユーザー写真)を
// assets/community_photos.json に書き出す(段階B-2 配信スナップショット)。
//
// 使い方:
//   $env:SUPABASE_URL="https://xxxx.supabase.co"; $env:SUPABASE_KEY="sb_publishable_..."
//   dart run tool/export_community_photos.dart            # 変更があれば書き込む
//   dart run tool/export_community_photos.dart --force    # 変更が無くても書き込む
//
// 採用写真は RLS で全員が読めるので publishable(anon)キーで十分。service_role は使わない。
// generated_at 以外に差分が無ければファイルを更新しない(GitHub Actions の空コミットを避ける)。
//
// 出力形式(v1.0 アプリは読まない別ファイルなので、後方互換の制約は無い):
//   {
//     "generated_at": "2026-09-20T00:00:00Z",
//     "items":  { "<itemId>":   { "url": "...", "poster": "<uuid>" } },
//     "series": { "<seriesId>": { "url": "...", "poster": "<uuid>" } }   // そのシリーズの最良1枚
//   }

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const String kOutputPath = 'assets/community_photos.json';
const int kPageSize = 1000;

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final url = Platform.environment['SUPABASE_URL'] ?? '';
  final key = Platform.environment['SUPABASE_KEY'] ?? '';
  if (url.isEmpty || key.isEmpty) {
    stderr.writeln('SUPABASE_URL / SUPABASE_KEY を環境変数で指定してください');
    exitCode = 2;
    return;
  }

  final rows = await fetchAllRows(Uri.parse(url), key);
  final snapshot = buildSnapshot(rows);
  final out = File(kOutputPath);

  if (!force && out.existsSync() && !hasContentChanged(out.readAsStringSync(), snapshot)) {
    stdout.writeln('変更なし(${(snapshot['items'] as Map).length}件)');
    return;
  }
  out.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(snapshot)}\n');
  stdout.writeln('書き込み: $kOutputPath items=${(snapshot['items'] as Map).length} series=${(snapshot['series'] as Map).length}');
}

// PostgREST から全行取得(Range ヘッダでページング)
Future<List<Map<String, dynamic>>> fetchAllRows(Uri base, String key) async {
  final rows = <Map<String, dynamic>>[];
  for (var offset = 0;; offset += kPageSize) {
    final res = await http.get(
      base.replace(path: '/rest/v1/approved_photo_snapshot', queryParameters: {
        'select': 'item_id,series_id,maker,public_url,poster_id,likes,auto_score,approved_at',
        'order': 'item_id.asc',
      }),
      headers: {
        'apikey': key,
        'Authorization': 'Bearer $key',
        'Range': '$offset-${offset + kPageSize - 1}',
      },
    );
    if (res.statusCode != 200 && res.statusCode != 206) {
      throw HttpException('approved_photo_snapshot: HTTP ${res.statusCode} ${res.body}');
    }
    final page = (jsonDecode(utf8.decode(res.bodyBytes)) as List).cast<Map<String, dynamic>>();
    rows.addAll(page);
    if (page.length < kPageSize) return rows;
  }
}

// ビューの行(アイテムごとに最良1枚)から配信用JSONを組み立てる。キーはソートして出力を安定させる
Map<String, dynamic> buildSnapshot(List<Map<String, dynamic>> rows) {
  final items = <String, Map<String, String>>{};
  final bestPerSeries = <String, Map<String, dynamic>>{};
  for (final row in rows) {
    final url = row['public_url'] as String?;
    final itemId = row['item_id'] as String?;
    final seriesId = row['series_id'] as String?;
    if (url == null || url.isEmpty || itemId == null || seriesId == null) continue;
    items[itemId] = _entry(row);
    final current = bestPerSeries[seriesId];
    if (current == null || _score(row) > _score(current)) bestPerSeries[seriesId] = row;
  }
  final series = {for (final e in bestPerSeries.entries) e.key: _entry(e.value)};
  return {
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'items': _sorted(items),
    'series': _sorted(series),
  };
}

Map<String, String> _entry(Map<String, dynamic> row) => {
      'url': row['public_url'] as String,
      if (row['poster_id'] != null) 'poster': row['poster_id'] as String,
    };

// ビューの並び順と同じ評価式: auto_score×0.5 + min(likes,50)/100
double _score(Map<String, dynamic> row) {
  final auto = (row['auto_score'] as num?)?.toDouble() ?? 0;
  final likes = (row['likes'] as num?)?.toInt() ?? 0;
  return auto * 0.5 + (likes < 50 ? likes : 50) / 100.0;
}

Map<String, T> _sorted<T>(Map<String, T> map) {
  final keys = map.keys.toList()..sort();
  return {for (final k in keys) k: map[k] as T};
}

// generated_at を除いて比較する
bool hasContentChanged(String existingJson, Map<String, dynamic> snapshot) {
  try {
    final existing = Map<String, dynamic>.from(jsonDecode(existingJson) as Map)..remove('generated_at');
    final next = Map<String, dynamic>.from(snapshot)..remove('generated_at');
    return jsonEncode(existing) != jsonEncode(next);
  } catch (_) {
    return true;
  }
}
