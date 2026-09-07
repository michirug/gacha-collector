import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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

  // --- 他ユーザーの写真への操作(B-2 で表示側を実装。API はここに揃えておく) ---

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

  static Future<void> blockPoster(String posterId) async {
    final uid = await ensureSignedIn();
    await _client.from('blocks').upsert({'blocker_id': uid, 'blocked_id': posterId});
  }

  static String _uuid() => const Uuid().v4();
}

// 通報理由(表示名と DB の値)
const List<({String code, String label})> kReportReasons = [
  (code: 'wrong_item', label: '違うアイテムの写真'),
  (code: 'inappropriate', label: '不適切な内容'),
  (code: 'copyright', label: '公式画像や他人の写真の転載'),
  (code: 'other', label: 'その他'),
];
