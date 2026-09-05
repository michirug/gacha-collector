import 'package:flutter_test/flutter_test.dart';
import 'package:gacha_collector/image_policy.dart';
import 'package:gacha_collector/models.dart';

void main() {
  tearDown(() {
    ImagePolicy.hiddenMakers.value = {};
    ImagePolicy.hiddenSeries.value = {};
  });

  test('リモート設定でメーカー単位・シリーズ単位に公式画像を非表示にできる', () {
    ImagePolicy.apply('{"hide_official_images":["bandai","kitan"],"hide_series":["tta:Y1"]}');
    expect(ImagePolicy.isMakerHidden(Maker.bandai), isTrue);
    expect(ImagePolicy.isMakerHidden(Maker.kitan), isTrue);
    expect(ImagePolicy.isMakerHidden(Maker.sota), isFalse);
    expect(ImagePolicy.isMakerHidden(null), isFalse);
    expect(ImagePolicy.isSeriesHidden('tta:Y1'), isTrue);
    expect(ImagePolicy.isSeriesHidden('tta:Y2'), isFalse);
  });

  test('壊れた設定は無視して直前の状態を保つ', () {
    ImagePolicy.apply('{"hide_official_images":["bandai"]}');
    ImagePolicy.apply('not json');
    expect(ImagePolicy.isMakerHidden(Maker.bandai), isTrue);
    ImagePolicy.apply('{"hide_official_images":[]}');
    expect(ImagePolicy.isMakerHidden(Maker.bandai), isFalse);
  });

  test('CollectionEntryの写真ファイル名はJSONを往復する', () {
    final entry = CollectionEntry(itemId: 'a::b', photoPath: 'a_b_1.jpg');
    final restored = CollectionEntry.fromJson(entry.toJson());
    expect(restored.photoPath, 'a_b_1.jpg');
    expect(CollectionEntry.fromJson({'itemId': 'x'}).photoPath, isNull);
  });
}
