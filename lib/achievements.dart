import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'collection_store.dart';
import 'models.dart';

class AchievementStats {
  final int totalItems;
  final int completedSeries;
  final int totalSpend;
  final int duplicateCount;
  // みんなの図鑑への貢献(段階B)。未参加なら 0
  final int approvedPhotos;
  final int photoCompletedSeries;

  const AchievementStats({
    required this.totalItems,
    required this.completedSeries,
    required this.totalSpend,
    required this.duplicateCount,
    this.approvedPhotos = 0,
    this.photoCompletedSeries = 0,
  });
}

class Achievement {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final bool Function(AchievementStats stats) isSatisfied;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.isSatisfied,
  });
}

final List<Achievement> allAchievements = [
  Achievement(id: 'first_item', title: 'はじめの一歩', description: '初めてアイテムを獲得した', icon: Icons.flag, isSatisfied: (s) => s.totalItems >= 1),
  Achievement(id: 'items_10', title: '駆け出しコレクター', description: 'アイテムを10個獲得した', icon: Icons.grid_view, isSatisfied: (s) => s.totalItems >= 10),
  Achievement(id: 'items_50', title: '一人前コレクター', description: 'アイテムを50個獲得した', icon: Icons.inventory_2, isSatisfied: (s) => s.totalItems >= 50),
  Achievement(id: 'items_100', title: 'ベテランコレクター', description: 'アイテムを100個獲得した', icon: Icons.military_tech, isSatisfied: (s) => s.totalItems >= 100),
  Achievement(id: 'items_500', title: 'ガチャマスター', description: 'アイテムを500個獲得した', icon: Icons.workspace_premium, isSatisfied: (s) => s.totalItems >= 500),
  Achievement(id: 'comp_1', title: '初コンプ', description: '初めてシリーズをコンプリートした', icon: Icons.emoji_events, isSatisfied: (s) => s.completedSeries >= 1),
  Achievement(id: 'comp_5', title: 'コンプハンター', description: '5シリーズをコンプリートした', icon: Icons.stars, isSatisfied: (s) => s.completedSeries >= 5),
  Achievement(id: 'comp_20', title: 'コンプの鬼', description: '20シリーズをコンプリートした', icon: Icons.local_fire_department, isSatisfied: (s) => s.completedSeries >= 20),
  Achievement(id: 'dup_1', title: 'ダブりの洗礼', description: '初めてダブりを記録した', icon: Icons.copy_all, isSatisfied: (s) => s.duplicateCount >= 1),
  Achievement(id: 'spend_10k', title: '沼のほとり', description: '総支出が1万円を超えた', icon: Icons.savings, isSatisfied: (s) => s.totalSpend >= 10000),
  Achievement(id: 'spend_50k', title: 'ガチャ沼', description: '総支出が5万円を超えた', icon: Icons.water, isSatisfied: (s) => s.totalSpend >= 50000),
  Achievement(id: 'spend_100k', title: '沼の主', description: '総支出が10万円を超えた', icon: Icons.tsunami, isSatisfied: (s) => s.totalSpend >= 100000),
  Achievement(id: 'photo_1', title: '図鑑職人', description: '撮った写真がみんなの図鑑に採用された', icon: Icons.photo_camera, isSatisfied: (s) => s.approvedPhotos >= 1),
  Achievement(id: 'photo_20', title: '図鑑の匠', description: '写真が20枚みんなの図鑑に採用された', icon: Icons.auto_awesome, isSatisfied: (s) => s.approvedPhotos >= 20),
  Achievement(id: 'photo_series', title: 'シリーズ完成', description: '1シリーズ全アイテムの図鑑写真が自分の写真になった', icon: Icons.collections_bookmark, isSatisfied: (s) => s.photoCompletedSeries >= 1),
];

// みんなの図鑑への貢献を集計する。contribution は CommunityService.myContribution()(seriesId → 採用アイテム数)
({int approvedPhotos, int photoCompletedSeries}) computePhotoContribution(
    Map<String, int> contribution, List<GachaSeries> allSeries) {
  var approved = 0;
  var completed = 0;
  final itemCounts = {for (final s in allSeries) s.id: s.items.length};
  for (final entry in contribution.entries) {
    approved += entry.value;
    final total = itemCounts[entry.key];
    if (total != null && total > 0 && entry.value >= total) completed++;
  }
  return (approvedPhotos: approved, photoCompletedSeries: completed);
}

AchievementStats computeAchievementStats(
    Map<String, CollectionEntry> collection, List<GachaSeries> allSeries,
    {Map<String, int> contribution = const {}}) {
  final photo = computePhotoContribution(contribution, allSeries);
  int completedSeries = 0;
  for (final series in allSeries) {
    if (series.items.isNotEmpty &&
        series.items.every((item) => collection.containsKey(item.id))) {
      completedSeries++;
    }
  }
  final priceBySeriesId = {
    for (final series in allSeries) series.id: series.price
  };
  final spend =
      computeSpendSummary(collection.values, priceBySeriesId, DateTime.now());
  final duplicateCount =
      collection.values.where((entry) => entry.count > 1).length;
  return AchievementStats(
    totalItems: collection.length,
    completedSeries: completedSeries,
    totalSpend: spend.total,
    duplicateCount: duplicateCount,
    approvedPhotos: photo.approvedPhotos,
    photoCompletedSeries: photo.photoCompletedSeries,
  );
}

class AchievementService {
  static const String _unlockedKey = 'unlocked_achievements';

  static Future<Set<String>> loadUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_unlockedKey) ?? []).toSet();
  }

  static Future<List<Achievement>> evaluate(AchievementStats stats) async {
    final prefs = await SharedPreferences.getInstance();
    final unlocked = (prefs.getStringList(_unlockedKey) ?? []).toSet();
    final newly = <Achievement>[];
    for (final achievement in allAchievements) {
      if (!unlocked.contains(achievement.id) && achievement.isSatisfied(stats)) {
        unlocked.add(achievement.id);
        newly.add(achievement);
      }
    }
    if (newly.isNotEmpty) {
      await prefs.setStringList(_unlockedKey, unlocked.toList());
    }
    return newly;
  }
}
