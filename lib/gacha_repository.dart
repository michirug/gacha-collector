import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

const String kRemoteDataUrl =
    'https://raw.githubusercontent.com/michirug/gacha-collector/main/assets/gacha_data.json';

class GachaRepository {
  static Future<List<GachaSeries>>? _cache;

  static Future<List<GachaSeries>> loadAll() {
    return _cache ??= _load();
  }

  static Future<List<GachaSeries>> _load() async {
    try {
      List<GachaSeries>? fromLocalCache;
      try {
        final cachedJson = await _readLocalCacheFile();
        if (cachedJson != null) {
          fromLocalCache = await compute(parseGachaSeriesList, cachedJson);
        }
      } catch (_) {
        fromLocalCache = null;
      }
      if (fromLocalCache != null && fromLocalCache.isNotEmpty) {
        unawaited(_refreshInBackground());
        return fromLocalCache;
      }
      final jsonString = await rootBundle.loadString('assets/gacha_data.json');
      final result = await compute(parseGachaSeriesList, jsonString);
      unawaited(_refreshInBackground());
      return result;
    } catch (e) {
      _cache = null;
      rethrow;
    }
  }

  static Future<String?> _readLocalCacheFile() async {
    if (kIsWeb) return null;
    final file = await _localCacheFile();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  static Future<File> _localCacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}gacha_data.json');
  }

  static Future<void> _refreshInBackground() async {
    if (kIsWeb || kRemoteDataUrl.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final headers = <String, String>{};
      final etag = prefs.getString('gacha_data_etag');
      if (etag != null) {
        headers['If-None-Match'] = etag;
      }
      final response =
          await http.get(Uri.parse(kRemoteDataUrl), headers: headers);
      if (response.statusCode != 200) return;
      final body = response.body;
      final parsed = await compute(parseGachaSeriesList, body);
      if (parsed.isEmpty) return;
      final file = await _localCacheFile();
      final tmpFile = File('${file.path}.tmp');
      await tmpFile.writeAsString(body, flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await tmpFile.rename(file.path);
      final newEtag = response.headers['etag'];
      if (newEtag != null) {
        await prefs.setString('gacha_data_etag', newEtag);
      }
    } catch (_) {
      return;
    }
  }
}

List<GachaSeries> parseGachaSeriesList(String jsonString) {
  final List<dynamic> jsonList = jsonDecode(jsonString);
  final seriesList = jsonList
      .map((jsonItem) => GachaSeries.fromJson(jsonItem as Map<String, dynamic>))
      .toList();
  final originalIndex = <GachaSeries, int>{};
  for (var i = 0; i < seriesList.length; i++) {
    originalIndex[seriesList[i]] = i;
  }
  seriesList.sort((a, b) {
    final comparison = b.releaseDate.compareTo(a.releaseDate);
    if (comparison != 0) return comparison;
    return originalIndex[b]!.compareTo(originalIndex[a]!);
  });
  return seriesList;
}
