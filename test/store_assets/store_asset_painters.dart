// ストア素材(アイコン・フィーチャーグラフィック)を描画するペインター群。
// テスト専用(アプリ本体には含まれない)。generate_store_assets_test.dart から使用する。
import 'dart:math' as math;

import 'package:flutter/material.dart';

const Color kBgTop = Color(0xFF8B5CF6);
const Color kBgBottom = Color(0xFF5B21B6);
const Color kCapsuleTop = Color(0xFFFF7BAC);
const Color kCapsuleSeam = Color(0xFFE8578D);
const Color kCapsuleBottom = Color(0xFFFFF7FA);
const Color kPocket = Color(0xFF9D7BEA);
const Color kPocketRim = Color(0xFF8A63E0);
const Color kFace = Color(0xFF4A3B57);

void drawBackgroundGradient(Canvas canvas, Rect rect) {
  final paint = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [kBgTop, kBgBottom],
    ).createShader(rect);
  canvas.drawRect(rect, paint);
}

void _drawSparkle(Canvas canvas, Offset c, double r, Color color) {
  final path = Path()
    ..moveTo(c.dx, c.dy - r)
    ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
    ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
    ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
    ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
    ..close();
  canvas.drawPath(path, Paint()..color = color);
}

void _drawDashedPath(Canvas canvas, Path path, Paint paint,
    {double dash = 30, double gap = 24}) {
  for (final metric in path.computeMetrics()) {
    double distance = 0;
    while (distance < metric.length) {
      final end = math.min(distance + dash, metric.length);
      canvas.drawPath(metric.extractPath(distance, end), paint);
      distance = end + gap;
    }
  }
}

/// カプセル+ポケットのメインアート。1024x1024の座標系で描画する。
void drawCapsuleArt(Canvas canvas) {
  _drawSparkle(canvas, const Offset(238, 225), 54, Colors.white.withValues(alpha: 0.95));
  _drawSparkle(canvas, const Offset(806, 190), 36, Colors.white.withValues(alpha: 0.85));
  _drawSparkle(canvas, const Offset(856, 545), 26, Colors.white.withValues(alpha: 0.6));
  _drawSparkle(canvas, const Offset(158, 545), 24, Colors.white.withValues(alpha: 0.5));

  const capsuleCenter = Offset(512, 470);
  const capsuleRadius = 250.0;
  final capsuleRect = Rect.fromCircle(center: capsuleCenter, radius: capsuleRadius);

  canvas.save();
  canvas.clipPath(Path()..addOval(capsuleRect));
  canvas.drawRect(
      Rect.fromLTRB(capsuleRect.left, capsuleCenter.dy, capsuleRect.right, capsuleRect.bottom),
      Paint()..color = kCapsuleBottom);
  canvas.drawRect(
      Rect.fromLTRB(capsuleRect.left, capsuleRect.top, capsuleRect.right, capsuleCenter.dy),
      Paint()..color = kCapsuleTop);
  canvas.drawRect(
      Rect.fromLTRB(capsuleRect.left, capsuleCenter.dy - 9, capsuleRect.right, capsuleCenter.dy + 9),
      Paint()..color = kCapsuleSeam);
  canvas.restore();

  // ハイライト
  canvas.save();
  canvas.translate(415, 330);
  canvas.rotate(-0.6);
  canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 96, height: 44),
      Paint()..color = Colors.white.withValues(alpha: 0.9));
  canvas.restore();

  // 顔
  final eye = Paint()..color = kFace;
  canvas.drawCircle(const Offset(455, 412), 15, eye);
  canvas.drawCircle(const Offset(569, 412), 15, eye);
  final smile = Paint()
    ..color = kFace
    ..style = PaintingStyle.stroke
    ..strokeWidth = 10
    ..strokeCap = StrokeCap.round;
  canvas.drawArc(Rect.fromCenter(center: const Offset(512, 424), width: 64, height: 48),
      0.35, math.pi - 0.7, false, smile);
  final blush = Paint()..color = const Color(0xFFFF4E8C).withValues(alpha: 0.5);
  canvas.drawCircle(const Offset(423, 444), 17, blush);
  canvas.drawCircle(const Offset(601, 444), 17, blush);

  // ポケット(カプセルの下半分に被せる)
  final pocketRect = RRect.fromRectAndCorners(
    const Rect.fromLTRB(190, 590, 834, 910),
    topLeft: const Radius.circular(56),
    topRight: const Radius.circular(56),
    bottomLeft: const Radius.circular(120),
    bottomRight: const Radius.circular(120),
  );
  canvas.drawRRect(pocketRect, Paint()..color = kPocket);
  canvas.save();
  canvas.clipRRect(pocketRect);
  canvas.drawRect(const Rect.fromLTRB(190, 590, 834, 648), Paint()..color = kPocketRim);
  canvas.restore();

  // ステッチ(破線)
  final stitchPath = Path()
    ..addRRect(RRect.fromRectAndCorners(
      const Rect.fromLTRB(222, 622, 802, 878),
      topLeft: const Radius.circular(36),
      topRight: const Radius.circular(36),
      bottomLeft: const Radius.circular(96),
      bottomRight: const Radius.circular(96),
    ));
  _drawDashedPath(
      canvas,
      stitchPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round);
}

/// アプリアイコン。drawBackground=falseでadaptiveアイコンの前景(透過)になる。
class AppIconPainter extends CustomPainter {
  final bool drawBackground;
  final double artScale;
  const AppIconPainter({required this.drawBackground, this.artScale = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 1024.0;
    canvas.scale(s);
    if (drawBackground) {
      drawBackgroundGradient(canvas, const Rect.fromLTWH(0, 0, 1024, 1024));
    }
    canvas.translate(512, 512);
    canvas.scale(artScale);
    canvas.translate(-512, -512);
    drawCapsuleArt(canvas);
  }

  @override
  bool shouldRepaint(covariant AppIconPainter oldDelegate) =>
      oldDelegate.drawBackground != drawBackground || oldDelegate.artScale != artScale;
}

/// adaptiveアイコンの背景(グラデーションのみ)。
class AdaptiveBackgroundPainter extends CustomPainter {
  const AdaptiveBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    drawBackgroundGradient(canvas, Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// フィーチャーグラフィック(1024x500)。
class FeatureGraphicPainter extends CustomPainter {
  final String fontFamily;
  const FeatureGraphicPainter({required this.fontFamily});

  void _drawText(Canvas canvas, String text, Offset offset,
      {required double fontSize,
      required FontWeight weight,
      required Color color,
      double maxWidth = 560,
      double height = 1.2}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          fontWeight: weight,
          color: color,
          height: height,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  @override
  void paint(Canvas canvas, Size size) {
    drawBackgroundGradient(canvas, Offset.zero & size);
    canvas.drawCircle(const Offset(950, -30), 260, Paint()..color = Colors.white.withValues(alpha: 0.05));
    canvas.drawCircle(const Offset(40, 520), 190, Paint()..color = Colors.white.withValues(alpha: 0.05));
    _drawSparkle(canvas, const Offset(500, 60), 18, Colors.white.withValues(alpha: 0.7));
    _drawSparkle(canvas, const Offset(960, 400), 22, Colors.white.withValues(alpha: 0.6));

    // 左側にカプセルアート
    canvas.save();
    canvas.translate(225, 260);
    canvas.scale(0.42);
    canvas.translate(-512, -512);
    drawCapsuleArt(canvas);
    canvas.restore();

    _drawText(canvas, 'ガチャ活ポケット', const Offset(452, 96),
        fontSize: 68, weight: FontWeight.w800, color: Colors.white);
    _drawText(
        canvas,
        'カプセルトイの新作チェック&\nコレクション・支出をまるごと管理',
        const Offset(456, 210),
        fontSize: 33,
        weight: FontWeight.w700,
        color: Colors.white.withValues(alpha: 0.95),
        height: 1.4);

    // ハッシュタグピル
    const pillRect = Rect.fromLTWH(456, 340, 210, 58);
    final pill = RRect.fromRectAndRadius(pillRect, const Radius.circular(29));
    canvas.drawRRect(
        pill,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    _drawText(canvas, '#ガチャ活', const Offset(486, 350),
        fontSize: 28, weight: FontWeight.w700, color: Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
