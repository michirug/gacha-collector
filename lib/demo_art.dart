import 'package:flutter/material.dart';

// DEMO_MODE(ストアスクリーンショット撮影)専用の見本イラスト。
// ストア掲載画像にメーカーの公式画像を含めないため、公式画像の代わりに
// シード(画像URL)ごとに配色の変わるカプセルを自前で描画する。
class DemoCapsuleArt extends StatelessWidget {
  final String seed;
  const DemoCapsuleArt(this.seed, {super.key});

  static const List<List<Color>> _palettes = [
    [Color(0xFFFF7BAC), Color(0xFFFFE3EE)],
    [Color(0xFF7C4DFF), Color(0xFFE9E0FF)],
    [Color(0xFF4FC3F7), Color(0xFFE1F5FE)],
    [Color(0xFFFFB74D), Color(0xFFFFF3E0)],
    [Color(0xFF81C784), Color(0xFFE8F5E9)],
    [Color(0xFFFFD54F), Color(0xFFFFFDE7)],
    [Color(0xFFF06292), Color(0xFFFCE4EC)],
    [Color(0xFF9575CD), Color(0xFFEDE7F6)],
    [Color(0xFF4DB6AC), Color(0xFFE0F2F1)],
    [Color(0xFFA1887F), Color(0xFFEFEBE9)],
  ];

  @override
  Widget build(BuildContext context) {
    final hash = seed.hashCode.abs();
    final palette = _palettes[hash % _palettes.length];
    final accent = _palettes[(hash ~/ 7) % _palettes.length][0];
    return CustomPaint(
      painter: _CapsulePainter(palette[0], palette[1], accent, hash),
      child: const SizedBox.expand(),
    );
  }
}

class _CapsulePainter extends CustomPainter {
  final Color top;
  final Color bg;
  final Color accent;
  final int hash;
  _CapsulePainter(this.top, this.bg, this.accent, this.hash);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = bg);

    // 背景の水玉
    final dot = Paint()..color = accent.withValues(alpha: 0.18);
    final step = size.shortestSide / 4;
    for (var x = step / 2 + (hash % 7); x < size.width; x += step) {
      for (var y = step / 2 + (hash % 5); y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), step * 0.12, dot);
      }
    }

    // カプセル本体(上半分: 色、下半分: 半透明の白)
    final r = size.shortestSide * 0.30;
    final c = Offset(size.width / 2, size.height / 2);
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(c + Offset(0, r * 0.15), r, shadow);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), 3.1416, 3.1416, true,
        Paint()..color = top);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), 0, 3.1416, true,
        Paint()..color = Colors.white.withValues(alpha: 0.92));
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy),
        Paint()
          ..color = top.withValues(alpha: 0.5)
          ..strokeWidth = r * 0.06);
    // ハイライト
    canvas.drawCircle(c + Offset(-r * 0.4, -r * 0.45), r * 0.14,
        Paint()..color = Colors.white.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(covariant _CapsulePainter old) =>
      old.top != top || old.bg != bg || old.accent != accent || old.hash != hash;
}
