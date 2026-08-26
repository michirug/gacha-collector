// スクリーンショット撮影用の見本データ投入。
// --dart-define=DEMO_MODE=true のときだけ main() から呼ばれる。リリースビルドには影響しない。
import 'collection_store.dart';
import 'gacha_repository.dart';
import 'models.dart';

/// シード対象のシリーズ(新しい順)。スクショ撮影テストと共有する。
List<GachaSeries> demoCandidateSeries(List<GachaSeries> allSeries) {
  return allSeries
      .where((s) => s.items.length >= 4 && s.items.length <= 10 && s.price > 0)
      .toList()
    ..sort((a, b) => b.releaseDate.compareTo(a.releaseDate));
}

/// 収集途中シリーズの保有アイテム数(6割)
int demoPartialOwnedCount(GachaSeries series) =>
    ((series.items.length * 0.6).ceil()).clamp(1, series.items.length - 1);

/// コンプ済みにするシリーズ数
const int kDemoCompleteSeriesCount = 5;

Future<void> seedDemoData() async {
  final allSeries = await GachaRepository.loadAll();
  final candidates = demoCandidateSeries(allSeries);
  if (candidates.length < 13) return;

  final now = DateTime.now();
  final Map<String, CollectionEntry> collection = {};
  var day = 2;

  void addItem(GachaItem item, {required int daysAgo, int count = 1}) {
    collection[item.id] = CollectionEntry(
      itemId: item.id,
      acquiredAt: now.subtract(Duration(days: daysAgo)),
      count: count,
    );
  }

  // 5シリーズをコンプ(各1つダブりあり) → コンプ実績・ダブり実績・支出1万円超を解禁
  for (final series in candidates.take(kDemoCompleteSeriesCount)) {
    var i = 0;
    for (final item in series.items) {
      addItem(item, daysAgo: day + i, count: i == 1 ? 2 : 1);
      i++;
    }
    day += 9;
  }
  // 4シリーズを収集途中(6割)にする
  for (final series in candidates.skip(kDemoCompleteSeriesCount).take(4)) {
    final takeCount = demoPartialOwnedCount(series);
    var i = 0;
    for (final item in series.items.take(takeCount)) {
      addItem(item, daysAgo: day + i);
      i++;
    }
    day += 11;
  }

  await CollectionStore.save(collection);
  await CollectionStore.saveWishlist(
      candidates.skip(9).take(4).map((s) => s.id).toSet());
}
