import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

// ウィッシュリストに入れたシリーズの発売時期を、端末内のローカル通知で知らせる(サーバー不要)。
//   - 起動時とウィッシュリスト変更時に、今後 kHorizonDays 日以内に発売時期を迎えるものを 9:00 に予約し直す
//   - 「上旬/中旬/下旬/第N週」は parseJapaneseReleaseDate の代表日(5日/15日/25日/週頭)で通知する
//   - 正確なアラーム(SCHEDULE_EXACT_ALARM)は使わず inexact(多少ずれても良い)で予約する
//   - 通知の権限は初めてウィッシュリストに追加したときに求める
class ReleaseNotifier {
  static const String _enabledKey = 'notify_release_enabled';
  static const String _askedKey = 'notify_release_asked';
  static const String channelId = 'release_reminder';
  static const int kNotifyHour = 9;
  static const int kHorizonDays = 60;

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool get isReady => _initialized;

  static Future<void> init() async {
    if (kIsWeb || _initialized) return;
    try {
      tzdata.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _initialized = true;
    } catch (_) {}
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  // 初回のウィッシュ追加時などに呼ぶ。Android 13+ で POST_NOTIFICATIONS を要求する(1回だけ)
  static Future<void> requestPermissionIfNeeded() async {
    if (!_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_askedKey) == true) return;
    await prefs.setBool(_askedKey, true);
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      'ウィッシュリストの発売通知',
      channelDescription: 'ウィッシュリストに入れたカプセルトイの発売時期をお知らせします',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );

  // 設定画面の「テスト通知」。権限と表示を確認するために即時に1件出す
  static Future<void> showTest({required int wishCount, required int scheduledCount}) async {
    if (!_initialized) return;
    await requestPermissionIfNeeded();
    await _plugin.show(
      id: 0,
      title: 'ガチャ活ポケットの通知テスト',
      body: 'ウィッシュリスト$wishCount件のうち、60日以内に発売時期を迎える$scheduledCount件を予約中です',
      notificationDetails: _details,
    );
  }

  // 予約を全部作り直す。ウィッシュリスト保存時と起動時に呼ぶ
  static Future<void> reschedule(Set<String> wishlist, List<GachaSeries> allSeries) async {
    if (!_initialized) return;
    try {
      await _plugin.cancelAll();
      if (!await isEnabled()) return;
      for (final plan in planReleaseNotifications(wishlist, allSeries, DateTime.now())) {
        final local = tz.TZDateTime.from(plan.when, tz.local);
        await _plugin.zonedSchedule(
          id: plan.id,
          title: plan.title,
          body: plan.body,
          payload: plan.seriesId,
          scheduledDate: tz.TZDateTime(tz.local, local.year, local.month, local.day, kNotifyHour),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (_) {}
  }
}

class ReleaseNotificationPlan {
  final int id;
  final String seriesId;
  final String title;
  final String body;
  final DateTime when; // 日付のみ意味を持つ(時刻は reschedule 側で 9:00 にする)
  const ReleaseNotificationPlan({
    required this.id,
    required this.seriesId,
    required this.title,
    required this.body,
    required this.when,
  });
}

// 通知IDはシリーズIDから決定的に作る(再スケジュールで重複しない)
int notificationIdFor(String seriesId) => seriesId.hashCode & 0x7fffffff;

// ウィッシュリストのうち、今日〜kHorizonDays日以内に発売時期の代表日を迎えるものを通知対象にする。
// 今日が代表日なら今日(9:00を過ぎていれば予約されないので、その場合は対象外にする)
List<ReleaseNotificationPlan> planReleaseNotifications(
    Set<String> wishlist, List<GachaSeries> allSeries, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final horizon = today.add(const Duration(days: ReleaseNotifier.kHorizonDays));
  final plans = <ReleaseNotificationPlan>[];
  for (final series in allSeries) {
    if (!wishlist.contains(series.id)) continue;
    if (series.releaseDateText.isEmpty || series.releaseDate.year < 2000) continue;
    final day = DateTime(series.releaseDate.year, series.releaseDate.month, series.releaseDate.day);
    if (day.isBefore(today) || day.isAfter(horizon)) continue;
    if (day == today && now.hour >= ReleaseNotifier.kNotifyHour) continue;
    plans.add(ReleaseNotificationPlan(
      id: notificationIdFor(series.id),
      seriesId: series.id,
      title: '${series.name} が発売時期です',
      body: '${series.releaseDateText}発売予定・${series.price}円。お店で見つけたら記録しましょう!',
      when: day,
    ));
  }
  plans.sort((a, b) => a.when.compareTo(b.when));
  return plans;
}
