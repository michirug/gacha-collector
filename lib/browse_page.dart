import 'package:flutter/material.dart';

import 'collection_store.dart';
import 'gacha_repository.dart';
import 'models.dart';
import 'series_page.dart';
import 'theme.dart';
import 'widgets.dart';

// 検索・絞り込み付きの全商品一覧。month を渡すとその月の発売カレンダーとして動作する
class BrowsePage extends StatefulWidget {
  final DateTime? month;
  final Maker? initialMaker;
  final String title;

  const BrowsePage({
    super.key,
    this.month,
    this.initialMaker,
    this.title = 'さがす',
  });

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  List<GachaSeries> _allSeries = [];
  List<GachaSeries> _found = [];
  Set<String> _wishlist = {};
  Maker? _selectedMaker;
  String _keyword = '';
  late DateTime? _month = widget.month;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedMaker = widget.initialMaker;
    _load();
  }

  Future<void> _load() async {
    final series = await GachaRepository.loadAll();
    final wishlist = await CollectionStore.loadWishlist();
    if (!mounted) return;
    _allSeries = series;
    _wishlist = wishlist;
    _isLoading = false;
    _applyFilters();
  }

  Future<void> _toggleWishlist(String seriesId) async {
    final wishlist = await CollectionStore.loadWishlist();
    if (!wishlist.remove(seriesId)) wishlist.add(seriesId);
    await CollectionStore.saveWishlist(wishlist);
    if (!mounted) return;
    setState(() => _wishlist = wishlist);
  }

  void _applyFilters() {
    final keyword = _keyword.toLowerCase();
    final month = _month;
    final results = _allSeries.where((s) {
      if (_selectedMaker != null && s.maker != _selectedMaker) return false;
      if (month != null &&
          (s.releaseDate.year != month.year || s.releaseDate.month != month.month)) {
        return false;
      }
      if (keyword.isNotEmpty &&
          !s.name.toLowerCase().contains(keyword) &&
          !s.items.any((i) => i.name.toLowerCase().contains(keyword))) {
        return false;
      }
      return true;
    }).toList();
    if (month != null) {
      // カレンダー表示は月内を発売日の早い順に
      results.sort((a, b) {
        final c = a.releaseDate.compareTo(b.releaseDate);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    }
    setState(() => _found = results);
  }

  void _shiftMonth(int delta) {
    final m = _month!;
    _month = DateTime(m.year, m.month + delta);
    _applyFilters();
  }

  @override
  Widget build(BuildContext context) {
    final month = _month;
    return Scaffold(
      appBar: AppBar(
        title: Text(month == null ? widget.title : '発売カレンダー'),
      ),
      body: Column(
        children: [
          if (month != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left)),
                  Expanded(
                    child: Text('${month.year}年${month.month}月',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kBrandInk)),
                  ),
                  IconButton(onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              onChanged: (v) {
                _keyword = v;
                _applyFilters();
              },
              decoration: const InputDecoration(
                hintText: '商品名・キャラクター名で検索',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip('すべて', _selectedMaker == null, () {
                  _selectedMaker = null;
                  _applyFilters();
                }),
                for (final maker in Maker.values.where((m) => m != Maker.other))
                  _chip(maker.label, _selectedMaker == maker, () {
                    _selectedMaker = maker;
                    _applyFilters();
                  }),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _found.isEmpty
                    ? const Center(child: Text('該当する商品がありません'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: _found.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text('${_found.length}件',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            );
                          }
                          final series = _found[index - 1];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SeriesTile(
                              series: series,
                              isWished: _wishlist.contains(series.id),
                              onWishTap: () => _toggleWishlist(series.id),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => ItemListPage(series: series)),
                              ).then((_) => _load()),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );
}
