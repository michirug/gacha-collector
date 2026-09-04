import 'package:flutter/material.dart';

import 'browse_page.dart';
import 'collection_store.dart';
import 'gacha_repository.dart';
import 'models.dart';
import 'series_page.dart';
import 'theme.dart';
import 'widgets.dart';

// ホーム: 今月/来月の新作、ウィッシュリストの発売間近、進行中コレクション、月別カレンダー
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<GachaSeries> _allSeries = [];
  Set<String> _wishlist = {};
  Map<String, CollectionEntry> _collection = {};
  Maker? _selectedMaker;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final series = await GachaRepository.loadAll();
    final wishlist = await CollectionStore.loadWishlist();
    final collection = await CollectionStore.load();
    if (!mounted) return;
    setState(() {
      _allSeries = series;
      _wishlist = wishlist;
      _collection = collection;
      _isLoading = false;
    });
  }

  Future<void> _reloadUserData() async {
    final wishlist = await CollectionStore.loadWishlist();
    final collection = await CollectionStore.load();
    if (!mounted) return;
    setState(() {
      _wishlist = wishlist;
      _collection = collection;
    });
  }

  Future<void> _toggleWishlist(String seriesId) async {
    final wishlist = await CollectionStore.loadWishlist();
    if (!wishlist.remove(seriesId)) wishlist.add(seriesId);
    await CollectionStore.saveWishlist(wishlist);
    if (!mounted) return;
    setState(() => _wishlist = wishlist);
  }

  void _openSeries(GachaSeries series) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ItemListPage(series: series)),
    ).then((_) => _reloadUserData());
  }

  void _openBrowse({DateTime? month, String title = 'さがす'}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BrowsePage(month: month, initialMaker: _selectedMaker, title: title),
      ),
    ).then((_) => _reloadUserData());
  }

  int _collectedCount(GachaSeries s) =>
      s.items.where((i) => _collection.containsKey(i.id)).length;

  Iterable<GachaSeries> get _filtered => _selectedMaker == null
      ? _allSeries
      : _allSeries.where((s) => s.maker == _selectedMaker);

  List<GachaSeries> _releasesIn(DateTime month) {
    final list = _filtered
        .where((s) => s.releaseDate.year == month.year && s.releaseDate.month == month.month)
        .toList();
    list.sort((a, b) {
      final c = a.releaseDate.compareTo(b.releaseDate);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    return list;
  }

  // ウィッシュリストのうち、発売前〜発売から2週間以内のもの
  List<GachaSeries> _upcomingWishes(DateTime now) {
    final threshold = now.subtract(const Duration(days: 14));
    final list = _filtered
        .where((s) => _wishlist.contains(s.id) && s.releaseDate.isAfter(threshold))
        .toList();
    list.sort((a, b) => a.releaseDate.compareTo(b.releaseDate));
    return list;
  }

  List<GachaSeries> _inProgress() {
    final list = _filtered.where((s) {
      final c = _collectedCount(s);
      return c > 0 && c < s.items.length;
    }).toList();
    list.sort((a, b) {
      final rateA = _collectedCount(a) / a.items.length;
      final rateB = _collectedCount(b) / b.items.length;
      return rateB.compareTo(rateA);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ガチャ活ポケット'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'さがす',
            onPressed: () => _openBrowse(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _buildMakerChips(),
                  ..._buildReleaseSection(
                    title: '今月の新作',
                    subtitle: '${thisMonth.month}月発売',
                    month: thisMonth,
                    emptyMessage: '今月の新作情報はまだありません',
                  ),
                  ..._buildWishSection(now),
                  ..._buildProgressSection(),
                  ..._buildReleaseSection(
                    title: '来月の発売予定',
                    subtitle: '${nextMonth.month}月発売予定',
                    month: nextMonth,
                    emptyMessage: '来月の発売予定はまだ公開されていません',
                  ),
                  const SectionHeader('発売カレンダー', subtitle: '月ごとに新作を確認'),
                  _buildMonthChips(now),
                ],
              ),
            ),
    );
  }

  Widget _buildMakerChips() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _chip('すべて', _selectedMaker == null, () => setState(() => _selectedMaker = null)),
          for (final maker in Maker.values.where((m) => m != Maker.other))
            _chip(maker.label, _selectedMaker == maker,
                () => setState(() => _selectedMaker = maker)),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );

  List<Widget> _buildReleaseSection({
    required String title,
    required String subtitle,
    required DateTime month,
    required String emptyMessage,
  }) {
    final releases = _releasesIn(month);
    return [
      SectionHeader(
        title,
        subtitle: '$subtitle・${releases.length}件',
        onMore: releases.isEmpty ? null : () => _openBrowse(month: month),
      ),
      if (releases.isEmpty)
        EmptyHint(icon: Icons.event_busy_outlined, message: emptyMessage)
      else
        SizedBox(
          height: 236,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: releases.length > 12 ? 12 : releases.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final s = releases[index];
              return SeriesPosterCard(
                series: s,
                isWished: _wishlist.contains(s.id),
                onWishTap: () => _toggleWishlist(s.id),
                onTap: () => _openSeries(s),
              );
            },
          ),
        ),
    ];
  }

  List<Widget> _buildWishSection(DateTime now) {
    final wishes = _upcomingWishes(now);
    if (wishes.isEmpty) {
      if (_wishlist.isNotEmpty) return const [];
      return [
        const SectionHeader('ウィッシュリスト'),
        const EmptyHint(
          icon: Icons.star_outline_rounded,
          message: '気になる商品の☆を押すと、発売が近づいたときにここに表示されます',
        ),
      ];
    }
    return [
      const SectionHeader('ウィッシュリスト', subtitle: '発売間近・発売中'),
      for (final s in wishes.take(5))
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SeriesTile(
            series: s,
            isWished: true,
            onWishTap: () => _toggleWishlist(s.id),
            onTap: () => _openSeries(s),
          ),
        ),
    ];
  }

  List<Widget> _buildProgressSection() {
    final progress = _inProgress();
    if (progress.isEmpty) {
      if (_collection.isNotEmpty) return const [];
      return [
        const SectionHeader('コレクションをはじめる'),
        const EmptyHint(
          icon: Icons.touch_app_outlined,
          message: 'シリーズを開いて、持っているアイテムをタップするだけで記録できます。コンプすると演出でお祝い!',
        ),
      ];
    }
    return [
      const SectionHeader('あと少しでコンプ', subtitle: '進行中のコレクション'),
      for (final s in progress.take(3))
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SeriesTile(
            series: s,
            collected: _collectedCount(s),
            onTap: () => _openSeries(s),
          ),
        ),
    ];
  }

  Widget _buildMonthChips(DateTime now) {
    final months = [for (var d = -2; d <= 3; d++) DateTime(now.year, now.month + d)];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final m in months)
            ActionChip(
              avatar: Icon(
                Icons.calendar_month_outlined,
                size: 16,
                color: m.month == now.month ? kBrandPurple : Colors.grey[600],
              ),
              label: Text(
                m.year == now.year ? '${m.month}月' : '${m.year}年${m.month}月',
                style: TextStyle(
                  fontWeight: m.month == now.month ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
              onPressed: () => _openBrowse(month: m),
            ),
        ],
      ),
    );
  }
}
