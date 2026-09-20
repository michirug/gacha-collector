import 'package:flutter/material.dart';

import 'collection_store.dart';
import 'gacha_repository.dart';
import 'models.dart';
import 'series_page.dart';
import 'theme.dart';
import 'widgets.dart';
import 'work_tags.dart';

// 検索・絞り込み付きの全商品一覧。month を渡すとその月の発売カレンダーとして動作する
class BrowsePage extends StatefulWidget {
  final DateTime? month;
  final Maker? initialMaker;
  final String? initialTag;
  final String title;

  const BrowsePage({
    super.key,
    this.month,
    this.initialMaker,
    this.initialTag,
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
  String? _selectedTag;
  String _keyword = '';
  late DateTime? _month = widget.month;
  bool _isLoading = true;
  WorkTagIndex? _tagIndex;

  @override
  void initState() {
    super.initState();
    _selectedMaker = widget.initialMaker;
    _selectedTag = widget.initialTag;
    _load();
  }

  Future<void> _load() async {
    final series = await GachaRepository.loadAll();
    final wishlist = await CollectionStore.loadWishlist();
    final tagIndex = _tagIndex ?? await WorkTagIndex.buildAsync(series);
    if (!mounted) return;
    _allSeries = series;
    _wishlist = wishlist;
    _tagIndex = tagIndex;
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
    final keyword = _keyword.trim();
    final month = _month;
    final tagIndex = _tagIndex;
    final tag = _selectedTag;
    final results = _allSeries.where((s) {
      if (_selectedMaker != null && s.maker != _selectedMaker) return false;
      if (month != null &&
          (s.releaseDate.year != month.year || s.releaseDate.month != month.month)) {
        return false;
      }
      if (tag != null && tagIndex?.tagOf(s)?.name != tag) return false;
      // 商品名・アイテム名・作品タグを、かな/全角半角/大文字小文字の違いを無視して AND 検索
      if (keyword.isNotEmpty &&
          !matchesSearch(keyword, [s.name, ...s.items.map((i) => i.name), tagIndex?.tagOf(s)?.name ?? ''])) {
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
          // 作品・シリーズ名タグ(商品名から自動抽出。3シリーズ以上あるものだけ)
          if (_tagIndex != null)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ActionChip(
                      avatar: const Icon(Icons.local_offer_outlined, size: 16),
                      label: Text(_selectedTag ?? '作品でさがす', style: const TextStyle(fontSize: 12)),
                      backgroundColor: _selectedTag != null ? kBrandPurple.withValues(alpha: 0.15) : null,
                      onPressed: _pickTag,
                    ),
                  ),
                  if (_selectedTag != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ActionChip(
                        avatar: const Icon(Icons.close, size: 16),
                        label: const Text('解除', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          _selectedTag = null;
                          _applyFilters();
                        },
                      ),
                    )
                  else
                    for (final tag in _tagIndex!.tags.take(30))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ChoiceChip(
                          label: Text(tag.name, style: const TextStyle(fontSize: 12)),
                          selected: false,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) {
                            _selectedTag = tag.name;
                            _applyFilters();
                          },
                        ),
                      ),
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

  // 全タグから選ぶシート(絞り込み入力付き)
  Future<void> _pickTag() async {
    final index = _tagIndex;
    if (index == null) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _TagPickerSheet(tags: index.tags),
    );
    if (picked == null) return;
    _selectedTag = picked;
    _applyFilters();
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );
}

class _TagPickerSheet extends StatefulWidget {
  final List<WorkTag> tags;
  const _TagPickerSheet({required this.tags});

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final shown = _filter.trim().isEmpty
        ? widget.tags
        : widget.tags.where((t) => matchesSearch(_filter, [t.name])).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              const Expanded(child: Text('作品・シリーズでさがす', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              Text('${widget.tags.length}件', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _filter = v),
              decoration: const InputDecoration(hintText: '作品名で絞り込み', prefixIcon: Icon(Icons.search), isDense: true),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: shown.length,
              itemBuilder: (context, i) {
                final tag = shown[i];
                return ListTile(
                  dense: true,
                  title: Text(tag.name),
                  trailing: Text('${tag.count}シリーズ', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  onTap: () => Navigator.pop(context, tag.name),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
