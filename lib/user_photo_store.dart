import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

// ユーザーが撮った写真を端末内(アプリ専用領域/photos)に保存する。
// CollectionEntry.photoPath にはファイル名だけを持ち、表示時にディレクトリと結合する。
// 保存時に再エンコードして EXIF(位置情報など)を除去し、長辺を kMaxEdge 以下に揃える。
class UserPhotoStore {
  static const int kMaxEdge = 1200;
  static final ImagePicker _picker = ImagePicker();
  static Directory? _dir;

  static Future<Directory> _photoDir() async {
    if (_dir != null) return _dir!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}${Platform.pathSeparator}photos');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  static Future<File> fileFor(String fileName) async {
    final dir = await _photoDir();
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  // 戻り値: 保存したファイル名。キャンセル時は null
  static Future<String?> pickAndSave(String itemId, ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 90,
    );
    if (picked == null) return null;
    final raw = await picked.readAsBytes();
    final cleaned = await compute(sanitizeJpeg, raw);
    final fileName = '${_safeName(itemId)}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final target = await fileFor(fileName);
    await target.writeAsBytes(cleaned, flush: true);
    return fileName;
  }

  static Future<void> delete(String? fileName) async {
    if (fileName == null || fileName.isEmpty) return;
    final file = await fileFor(fileName);
    if (await file.exists()) await file.delete();
  }

  static String _safeName(String itemId) {
    final safe = itemId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.length > 60 ? safe.substring(0, 60) : safe;
  }
}

// 画像をデコードして向きを確定し、長辺を制限してJPEGに再エンコードする。
// 再エンコードにより EXIF などのメタデータは含まれなくなる。デコードできない場合は元データを返す。
Uint8List sanitizeJpeg(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return bytes;
  }
  if (decoded == null) return bytes;
  decoded = img.bakeOrientation(decoded);
  final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
  if (longest > UserPhotoStore.kMaxEdge) {
    decoded = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: UserPhotoStore.kMaxEdge)
        : img.copyResize(decoded, height: UserPhotoStore.kMaxEdge);
  }
  // image パッケージは再エンコード時に元の EXIF を引き継ぐため、明示的に空にする
  decoded.exif = img.ExifData();
  return Uint8List.fromList(img.encodeJpg(decoded, quality: 85));
}
