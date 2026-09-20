import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'community_photos.dart';
import 'models.dart';

// 写真共有(段階B)のバックエンド接続。Supabase の URL/anon キーは --dart-define で渡す。
// 未設定ならすべての機能が無効になり、アプリは段階Aと同じ挙動(端末内のみ)になる。
//
//   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
//
// 個人情報は扱わない: 匿名認証のユーザーID(匿名ID)・写真・対象アイテムIDのみ送信する。
class CommunityService {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _consentKey = 'community_consent_at';
  static const String _shareDefaultKey = 'community_share_default';
  static const String _blockedKey = 'community_blocked_posters';
  static const String kPendingBucket = 'photos-pending';

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
  static bool _initialized = false;

  static Future<void> init() async {
    if (!isConfigured || _initialized) return;
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
    _initialized = true;
  }

  static SupabaseClient get _client => Supabase.instance.client;

  // --- 同意・設定(端末内) ---

  static Future<bool> hasConsented() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_consentKey) != null;
  }

  static Future<void> recordConsent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_consentKey, DateTime.now().toIso8601String());
    await prefs.setBool(_shareDefaultKey, true);
  }

  // 「写真を登録したら自動でみんなの図鑑にも送る」設定。同意後のデフォルトは true
  static Future<bool> shareByDefault() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_shareDefaultKey) ?? false;
  }

  static Future<void> setShareByDefault(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shareDefaultKey, value);
  }

  // --- 匿名ID ---

  // 匿名サインイン(初回のみ)して posters 行を用意し、ユーザーIDを返す
  static Future<String> ensureSignedIn() async {
    if (!_initialized) throw StateError('CommunityService is not configured');
    var user = _client.auth.currentUser;
    if (user == null) {
      final res = await _client.auth.signInAnonymously();
      user = res.user;
      if (user == null) throw StateError('anonymous sign-in failed');
    }
    await _client.from('posters').upsert({'id': user.id}, onConflict: 'id', ignoreDuplicates: true);
    return user.id;
  }

  static String? get currentUserId =>
      _initialized ? _client.auth.currentUser?.id : null;

  // --- 投稿 ---

  // 写真を pending バケットへアップロードし photos 行を作る。戻り値は photo id
  static Future<String> uploadPhoto({
    required GachaSeries series,
    required GachaItem item,
    required File file,
  }) async {
    final uid = await ensureSignedIn();
    final photoId = _uuid();
    final path = '$uid/$photoId.jpg';
    await _client.storage.from(kPendingBucket).uploadBinary(
          path,
          await file.readAsBytes(),
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
        );
    await _client.from('photos').insert({
      'id': photoId,
      'item_id': item.id,
      'series_id': series.id,
      'maker': series.maker.code,
      'poster_id': uid,
      'storage_path': path,
      // Edge Function の一致度判定用の表示名(個人情報は含まない)
      'item_label': '${series.name} / ${item.name}',
    });
    return photoId;
  }

  static Future<void> removeOwnPhoto(String photoId) async {
    await _client.rpc('remove_own_photo', params: {'p_photo_id': photoId});
  }

  // 自分の投稿の状態(pending/approved/held/rejected/removed)
  static Future<String?> photoStatus(String photoId) async {
    final row = await _client.from('photos').select('status').eq('id', photoId).maybeSingle();
    return row?['status'] as String?;
  }

  // --- 他ユーザーの写真への操作(承認・通報・ブロック) ---

  // 承認候補を取れるのは、写真共有に参加している(同意済み or サインイン済み)ユーザーのみ。
  // 開いただけのユーザーに匿名アカウントを作らせないための制限
  static Future<bool> canReview() async =>
      isConfigured && (currentUserId != null || await hasConsented());

  // 指定シリーズの審査中写真(自分の投稿・既に判定したもの・ブロック済み投稿者を除く)
  static Future<List<PendingPhoto>> pendingPhotosForReview(String seriesId, {int limit = 5}) async {
    await ensureSignedIn();
    final rows = await _client.rpc('pending_photos_for_review',
        params: {'p_series_id': seriesId, 'p_limit': limit}) as List;
    final result = <PendingPhoto>[];
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final signed = await _client.storage
          .from(kPendingBucket)
          .createSignedUrl(row['storage_path'] as String, 3600);
      result.add(PendingPhoto(
        id: row['id'] as String,
        itemId: row['item_id'] as String,
        itemLabel: row['item_label'] as String?,
        posterId: row['poster_id'] as String,
        url: signed,
      ));
    }
    return result;
  }

  static Future<void> approvePhoto(String photoId) async {
    await ensureSignedIn();
    await _client.rpc('approve_photo', params: {'p_photo_id': photoId});
  }

  static Future<void> reportPhoto(String photoId, String reason, {String? detail}) async {
    await ensureSignedIn();
    await _client.rpc('report_photo', params: {
      'p_photo_id': photoId,
      'p_reason': reason,
      if (detail != null) 'p_detail': detail,
    });
  }

  // ブロック: サーバーに記録し、端末側の除外リスト(CommunityPhotos.blockedPosters)にも反映する
  static Future<void> blockPoster(String posterId) async {
    final uid = await ensureSignedIn();
    await _client.from('blocks').upsert({'blocker_id': uid, 'blocked_id': posterId});
    CommunityPhotos.blockedPosters.value = {...CommunityPhotos.blockedPosters.value, posterId};
    await _saveBlocked();
  }

  static Future<void> unblockPoster(String posterId) async {
    final uid = await ensureSignedIn();
    await _client.from('blocks').delete().match({'blocker_id': uid, 'blocked_id': posterId});
    CommunityPhotos.blockedPosters.value = {...CommunityPhotos.blockedPosters.value}..remove(posterId);
    await _saveBlocked();
  }

  // 起動時: 端末キャッシュ → サインイン済みならサーバーの blocks で上書き
  static Future<void> loadBlocked() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getStringList(_blockedKey);
    if (cached != null) CommunityPhotos.blockedPosters.value = cached.toSet();
    if (!_initialized || currentUserId == null) return;
    try {
      final rows = await _client.from('blocks').select('blocked_id') as List;
      CommunityPhotos.blockedPosters.value =
          rows.map((r) => (r as Map)['blocked_id'].toString()).toSet();
      await _saveBlocked();
    } catch (_) {}
  }

  static Future<void> _saveBlocked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_blockedKey, CommunityPhotos.blockedPosters.value.toList());
  }

  static String _uuid() => const Uuid().v4();
}

// 承認候補(他ユーザーの審査中写真)。url は1時間有効の署名付きURL
class PendingPhoto {
  final String id;
  final String itemId;
  final String? itemLabel;
  final String posterId;
  final String url;
  const PendingPhoto({required this.id, required this.itemId, this.itemLabel, required this.posterId, required this.url});
}

// 通報理由(表示名と DB の値)
const List<({String code, String label})> kReportReasons = [
  (code: 'wrong_item', label: '違うアイテムの写真'),
  (code: 'inappropriate', label: '不適切な内容'),
  (code: 'copyright', label: '公式画像や他人の写真の転載'),
  (code: 'other', label: 'その他'),
];
