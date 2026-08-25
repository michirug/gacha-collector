// ストア素材(アイコン・フィーチャーグラフィック)PNGを生成するテスト。
// 通常のテスト実行ではスキップされる。生成するには:
//   flutter test test/store_assets --dart-define=GENERATE_ASSETS=true --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'store_asset_painters.dart';

const bool kGenerate = bool.fromEnvironment('GENERATE_ASSETS');

Future<void> _pumpAsset(
    WidgetTester tester, Size sizePx, CustomPainter painter, Key key) async {
  tester.view.physicalSize = sizePx;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: sizePx.width,
            height: sizePx.height,
            child: CustomPaint(painter: painter),
          ),
        ),
      ),
    ),
  );
}

Future<void> _loadFont() async {
  final bytes = await File('store/assets/fonts/MPLUSRounded1c-Bold.ttf').readAsBytes();
  final loader = FontLoader('MPlusRounded1c')
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

void main() {
  testWidgets('generate icon master 1024', skip: !kGenerate, (tester) async {
    const key = ValueKey('icon_master');
    await _pumpAsset(tester, const Size(1024, 1024),
        const AppIconPainter(drawBackground: true), key);
    await expectLater(
        find.byKey(key), matchesGoldenFile('../../store/assets/icon_master_1024.png'));
  });

  testWidgets('generate store icon 512', skip: !kGenerate, (tester) async {
    const key = ValueKey('icon_512');
    await _pumpAsset(tester, const Size(512, 512),
        const AppIconPainter(drawBackground: true), key);
    await expectLater(
        find.byKey(key), matchesGoldenFile('../../store/assets/icon_512.png'));
  });

  testWidgets('generate adaptive foreground 1024', skip: !kGenerate, (tester) async {
    const key = ValueKey('icon_fg');
    await _pumpAsset(tester, const Size(1024, 1024),
        const AppIconPainter(drawBackground: false, artScale: 0.62), key);
    await expectLater(find.byKey(key),
        matchesGoldenFile('../../store/assets/icon_adaptive_fg_1024.png'));
  });

  testWidgets('generate adaptive background 1024', skip: !kGenerate, (tester) async {
    const key = ValueKey('icon_bg');
    await _pumpAsset(
        tester, const Size(1024, 1024), const AdaptiveBackgroundPainter(), key);
    await expectLater(find.byKey(key),
        matchesGoldenFile('../../store/assets/icon_adaptive_bg_1024.png'));
  });

  testWidgets('generate feature graphic 1024x500', skip: !kGenerate, (tester) async {
    await tester.runAsync(_loadFont);
    const key = ValueKey('feature');
    await _pumpAsset(tester, const Size(1024, 500),
        const FeatureGraphicPainter(fontFamily: 'MPlusRounded1c'), key);
    await expectLater(find.byKey(key),
        matchesGoldenFile('../../store/assets/feature_graphic_1024x500.png'));
  });
}
