import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'collection_store.dart';
import 'models.dart';

// コレクション・ウィッシュリストのバックアップ(JSON)を作成・復元する。
// フォーマット: {"app":"gacha_collector","version":1,"exportedAt":ISO8601,"collection":{itemId:entry},"wishlist":[seriesId]}
class BackupService {
  static const String kApp = 'gacha_collector';
  static const int kVersion = 1;

  static Map<String, dynamic> buildBackup(
      Map<String, CollectionEntry> collection, Set<String> wishlist, DateTime now) {
    return {
      'app': kApp,
      'version': kVersion,
      'exportedAt': now.toIso8601String(),
      'collection': {for (final e in collection.entries) e.key: e.value.toJson()},
      'wishlist': wishlist.toList()..sort(),
    };
  }

  // 戻り値: 復元したコレクション件数とウィッシュリスト件数。不正なファイルは FormatException
  static ({Map<String, CollectionEntry> collection, Set<String> wishlist}) parseBackup(
      String jsonText) {
    final dynamic decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic> || decoded['app'] != kApp) {
      throw const FormatException('ガチャ活ポケットのバックアップファイルではありません');
    }
    final rawCollection = decoded['collection'];
    final rawWishlist = decoded['wishlist'];
    if (rawCollection is! Map<String, dynamic> || rawWishlist is! List) {
      throw const FormatException('バックアップの内容が壊れています');
    }
    final collection = <String, CollectionEntry>{};
    rawCollection.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        collection[key] = CollectionEntry.fromJson(value);
      }
    });
    return (
      collection: collection,
      wishlist: rawWishlist.map((e) => e.toString()).toSet(),
    );
  }

  // 既存データに上書きせずマージする(バックアップ側に無いものは残す、重複は所持数の大きい方)
  static Map<String, CollectionEntry> merge(
      Map<String, CollectionEntry> current, Map<String, CollectionEntry> incoming) {
    final merged = Map<String, CollectionEntry>.from(current);
    incoming.forEach((key, entry) {
      final existing = merged[key];
      if (existing == null || entry.count > existing.count) {
        merged[key] = entry;
      }
    });
    return merged;
  }

  static Future<void> exportAndShare() async {
    final collection = await CollectionStore.load();
    final wishlist = await CollectionStore.loadWishlist();
    final now = DateTime.now();
    final json = const JsonEncoder.withIndent('  ')
        .convert(buildBackup(collection, wishlist, now));
    final dir = await getTemporaryDirectory();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final file = File('${dir.path}${Platform.pathSeparator}gacha_pocket_backup_$stamp.json');
    await file.writeAsString(json, flush: true);
    await Share.shareXFiles([XFile(file.path, mimeType: 'application/json')],
        text: 'ガチャ活ポケット バックアップ ($stamp)');
  }

  // ファイルを選んで復元する。戻り値 null はキャンセル
  static Future<({int items, int wishes})?> pickAndRestore({required bool replace}) async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.first;
    final bytes = picked.bytes ??
        (picked.path != null ? await File(picked.path!).readAsBytes() : null);
    if (bytes == null) throw const FormatException('ファイルを読み込めませんでした');
    final parsed = parseBackup(utf8.decode(bytes));

    final collection = replace
        ? parsed.collection
        : merge(await CollectionStore.load(), parsed.collection);
    final wishlist = replace
        ? parsed.wishlist
        : ({...await CollectionStore.loadWishlist(), ...parsed.wishlist});
    await CollectionStore.save(collection);
    await CollectionStore.saveWishlist(wishlist);
    return (items: collection.length, wishes: wishlist.length);
  }
}
