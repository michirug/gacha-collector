import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

// ユーザーが撮った写真を端末内(アプリ専用領域/photos)に保存する。
// CollectionEntry.photoPath にはファイル名だけを持ち、表示時にディレクトリと結合する。
class UserPhotoStore {
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
      imageQuality: 85,
    );
    if (picked == null) return null;
    final fileName = '${_safeName(itemId)}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final target = await fileFor(fileName);
    await File(picked.path).copy(target.path);
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
