import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// release ビルドでは Flutter が debug/profile 用に足す INTERNET 権限が付かない。
// main の Manifest から抜けると商品データも画像も一切取得できないアプリになる(2026-09-27 に発見)。
void main() {
  test('main AndroidManifest declares the permissions release builds need', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    for (final permission in const [
      'android.permission.INTERNET',
      'android.permission.POST_NOTIFICATIONS',
      'android.permission.RECEIVE_BOOT_COMPLETED',
    ]) {
      expect(manifest, contains('<uses-permission android:name="$permission"/>'), reason: permission);
    }
  });
}
