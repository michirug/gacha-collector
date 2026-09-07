import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gacha_collector/models.dart';
import 'package:gacha_collector/user_photo_store.dart';
import 'package:image/image.dart' as img;

void main() {
  test('sanitizeJpeg はEXIF(位置情報など)を除去し、長辺を1200px以下に縮小する', () {
    final source = img.Image(width: 2400, height: 1600);
    img.fill(source, color: img.ColorRgb8(200, 100, 50));
    source.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(35, 1);
    source.exif.imageIfd['Make'] = img.IfdValueAscii('TestCamera');
    final bytes = img.encodeJpg(source, quality: 90);
    expect(img.decodeJpgExif(bytes)?.imageIfd['Make']?.toString(), contains('TestCamera'));

    final cleaned = sanitizeJpeg(bytes);
    final decoded = img.decodeJpg(cleaned)!;
    expect(decoded.width, UserPhotoStore.kMaxEdge);
    expect(decoded.height, 800);
    final exif = img.decodeJpgExif(cleaned);
    expect(exif == null || exif.gpsIfd.isEmpty, isTrue);
    expect(exif == null || exif.imageIfd['Make'] == null, isTrue);
  });

  test('sanitizeJpeg は小さい画像を拡大しない・壊れたデータは素通しする', () {
    final small = img.Image(width: 300, height: 400);
    final cleaned = sanitizeJpeg(img.encodeJpg(small));
    final decoded = img.decodeJpg(cleaned)!;
    expect(decoded.width, 300);
    expect(decoded.height, 400);

    final garbage = Uint8List.fromList([1, 2, 3, 4]);
    expect(sanitizeJpeg(garbage), garbage);
  });

  test('CollectionEntry の sharedPhotoId はJSONを往復する', () {
    final entry = CollectionEntry(itemId: 'a::b', photoPath: 'p.jpg', sharedPhotoId: 'uuid-1');
    final restored = CollectionEntry.fromJson(entry.toJson());
    expect(restored.sharedPhotoId, 'uuid-1');
    expect(CollectionEntry.fromJson({'itemId': 'x'}).sharedPhotoId, isNull);
  });
}
