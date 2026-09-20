import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String kCommunityPhotosUrl =
    'https://raw.githubusercontent.com/michirug/gacha-collector/main/assets/community_photos.json';

// 「みんなの図鑑」で採用されたユーザー写真
class CommunityPhoto {
  final String url;
  final String? posterId;
  const CommunityPhoto(this.url, {this.posterId});
}

class CommunityPhotoSnapshot {
  final Map<String, CommunityPhoto> items;
  final Map<String, CommunityPhoto> series;
  const CommunityPhotoSnapshot({this.items = const {}, this.series = const {}});
  bool get isEmpty => items.isEmpty && series.isEmpty;
}

// 採用写真の配信スナップショット(assets/community_photos.json)。
// GitHub Actions が Supabase の approved_photo_snapshot ビューから毎時書き出し、
// アプリは ImagePolicy と同じく 同梱→端末キャッシュ→リモート の順で読む。
// 表示優先順は GachaImage 側で 自分の写真 → みんなの写真 → 公式画像 → プレースホルダー。
class CommunityPhotos {
  static const String _prefsKey = 'community_photos_json';
  static final ValueNotifier<CommunityPhotoSnapshot> snapshot =
      ValueNotifier(const CommunityPhotoSnapshot());

  static CommunityPhoto? forItem(String? itemId) =>
      itemId == null ? null : snapshot.value.items[itemId];

  static CommunityPhoto? forSeries(String? seriesId) =>
      seriesId == null ? null : snapshot.value.series[seriesId];

  static void apply(String jsonText) {
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) return;
      snapshot.value = CommunityPhotoSnapshot(
        items: _photoMap(decoded['items']),
        series: _photoMap(decoded['series']),
      );
    } catch (_) {}
  }

  static Map<String, CommunityPhoto> _photoMap(dynamic value) {
    if (value is! Map) return const {};
    final result = <String, CommunityPhoto>{};
    for (final entry in value.entries) {
      final v = entry.value;
      final url = v is Map ? v['url'] : v;
      if (url is! String || url.isEmpty) continue;
      result[entry.key.toString()] =
          CommunityPhoto(url, posterId: v is Map ? v['poster']?.toString() : null);
    }
    return result;
  }

  static Future<void> load() async {
    try {
      apply(await rootBundle.loadString('assets/community_photos.json'));
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefsKey);
    if (cached != null) apply(cached);
    if (kIsWeb || kCommunityPhotosUrl.isEmpty) return;
    try {
      final response = await http.get(Uri.parse(kCommunityPhotosUrl));
      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        apply(body);
        await prefs.setString(_prefsKey, body);
      }
    } catch (_) {}
  }
}
