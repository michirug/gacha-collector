import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'gacha_repository.dart';
import 'models.dart';

class CollectionStore {
  static const String _collectionKey = 'collection';
  static const String _schemaVersionKey = 'collection_schema_version';
  static const String _wishlistKey = 'wishlist';
  static const int _currentSchemaVersion = 2;

  static Future<Set<String>> loadWishlist() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_wishlistKey) ?? []).toSet();
  }

  static Future<void> saveWishlist(Set<String> seriesIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_wishlistKey, seriesIds.toList());
  }

  static Future<Map<String, CollectionEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateIfNeeded(prefs);
    final String? collectionJson = prefs.getString(_collectionKey);
    final Map<String, CollectionEntry> collection = {};
    if (collectionJson != null) {
      final Map<String, dynamic> decodedMap = jsonDecode(collectionJson);
      decodedMap.forEach((key, value) {
        collection[key] = CollectionEntry.fromJson(value);
      });
    }
    return collection;
  }

  static Future<void> save(Map<String, CollectionEntry> collection) async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> mapToSave = {};
    collection.forEach((key, value) {
      mapToSave[key] = value.toJson();
    });
    await prefs.setString(_collectionKey, jsonEncode(mapToSave));
  }

  static Future<void> _migrateIfNeeded(SharedPreferences prefs) async {
    final int version = prefs.getInt(_schemaVersionKey) ?? 1;
    if (version >= _currentSchemaVersion) return;
    final String? collectionJson = prefs.getString(_collectionKey);
    if (collectionJson != null) {
      final Map<String, dynamic> oldMap = jsonDecode(collectionJson);
      final allSeries = await GachaRepository.loadAll();
      final newMap = migrateCollectionKeys(oldMap, allSeries);
      await prefs.setString(_collectionKey, jsonEncode(newMap));
    }
    await prefs.setInt(_schemaVersionKey, _currentSchemaVersion);
  }
}

({int total, int thisMonth}) computeSpendSummary(
    Iterable<CollectionEntry> entries,
    Map<String, int> priceBySeriesId,
    DateTime now) {
  int total = 0;
  int thisMonth = 0;
  for (final entry in entries) {
    final separatorIndex = entry.itemId.indexOf('::');
    final seriesId = separatorIndex < 0
        ? entry.itemId
        : entry.itemId.substring(0, separatorIndex);
    final price = entry.paidPrice ?? priceBySeriesId[seriesId] ?? 0;
    total += price;
    final acquiredAt = entry.acquiredAt;
    if (acquiredAt != null &&
        acquiredAt.year == now.year &&
        acquiredAt.month == now.month) {
      thisMonth += price;
    }
  }
  return (total: total, thisMonth: thisMonth);
}

Map<String, dynamic> migrateCollectionKeys(
    Map<String, dynamic> oldMap, List<GachaSeries> allSeries) {
  final Map<String, List<String>> rawIdToNewIds = {};
  for (final series in allSeries) {
    for (final item in series.items) {
      final separatorIndex = item.id.indexOf('::');
      if (separatorIndex < 0) continue;
      final rawId = item.id.substring(separatorIndex + 2);
      rawIdToNewIds.putIfAbsent(rawId, () => []).add(item.id);
    }
  }
  final Map<String, dynamic> newMap = {};
  oldMap.forEach((oldKey, value) {
    final newIds = rawIdToNewIds[oldKey];
    if (newIds == null) {
      newMap[oldKey] = value;
      return;
    }
    final bool isFavorite = value is Map && value['isFavorite'] == true;
    for (final newId in newIds) {
      newMap[newId] = {'itemId': newId, 'isFavorite': isFavorite};
    }
  });
  return newMap;
}
