import 'package:flutter/material.dart';
import 'collection_store.dart';
import 'gacha_repository.dart';
import 'models.dart';

void main() {
  runApp(const GachaCollectorApp());
}

// アプリ全体の設計図
class GachaCollectorApp extends StatelessWidget {
  const GachaCollectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ガチャコレクション',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

// --- ボトムナビゲーションバーを持つアプリの骨格 ---
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = <Widget>[
    HomePage(),
    MyPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'ホーム',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'マイページ',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}


String formatYen(int amount) {
  final digits = amount.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (match) => '${match[1]},');
  return '$digits円';
}

// ホーム画面（シリーズ一覧）
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<GachaSeries> _allSeries = [];
  List<GachaSeries> _foundSeries = [];
  Set<String> _wishlist = {};
  bool _isLoading = true;
  @override
  void initState() {
    super.initState();
    _loadGachaData();
  }
  Future<void> _loadGachaData() async {
    final seriesList = await GachaRepository.loadAll();
    final wishlist = await CollectionStore.loadWishlist();
    if (!mounted) return;
    setState(() {
      _allSeries = seriesList;
      _foundSeries = _allSeries;
      _wishlist = wishlist;
      _isLoading = false;
    });
  }
  Future<void> _toggleWishlist(String seriesId) async {
    final wishlist = await CollectionStore.loadWishlist();
    if (!wishlist.remove(seriesId)) {
      wishlist.add(seriesId);
    }
    await CollectionStore.saveWishlist(wishlist);
    if (!mounted) return;
    setState(() { _wishlist = wishlist; });
  }
  Future<void> _reloadWishlist() async {
    final wishlist = await CollectionStore.loadWishlist();
    if (!mounted) return;
    setState(() { _wishlist = wishlist; });
  }
  void _runFilter(String enteredKeyword) {
    List<GachaSeries> results = [];
    if (enteredKeyword.isEmpty) {
      results = _allSeries;
    } else {
      results = _allSeries.where((series) => series.name.toLowerCase().contains(enteredKeyword.toLowerCase())).toList();
    }
    setState(() { _foundSeries = results; });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ガチャコレクション'), backgroundColor: Colors.deepPurple[100],),
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.all(8.0), child: TextField(onChanged: (value) => _runFilter(value), decoration: const InputDecoration(labelText: '検索', suffixIcon: Icon(Icons.search),),),),
          Expanded(child: _isLoading ? const Center(child: CircularProgressIndicator()) : _foundSeries.isEmpty ? const Center(child: Text('データが見つかりません…')) : ListView.builder(itemCount: _foundSeries.length, itemBuilder: (context, index) {
            final series = _foundSeries[index];
            final isWished = _wishlist.contains(series.id);
            return Card(margin: const EdgeInsets.all(8.0), child: ListTile(leading: Image.network(series.mainImage, width: 60, height: 60, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) { return const Icon(Icons.error, size: 60); },), title: Text(series.name), subtitle: Text(series.gachaType.label), trailing: IconButton(icon: Icon(isWished ? Icons.star : Icons.star_border, color: isWished ? Colors.amber : Colors.grey), tooltip: 'ウィッシュリスト', onPressed: () => _toggleWishlist(series.id),), onTap: () { Navigator.push(context, MaterialPageRoute(builder: (context) => ItemListPage(series: series),),).then((_) => _reloadWishlist()); },),);
          },),),
        ],
      ),
    );
  }
}

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
  Set<String> _wishlist = {};
  int _totalSpend = 0;
  int _monthSpend = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    // 1. 図鑑データをJSONから読み込む
    _allSeries = await GachaRepository.loadAll();

    // 2. 個人コレクションデータを読み込む
    final loaded = await CollectionStore.load();
    _collection
      ..clear()
      ..addAll(loaded);
    _wishlist = await CollectionStore.loadWishlist();

    // 3. 表示用データを加工する
    _processCollectionData();
  }

  void _processCollectionData() {
    List<GachaSeries> collectedSeriesTemp = [];

    for (var series in _allSeries) {
      bool hasAnyItem = series.items.any((item) => _collection.containsKey(item.id));
      if (hasAnyItem) {
        collectedSeriesTemp.add(series);
      }
    }

    // --- 並び替えロジック ---
    collectedSeriesTemp.sort((a, b) {
      // aの獲得率と獲得数を計算
      final collectedA = a.items.where((item) => _collection.containsKey(item.id)).length;
      final totalA = a.items.length;
      final rateA = totalA > 0 ? collectedA / totalA : 0.0;

      // bの獲得率と獲得数を計算
      final collectedB = b.items.where((item) => _collection.containsKey(item.id)).length;
      final totalB = b.items.length;
      final rateB = totalB > 0 ? collectedB / totalB : 0.0;

      // 1. 獲得率で比較 (降順)
      int comparison = rateB.compareTo(rateA);
      if (comparison != 0) {
        return comparison;
      }

      // 2. 獲得率が同じなら、獲得数で比較 (降順)
      return collectedB.compareTo(collectedA);
    });

    final wishedSeriesTemp =
        _allSeries.where((series) => _wishlist.contains(series.id)).toList();
    final priceBySeriesId = {
      for (final series in _allSeries) series.id: series.price
    };
    final spend = computeSpendSummary(
        _collection.values, priceBySeriesId, DateTime.now());

    if (!mounted) return;
    setState(() {
      _collectedSeries = collectedSeriesTemp;
      _wishedSeries = wishedSeriesTemp;
      _totalSpend = spend.total;
      _monthSpend = spend.thisMonth;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    int totalCollectedItems = _collection.length;
    int completedSeriesCount = 0;
    for (var series in _collectedSeries) {
      bool isComplete = series.items.every((item) => _collection.containsKey(item.id));
      if (isComplete) {
        completedSeriesCount++;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('マイページ'),
        backgroundColor: Colors.deepPurple[100],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator( // --- 画面を下に引っ張って更新する機能 ---
        onRefresh: _loadAllData,
        child: ListView(
          children: [
            Card(
              margin: const EdgeInsets.all(16.0),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text('コレクションサマリー', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text('収集アイテム数', style: TextStyle(color: Colors.grey[600])),
                            Text('$totalCollectedItems', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          children: [
                            Text('コンプ数', style: TextStyle(color: Colors.grey[600])),
                            Text('$completedSeriesCount', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text('総支出', style: TextStyle(color: Colors.grey[600])),
                            Text(formatYen(_totalSpend), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          children: [
                            Text('今月の支出', style: TextStyle(color: Colors.grey[600])),
                            Text(formatYen(_monthSpend), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_wishedSeries.isNotEmpty) _buildSectionHeader('ウィッシュリスト'),
            ..._wishedSeries.map(_buildWishCard),
            if (_collectedSeries.isNotEmpty) _buildSectionHeader('獲得中のシリーズ'),
            ..._collectedSeries.map(_buildCollectedCard),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildWishCard(GachaSeries series) {
    final collectedCount = series.items.where((item) => _collection.containsKey(item.id)).length;
    final totalCount = series.items.length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: ListTile(
        leading: Image.network(
          series.mainImage,
          width: 60, height: 60, fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(width: 60, height: 60, color: Colors.grey[200], child: const Icon(Icons.error, size: 30));
          },
        ),
        title: Text(series.name, maxLines: 2, overflow: TextOverflow.ellipsis,),
        subtitle: Text('獲得 $collectedCount / $totalCount・${formatYen(series.price)}'),
        trailing: const Icon(Icons.star, color: Colors.amber),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ItemListPage(series: series),),
          ).then((_) => _loadAllData());
        },
      ),
    );
  }

  Widget _buildCollectedCard(GachaSeries series) {
    final collectedCount = series.items.where((item) => _collection.containsKey(item.id)).length;
    final totalCount = series.items.length;
    final isComplete = collectedCount == totalCount;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: ListTile(
        leading: Image.network(
          series.mainImage,
          width: 60, height: 60, fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(width: 60, height: 60, color: Colors.grey[200], child: const Icon(Icons.error, size: 30));
          },
        ),
        title: Text(series.name, maxLines: 2, overflow: TextOverflow.ellipsis,),
        subtitle: Row(
          children: [
            // --- 変更：「○ / ○」表示 ---
            Text('獲得 $collectedCount / $totalCount'),
            const SizedBox(width: 8),
            if (isComplete)
              const Chip(
                label: Text('コンプリート！', style: TextStyle(fontSize: 12, color: Colors.white)),
                backgroundColor: Colors.amber,
                padding: EdgeInsets.zero,
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ItemListPage(series: series),),
          ).then((_) => _loadAllData());
        },
      ),
    );
  }
}


// ItemListPage (詳細ページ)
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
    _checkCompletion();
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
  }

  void _checkCompletion() {
    bool allItemsOwned = widget.series.items.every((item) => _collection.containsKey(item.id));
    if (_isSeriesCompleted != allItemsOwned) {
      setState(() { _isSeriesCompleted = allItemsOwned; });
      if (allItemsOwned) { _playCompletionAnimation(); }
    }
  }
  void _playCompletionAnimation() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('🎉 シリーズコンプリート！おめでとうございます！ 🎉', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),), backgroundColor: Colors.deepPurpleAccent, duration: const Duration(seconds: 3), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), margin: const EdgeInsets.all(20),),);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.series.name), backgroundColor: Colors.deepPurple[100], actions: [IconButton(icon: Icon(_isWished ? Icons.star : Icons.star_border, color: _isWished ? Colors.amber : null), tooltip: 'ウィッシュリスト', onPressed: _toggleWishlist,)],),
      body: SafeArea(
        child: ListView(
          children: [
            Image.network(widget.series.mainImage, height: 250, width: double.infinity, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) { return Container(height: 250, color: Colors.grey[300], child: const Center(child: Text('画像なし')),); },),
            Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('種類: ${widget.series.gachaType.label}'),
              Text('価格: ${widget.series.price}円'),
              if (widget.series.numTypes != null && widget.series.numTypes!.isNotEmpty)
                Text(widget.series.numTypes!),
              if (widget.series.targetAge != null && widget.series.targetAge!.isNotEmpty)
                Text('対象年齢: ${widget.series.targetAge}'),
              const SizedBox(height: 16),
              if (widget.series.description != null && widget.series.description!.isNotEmpty)
                Text(widget.series.description!),
              const SizedBox(height: 16),
              _isSeriesCompleted
                  ? const Text('🎉 このシリーズはコンプリート済みです！🎉', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple),)
                  : Text('獲得 ${widget.series.items.where((i) => _collection.containsKey(i.id)).length} / ${widget.series.items.length}', style: const TextStyle(fontSize: 16, color: Colors.grey),),
            ],),),
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text('アイテム一覧', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),),
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
              itemCount: widget.series.items.length,
              itemBuilder: (context, index) {
                final item = widget.series.items[index];
                final isFound = _collection.containsKey(item.id);

                return InkWell(
                  onTap: () => _toggleItemStatus(item.id),
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
                          child: Image.network(
                            item.image,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(color: Colors.grey[200], child: const Icon(Icons.broken_image));
                            },
                          ),
                        ),
                        if (isFound)
                          const Center(
                            child: Icon(Icons.check_circle, color: Colors.greenAccent, size: 40, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}