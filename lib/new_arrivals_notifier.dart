import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'collection_store.dart';
import 'gacha_repository.dart';
import 'models.dart';
import 'release_notifier.dart';
import 'work_tags.dart';

// 「新作が追加された」通知(端末内・サーバー不要)。
//   - WorkManager の定期タスク(12時間ごと・ネットワーク接続時)で配信 JSON を条件付き GET する。
//     クローラーは週1回しか更新しないので、ほとんどの実行は 304 で終わり通信量はほぼゼロ
//   - 前回のキャッシュに無かったシリーズがあれば1件の通知にまとめる。
//     ユーザーの記録・ウィッシュにある作品タグと同じタグの新作を優先して本文に載せ、タップでその詳細を開く
//   - アプリを開いた時点でキャッシュが更新されるので、毎日開く人には通知が出ない(=見た新作は通知しない)
//   - Android のみ。iOS は BGAppRefresh の設定が別に要るので対象外
class NewArrivalsNotifier {
  static const String taskName = 'gacha_pocket_new_arrivals';
  static const String channelId = 'new_arrivals';
  static const String _enabledKey = 'notify_new_arrivals_enabled';
  static const Duration frequency = Duration(hours: 12);
  static const int notificationId = 1;
  static const int kMaxHighlights = 3;

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    if (!isSupported) return;
    if (value) {
      await ReleaseNotifier.requestPermissionIfNeeded();
      await _register();
    } else {
      await Workmanager().cancelByUniqueName(taskName);
    }
  }

  // 起動時に呼ぶ。既に登録済みなら keep で触らない
  static Future<void> init() async {
    if (!isSupported) return;
    try {
      await Workmanager().initialize(newArrivalsCallbackDispatcher);
      if (await isEnabled()) await _register();
    } catch (e) {
      debugPrint('NewArrivalsNotifier.init failed: $e');
    }
  }

  static Future<void> _register() async {
    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: frequency,
      // 起動直後のフォアグラウンド更新(21MB のDL)と重ならないよう少しずらす
      initialDelay: const Duration(minutes: 30),
      constraints: Constraints(networkType: NetworkType.connected, requiresBatteryNotLow: true),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 30),
    );
  }

  // バックグラウンド isolate から呼ばれる本体。テストしやすいよう取得と通知を分けている
  static Future<bool> runCheck() async {
    if (!await isEnabled()) return true;
    await checkNow();
    return true;
  }

  // 配信データを取りに行き、追加があれば通知する。追加件数を返す(マイページの「今すぐ確認」からも呼ぶ)
  static Future<int> checkNow() async {
    final added = await GachaRepository.refreshFromRemote();
    if (added.isEmpty) return 0;
    final all = await GachaRepository.loadAll();
    final collection = await CollectionStore.load();
    final wishlist = await CollectionStore.loadWishlist();
    final message = buildNewArrivalsMessage(
      added: added,
      allSeries: all,
      ownedItemIds: collection.keys.toSet(),
      wishlist: wishlist,
    );
    await _show(message);
    return added.length;
  }

  static Future<void> _show(NewArrivalsMessage message) async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await plugin.show(
      id: notificationId,
      title: message.title,
      body: message.body,
      payload: message.payloadSeriesId,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          '新作追加のお知らせ',
          channelDescription: '新しいカプセルトイの情報が追加されたときにお知らせします',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(''),
        ),
      ),
    );
  }
}

// WorkManager が起こす isolate のエントリポイント。必ずトップレベル関数
@pragma('vm:entry-point')
void newArrivalsCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != NewArrivalsNotifier.taskName) return true;
    try {
      return await NewArrivalsNotifier.runCheck();
    } catch (_) {
      return false;
    }
  });
}

class NewArrivalsMessage {
  final String title;
  final String body;
  final String? payloadSeriesId;
  const NewArrivalsMessage({required this.title, required this.body, this.payloadSeriesId});
}

// 追加されたシリーズから通知文を作る。
// ユーザーが記録・ウィッシュしているシリーズの作品タグと同じタグの新作を先頭に置き、タップでそれを開く
NewArrivalsMessage buildNewArrivalsMessage({
  required List<GachaSeries> added,
  required List<GachaSeries> allSeries,
  required Set<String> ownedItemIds,
  required Set<String> wishlist,
}) {
  final index = WorkTagIndex.build(allSeries);
  final myTags = <String>{};
  for (final s in allSeries) {
    if (wishlist.contains(s.id) || s.items.any((i) => ownedItemIds.contains(i.id))) {
      final tag = index.tagOf(s);
      if (tag != null) myTags.add(tag.name);
    }
  }
  final favorites = added.where((s) {
    final tag = index.tagOf(s);
    return tag != null && myTags.contains(tag.name);
  }).toList();
  final others = added.where((s) => !favorites.contains(s)).toList();
  final highlights = [...favorites, ...others].take(kMaxHighlightsFor(added.length)).toList();

  final makers = <Maker, int>{};
  for (final s in added) {
    makers[s.maker] = (makers[s.maker] ?? 0) + 1;
  }
  final makerText = (makers.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
      .take(3)
      .map((e) => '${e.key.label}${e.value}')
      .join('・');

  final title = favorites.isNotEmpty
      ? '${index.tagOf(favorites.first)!.name} の新作など${added.length}件が追加されました'
      : '新作${added.length}件が追加されました($makerText)';
  final body = [
    for (final s in highlights) '・${s.name}${s.releaseDateText.isEmpty ? '' : '(${s.releaseDateText})'}',
    if (added.length > highlights.length) 'ほか${added.length - highlights.length}件',
  ].join('\n');
  return NewArrivalsMessage(
    title: title,
    body: body,
    payloadSeriesId: favorites.isNotEmpty ? favorites.first.id : null,
  );
}

int kMaxHighlightsFor(int total) => total < NewArrivalsNotifier.kMaxHighlights ? total : NewArrivalsNotifier.kMaxHighlights;
