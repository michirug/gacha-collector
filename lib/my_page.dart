import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'achievements.dart';
import 'backup.dart';
import 'collection_store.dart';
import 'gacha_repository.dart';
import 'models.dart';
import 'series_page.dart';
import 'share_card.dart';
import 'theme.dart';
import 'widgets.dart';

const String kPrivacyPolicyUrl =
    'https://michirug.github.io/gacha-collector/privacy/';
const String kTermsOfServiceUrl =
    'https://michirug.github.io/gacha-collector/terms/';

// --- マイページ ---
class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  List<GachaSeries> _allSeries = [];
  final Map<String, CollectionEntry> _collection = {};
  List<GachaSeries> _collectedSeries = [];
  List<GachaSeries> _wishedSeries = [];
  List<({CollectionEntry entry, GachaItem item, GachaSeries series})>
      _recentAcquisitions = [];
  Set<String> _wishlist = {};
  Set<String> _unlockedAchievements = {};
  int _totalSpend = 0;
  int _monthSpend = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    _allSeries = await GachaRepository.loadAll();
    final loaded = await CollectionStore.load();
    _collection
      ..clear()
      ..addAll(loaded);
    _wishlist = await CollectionStore.loadWishlist();
    await AchievementService.evaluate(
        computeAchievementStats(_collection, _allSeries));
    _unlockedAchievements = await AchievementService.loadUnlocked();
    _processCollectionData();
  }

  int _collectedCount(GachaSeries series) =>
      series.items.where((item) => _collection.containsKey(item.id)).length;

  void _processCollectionData() {
    final collectedSeriesTemp = <GachaSeries>[];
    for (final series in _allSeries) {
      if (series.items.any((item) => _collection.containsKey(item.id))) {
        collectedSeriesTemp.add(series);
      }
    }
    collectedSeriesTemp.sort((a, b) {
      final rateA = a.items.isEmpty ? 0.0 : _collectedCount(a) / a.items.length;
      final rateB = b.items.isEmpty ? 0.0 : _collectedCount(b) / b.items.length;
      final comparison = rateB.compareTo(rateA);
      if (comparison != 0) return comparison;
      return _collectedCount(b).compareTo(_collectedCount(a));
    });

    final wishedSeriesTemp =
        _allSeries.where((series) => _wishlist.contains(series.id)).toList();
    final priceBySeriesId = {
      for (final series in _allSeries) series.id: series.price
    };
    final spend = computeSpendSummary(
        _collection.values, priceBySeriesId, DateTime.now());

    final itemIndex = <String, ({GachaItem item, GachaSeries series})>{};
    for (final series in _allSeries) {
      for (final item in series.items) {
        itemIndex[item.id] = (item: item, series: series);
      }
    }
    final recentTemp =
        <({CollectionEntry entry, GachaItem item, GachaSeries series})>[];
    for (final entry in _collection.values) {
      if (entry.acquiredAt == null) continue;
      final indexed = itemIndex[entry.itemId];
      if (indexed == null) continue;
      recentTemp.add((entry: entry, item: indexed.item, series: indexed.series));
    }
    recentTemp.sort((a, b) => b.entry.acquiredAt!.compareTo(a.entry.acquiredAt!));

    if (!mounted) return;
    setState(() {
      _collectedSeries = collectedSeriesTemp;
      _wishedSeries = wishedSeriesTemp;
      _recentAcquisitions = recentTemp.take(10).toList();
      _totalSpend = spend.total;
      _monthSpend = spend.thisMonth;
      _isLoading = false;
    });
  }

  int get _completedSeriesCount => _collectedSeries
      .where((s) => s.items.every((item) => _collection.containsKey(item.id)))
      .length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('マイページ'),
        actions: [
          IconButton(icon: const Icon(Icons.share), tooltip: 'シェア', onPressed: _shareSummary,),
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
        onRefresh: _loadAllData,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kBrandPurple, kBrandPurpleDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    const Text('コレクションサマリー', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white70)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _stat('収集アイテム数', '${_collection.length}'),
                        _stat('コンプ数', '$_completedSeriesCount'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _stat('総支出', formatYen(_totalSpend)),
                        _stat('今月の支出', formatYen(_monthSpend)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SectionHeader('実績 (${_unlockedAchievements.length}/${allAchievements.length})'),
            SizedBox(
              height: 104,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                children: [
                  for (final achievement in allAchievements)
                    _buildAchievementBadge(achievement),
                ],
              ),
            ),
            if (_recentAcquisitions.isNotEmpty) const SectionHeader('最近の獲得'),
            ..._recentAcquisitions.map(_buildRecentCard),
            if (_wishedSeries.isNotEmpty) const SectionHeader('ウィッシュリスト'),
            for (final series in _wishedSeries)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SeriesTile(
                  series: series,
                  collected: _collectedCount(series),
                  onTap: () => _openSeries(series),
                ),
              ),
            if (_collectedSeries.isNotEmpty) const SectionHeader('獲得中のシリーズ'),
            for (final series in _collectedSeries)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SeriesTile(
                  series: series,
                  collected: _collectedCount(series),
                  onTap: () => _openSeries(series),
                ),
              ),
            const SectionHeader('バックアップ', subtitle: '機種変更やアプリの再インストールに備えて記録を保存できます'),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.upload_file_outlined),
                    title: const Text('バックアップを書き出す'),
                    subtitle: const Text('JSONファイルを共有・保存(自分で撮った写真は含まれません)'),
                    onTap: _exportBackup,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.download_outlined),
                    title: const Text('バックアップから復元'),
                    subtitle: const Text('書き出したJSONファイルを読み込む'),
                    onTap: _importBackup,
                  ),
                ],
              ),
            ),
            const SectionHeader('このアプリについて'),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('プライバシーポリシー'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _openUrl(kPrivacyPolicyUrl),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('利用規約'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _openUrl(kTermsOfServiceUrl),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.gavel_outlined),
                    title: const Text('権利者の方へ(掲載内容の削除依頼)'),
                    subtitle: const Text('商品情報・画像の権利は各権利者に帰属します。ご連絡には速やかに対応します'),
                    trailing: const Icon(Icons.mail_outline, size: 18),
                    onTap: () => _openUrl('mailto:$kContactEmail?subject=${Uri.encodeComponent('【ガチャ活ポケット】掲載内容の削除依頼')}'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
          ],
        ),
      );

  void _openSeries(GachaSeries series) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ItemListPage(series: series)),
    ).then((_) => _loadAllData());
  }

  Future<void> _openUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _exportBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await BackupService.exportAndShare();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('書き出しに失敗しました: $e')));
    }
  }

  Future<void> _importBackup() async {
    final replace = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('バックアップから復元'),
        content: const Text('現在の記録とどう扱いますか?\n\n・追加: 今の記録を残したままバックアップの内容を足します\n・置き換え: 今の記録を消してバックアップの内容にします'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('追加')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('置き換え')),
        ],
      ),
    );
    if (replace == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await BackupService.pickAndRestore(replace: replace);
      if (result == null) return;
      messenger.showSnackBar(SnackBar(
          content: Text('復元しました(アイテム${result.items}件・ウィッシュ${result.wishes}件)')));
      await _loadAllData();
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('復元に失敗しました: $e')));
    }
  }

  Future<void> _shareSummary() async {
    await showShareCardDialog(
      context,
      buildSummaryShareCard(
        totalItems: _collection.length,
        completedSeries: _completedSeriesCount,
        unlockedAchievements: _unlockedAchievements.length,
        totalAchievements: allAchievements.length,
      ),
      'gacha_collection_summary.png',
      'ガチャ活の記録 #ガチャ活ポケット #ガチャ活',
    );
  }

  Widget _buildAchievementBadge(Achievement achievement) {
    final unlocked = _unlockedAchievements.contains(achievement.id);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: InkWell(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  Icon(unlocked ? achievement.icon : Icons.lock, color: unlocked ? Colors.amber[700] : Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(child: Text(achievement.title, style: const TextStyle(fontSize: 18))),
                ],
              ),
              content: Text(unlocked ? achievement.description : '???　${achievement.description}'),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
            ),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: unlocked ? Colors.amber[100] : Colors.grey[300],
              child: Icon(unlocked ? achievement.icon : Icons.lock, color: unlocked ? Colors.amber[800] : Colors.grey, size: 28),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 64,
              child: Text(achievement.title, style: TextStyle(fontSize: 10, color: unlocked ? Colors.black87 : Colors.grey), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentCard(
      ({CollectionEntry entry, GachaItem item, GachaSeries series}) record) {
    final acquiredAt = record.entry.acquiredAt!;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: ListTile(
        dense: true,
        leading: GachaImage(record.item.image, maker: record.series.maker, width: 48, height: 48, borderRadius: BorderRadius.circular(8)),
        title: Text(record.item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(record.series.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text('${acquiredAt.month}/${acquiredAt.day}', style: TextStyle(color: Colors.grey[600])),
        onTap: () => _openSeries(record.series),
      ),
    );
  }
}
