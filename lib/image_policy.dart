import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

const String kRemoteConfigUrl =
    'https://raw.githubusercontent.com/michirug/gacha-collector/main/assets/app_config.json';

// 権利者からの申し出があった際に、アプリを更新せずに公式画像の表示を止めるための設定。
// assets/app_config.json をリポジトリ側で書き換えると、次回起動時に全端末へ反映される。
//   hide_official_images: 公式画像を表示しないメーカーコードの配列(例: ["bandai"])
//   hide_series: 非表示にするシリーズIDの配列
class ImagePolicy {
  static const String _prefsKey = 'app_config_json';
  static final ValueNotifier<Set<String>> hiddenMakers = ValueNotifier({});
  static final ValueNotifier<Set<String>> hiddenSeries = ValueNotifier({});

  static bool isMakerHidden(Maker? maker) =>
      maker != null && hiddenMakers.value.contains(maker.code);

  static bool isSeriesHidden(String seriesId) =>
      hiddenSeries.value.contains(seriesId);

  static void apply(String jsonText) {
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) return;
      hiddenMakers.value = _stringSet(decoded['hide_official_images']);
      hiddenSeries.value = _stringSet(decoded['hide_series']);
    } catch (_) {}
  }

  static Set<String> _stringSet(dynamic value) =>
      value is List ? value.map((e) => e.toString()).toSet() : <String>{};

  // 起動時に呼ぶ。同梱→端末キャッシュ→リモートの順で適用し、リモート取得結果をキャッシュする
  static Future<void> load() async {
    try {
      apply(await rootBundle.loadString('assets/app_config.json'));
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefsKey);
    if (cached != null) apply(cached);
    if (kIsWeb || kRemoteConfigUrl.isEmpty) return;
    try {
      final response = await http.get(Uri.parse(kRemoteConfigUrl));
      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        apply(body);
        await prefs.setString(_prefsKey, body);
      }
    } catch (_) {}
  }
}
