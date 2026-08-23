import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'collection_store.dart';
import 'models.dart';

class AchievementStats {
  final int totalItems;
  final int completedSeries;
  final int totalSpend;
  final int duplicateCount;

  const AchievementStats({
    required this.totalItems,
    required this.completedSeries,
    required this.totalSpend,
    required this.duplicateCount,
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
];

AchievementStats computeAchievementStats(
    Map<String, CollectionEntry> collection, List<GachaSeries> allSeries) {
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
