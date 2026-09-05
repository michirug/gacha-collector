import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'achievements.dart';
import 'celebration.dart';
import 'collection_store.dart';
import 'gacha_repository.dart';
import 'models.dart';
import 'share_card.dart';
import 'theme.dart';
import 'user_photo_store.dart';
import 'widgets.dart';

const String kContactEmail = 'info@contentsmarketing.co.jp';

// ItemListPage (シリーズ詳細ページ)
class ItemListPage extends StatefulWidget {
  final GachaSeries series;
  const ItemListPage({super.key, required this.series});
  @override
  State<ItemListPage> createState() => _ItemListPageState();
}

class _ItemListPageState extends State<ItemListPage> {
  final Map<String, CollectionEntry> _collection = {};
  bool _isSeriesCompleted = false;
  bool _isWished = false;
  @override
  void initState() {
    super.initState();
    _loadCollection();
  }
  Future<void> _loadCollection() async {
    final loaded = await CollectionStore.load();
    final wishlist = await CollectionStore.loadWishlist();
    if (!mounted) return;
    setState(() {
      _collection
        ..clear()
        ..addAll(loaded);
      _isWished = wishlist.contains(widget.series.id);
    });
    // 初回ロード時は状態の同期のみ行い、演出は出さない(コンプ済みを開くたびに再生されるのを防ぐ)
    _checkCompletion(celebrate: false);
    _loadUserPhotos();
  }
  Future<void> _toggleWishlist() async {
    final wishlist = await CollectionStore.loadWishlist();
    if (!wishlist.remove(widget.series.id)) {
      wishlist.add(widget.series.id);
    }
    await CollectionStore.saveWishlist(wishlist);
    if (!mounted) return;
    setState(() { _isWished = wishlist.contains(widget.series.id); });
  }
  Future<void> _saveCollection() async {
    await CollectionStore.save(_collection);
  }

  void _toggleItemStatus(String itemId) {
    setState(() {
      if (_collection.containsKey(itemId)) {
        _collection.remove(itemId);
      } else {
        _collection[itemId] = CollectionEntry(
          itemId: itemId,
          acquiredAt: DateTime.now(),
          paidPrice: widget.series.price,
        );
      }
    });
    _saveCollection();
    _checkCompletion();
    _checkAchievements();
  }

  void _changeItemCount(String itemId, int delta) {
    final entry = _collection[itemId];
    if (entry == null) return;
    setState(() {
      entry.count = (entry.count + delta).clamp(1, 99);
    });
    _saveCollection();
    _checkAchievements();
  }

  Future<void> _checkAchievements() async {
    final allSeries = await GachaRepository.loadAll();
    final stats = computeAchievementStats(_collection, allSeries);
    final newly = await AchievementService.evaluate(stats);
    if (!mounted || newly.isEmpty) return;
    for (final achievement in newly) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🏆 実績解除: ${achievement.title}')),
      );
    }
  }

  Future<void> _showCountSheet(GachaItem item) async {
    await showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(builder: (sheetContext, setSheetState) {
          final current = _collection[item.id]?.count ?? 1;
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,),
                const SizedBox(height: 8),
                Text(current > 1 ? 'ダブり ${current - 1}個' : 'ダブりなし', style: TextStyle(color: Colors.grey[600]),),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(onPressed: current > 1 ? () { _changeItemCount(item.id, -1); setSheetState(() {}); } : null, icon: const Icon(Icons.remove_circle_outline, size: 32),),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Text('所持数 $current', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),),),
                    IconButton(onPressed: current < 99 ? () { _changeItemCount(item.id, 1); setSheetState(() {}); } : null, icon: const Icon(Icons.add_circle_outline, size: 32),),
                  ],
                ),
                const Divider(height: 24),
                Text('自分の写真', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey[700])),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () { Navigator.pop(sheetContext); _setUserPhoto(item, ImageSource.camera); },
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('撮る'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () { Navigator.pop(sheetContext); _setUserPhoto(item, ImageSource.gallery); },
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('アルバム'),
                    ),
                    if (_collection[item.id]?.photoPath != null)
                      TextButton.icon(
                        onPressed: () { Navigator.pop(sheetContext); _removeUserPhoto(item); },
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('写真を削除'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        });
      },
    );
  }

  Future<void> _setUserPhoto(GachaItem item, ImageSource source) async {
    final entry = _collection[item.id];
    if (entry == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final fileName = await UserPhotoStore.pickAndSave(item.id, source);
      if (fileName == null) return;
      await UserPhotoStore.delete(entry.photoPath);
      entry.photoPath = fileName;
      await _saveCollection();
      await _loadUserPhotos();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('写真を保存できませんでした: $e')));
    }
  }

  Future<void> _removeUserPhoto(GachaItem item) async {
    final entry = _collection[item.id];
    if (entry == null) return;
    await UserPhotoStore.delete(entry.photoPath);
    entry.photoPath = null;
    await _saveCollection();
    await _loadUserPhotos();
  }

  // photoPath(ファイル名) → File の解決結果。表示用にキャッシュする
  final Map<String, File> _userPhotos = {};
  Future<void> _loadUserPhotos() async {
    final resolved = <String, File>{};
    for (final item in widget.series.items) {
      final path = _collection[item.id]?.photoPath;
      if (path == null) continue;
      final file = await UserPhotoStore.fileFor(path);
      if (await file.exists()) resolved[item.id] = file;
    }
    if (!mounted) return;
    setState(() {
      _userPhotos
        ..clear()
        ..addAll(resolved);
    });
  }

  Future<void> _contactAboutSeries() async {
    final subject = Uri.encodeComponent('【ガチャ活ポケット】掲載内容について(${widget.series.id})');
    final body = Uri.encodeComponent('対象商品: ${widget.series.name}\n公式URL: ${widget.series.sourceUrl}\n\nご用件(削除依頼・誤り指摘など):\n');
    await launchUrl(Uri.parse('mailto:$kContactEmail?subject=$subject&body=$body'));
  }

  Future<void> _shareSeries() async {
    final collected = widget.series.items.where((item) => _collection.containsKey(item.id)).length;
    final total = widget.series.items.length;
    await showShareCardDialog(
      context,
      buildSeriesShareCard(series: widget.series, collected: collected, total: total),
      'gacha_series_share.png',
      '「${widget.series.name}」獲得 $collected/$total #ガチャ活ポケット #ガチャ活',
    );
  }

  Future<void> _shareTrade() async {
    final duplicates = <GachaItem>[];
    final wanted = <GachaItem>[];
    for (final item in widget.series.items) {
      final entry = _collection[item.id];
      if (entry == null) {
        wanted.add(item);
      } else if (entry.count > 1) {
        duplicates.add(item);
      }
    }
    if (duplicates.isEmpty && wanted.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ダブりも未獲得もないため譲/求カードは作れません')));
      return;
    }
    final giveText = duplicates.map((i) => i.name).join('、');
    final wantText = wanted.map((i) => i.name).join('、');
    await showShareCardDialog(
      context,
      buildTradeShareCard(
        series: widget.series,
        give: duplicates,
        want: wanted,
        counts: {for (final d in duplicates) d.id: _collection[d.id]!.count - 1},
      ),
      'gacha_trade_share.png',
      '【交換希望】${widget.series.name}\n'
      '譲: ${giveText.isEmpty ? "なし" : giveText}\n'
      '求: ${wantText.isEmpty ? "なし" : wantText}\n'
      '#ガチャ活ポケット #ガチャ活 #ガチャ交換',
    );
  }

  void _checkCompletion({bool celebrate = true}) {
    bool allItemsOwned = widget.series.items.every((item) => _collection.containsKey(item.id));
    if (_isSeriesCompleted != allItemsOwned) {
      setState(() { _isSeriesCompleted = allItemsOwned; });
      if (allItemsOwned && celebrate) { _playCompletionAnimation(); }
    }
  }
  void _playCompletionAnimation() {
    if (!mounted) return;
    showCompletionCelebration(context, widget.series);
  }

  Future<void> _openSource() async {
    final url = widget.series.sourceUrl;
    if (url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final collectedCount = series.items.where((i) => _collection.containsKey(i.id)).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(series.name, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(icon: const Icon(Icons.swap_horiz), tooltip: '譲/求カード', onPressed: _shareTrade,),
          IconButton(icon: const Icon(Icons.share), tooltip: 'シェア', onPressed: _shareSeries,),
          IconButton(icon: Icon(_isWished ? Icons.star_rounded : Icons.star_outline_rounded, color: _isWished ? Colors.amber[700] : null), tooltip: 'ウィッシュリスト', onPressed: _toggleWishlist,),
        ],
      ),
      body: SafeArea(
        child: ListView(
          children: [
            GachaImage(series.mainImage, maker: series.maker, height: 250, width: double.infinity),
            Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 0), child: ImageCredit(series.maker)),
            Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MakerBadge(series.maker),
                  if (series.maker == Maker.bandai) _InfoChip(series.gachaType.label),
                  _InfoChip(formatYen(series.price)),
                  if (series.releaseDateText.isNotEmpty) _InfoChip(series.releaseDateText),
                  if (series.numTypes != null && series.numTypes!.isNotEmpty) _InfoChip(series.numTypes!),
                  if (series.targetAge != null && series.targetAge!.isNotEmpty) _InfoChip('対象年齢 ${series.targetAge}'),
                ],
              ),
              const SizedBox(height: 16),
              if (series.sourceUrl.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _openSource,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('公式サイトで見る'),
                  ),
                ),
              const SizedBox(height: 8),
              _isSeriesCompleted
                  ? const Text('🎉 このシリーズはコンプリート済みです！🎉', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kBrandPurpleDark),)
                  : Text('獲得 $collectedCount / ${series.items.length}', style: const TextStyle(fontSize: 16, color: Colors.grey),),
            ],),),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('アイテム一覧', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),),
                  Text('タップで獲得切替・獲得済みを長押しでダブり数や自分の写真を登録', style: TextStyle(fontSize: 12, color: Colors.grey[600]),),
                  if (series.lineupUnknown)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('公式サイトにラインナップ名の掲載がないため、番号(No.)で管理します',
                          style: TextStyle(fontSize: 12, color: kBrandPinkDark)),
                    ),
                ],
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(8.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: series.items.length,
              itemBuilder: (context, index) {
                final item = series.items[index];
                final entry = _collection[item.id];
                final isFound = entry != null;

                return InkWell(
                  onTap: () => _toggleItemStatus(item.id),
                  onLongPress: isFound ? () => _showCountSheet(item) : null,
                  child: GridTile(
                    footer: GridTileBar(
                      backgroundColor: Colors.black45,
                      title: Text(item.name, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center,),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Opacity(
                          opacity: isFound ? 1.0 : 0.3,
                          child: GachaImage(item.image, maker: series.maker, localFile: _userPhotos[item.id], borderRadius: BorderRadius.circular(10)),
                        ),
                        if (isFound)
                          const Center(
                            child: Icon(Icons.check_circle, color: Colors.greenAccent, size: 40, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                          ),
                        if (entry != null && entry.count > 1)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: kBrandPurple, borderRadius: BorderRadius.circular(10)),
                              child: Text('×${entry.count}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('商品情報・画像の権利は各権利者に帰属します。掲載内容の削除依頼や誤りのご指摘は下記からお願いします。',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.4)),
                  TextButton.icon(
                    onPressed: _contactAboutSeries,
                    icon: const Icon(Icons.mail_outline, size: 16),
                    label: const Text('この商品の掲載について問い合わせる', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String text;
  const _InfoChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kBrandPurple.withValues(alpha: 0.15)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, color: kBrandInk)),
    );
  }
}
