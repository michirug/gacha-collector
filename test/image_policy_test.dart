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

  test('CollectionEntryのメモ・場所はJSONを往復し、空文字は未設定として扱う', () {
    final entry = CollectionEntry(itemId: 'a::b', memo: '3回目で出た', place: 'イオン 3F');
    final json = entry.toJson();
    expect(json['memo'], '3回目で出た');
    expect(json['place'], 'イオン 3F');
    final restored = CollectionEntry.fromJson(json);
    expect(restored.memo, '3回目で出た');
    expect(restored.place, 'イオン 3F');
    expect(restored.hasNote, isTrue);
    final blank = CollectionEntry.fromJson({'itemId': 'x', 'memo': '  ', 'place': ''});
    expect(blank.memo, isNull);
    expect(blank.place, isNull);
    expect(blank.hasNote, isFalse);
    expect(CollectionEntry(itemId: 'y', memo: '').toJson().containsKey('memo'), isFalse);
  });
}
