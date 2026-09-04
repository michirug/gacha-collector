import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'models.dart';

Widget buildSeriesShareCard(
    {required GachaSeries series, required int collected, required int total}) {
  final isComplete = total > 0 && collected == total;
  return _ShareCardFrame(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(isComplete ? Icons.emoji_events : Icons.catching_pokemon,
            size: 64, color: Colors.amber),
        const SizedBox(height: 12),
        Text(isComplete ? 'コンプリート！' : 'コレクション進行中',
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 12),
        Text(series.name,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, color: Colors.white)),
        const SizedBox(height: 16),
        Text('獲得 $collected / $total',
            style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.amberAccent)),
      ],
    ),
  );
}

Widget buildSummaryShareCard(
    {required int totalItems,
    required int completedSeries,
    required int unlockedAchievements,
    required int totalAchievements}) {
  return _ShareCardFrame(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.auto_awesome, size: 56, color: Colors.amber),
        const SizedBox(height: 12),
        const Text('マイコレクション',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 20),
        _statRow('獲得アイテム', '$totalItems個'),
        _statRow('コンプシリーズ', '$completedSeries個'),
        _statRow('実績', '$unlockedAchievements / $totalAchievements'),
      ],
    ),
  );
}

// 譲/求カード。X上の #ガチャ活 交換投稿の定型(譲: ダブり / 求: 未獲得)を画像化する
Widget buildTradeShareCard({
  required GachaSeries series,
  required List<GachaItem> give,
  required List<GachaItem> want,
  required Map<String, int> counts,
}) {
  return _ShareCardFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(Icons.swap_horiz_rounded, size: 28, color: Colors.amber),
            SizedBox(width: 8),
            Text('交換希望',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        const SizedBox(height: 6),
        Text(series.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Colors.white70)),
        const SizedBox(height: 14),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _tradeColumn(
                  '譲',
                  const Color(0xFFFF7BAC),
                  give.map((i) {
                    final n = counts[i.id] ?? 1;
                    return n > 1 ? '${i.name} ×$n' : i.name;
                  }).toList(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _tradeColumn(
                    '求', const Color(0xFF7DD3FC), want.map((i) => i.name).toList()),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _tradeColumn(String label, Color color, List<String> names) {
  const maxLines = 6;
  final shown = names.take(maxLines).toList();
  final rest = names.length - shown.length;
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(6)),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
        ),
        const SizedBox(height: 8),
        if (names.isEmpty)
          const Text('なし', style: TextStyle(fontSize: 12, color: Colors.white54)),
        for (final name in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text('・$name',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white, height: 1.25)),
          ),
        if (rest > 0)
          Text('他$rest件', style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ],
    ),
  );
}

Widget _statRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 14, color: Colors.white70)),
          Text(value,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ],
      ),
    );

class _ShareCardFrame extends StatelessWidget {
  final Widget child;
  const _ShareCardFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      height: 400,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple[400]!, Colors.deepPurple[800]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Expanded(child: child),
          const Text('#ガチャ活ポケット',
              style: TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
    );
  }
}

Future<void> showShareCardDialog(BuildContext context, Widget card,
    String fileName, String shareText) async {
  final boundaryKey = GlobalKey();
  await showDialog(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(key: boundaryKey, child: card),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child:
                      const Text('閉じる', style: TextStyle(color: Colors.white)),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('シェア'),
                  onPressed: () => _captureAndShare(
                      dialogContext, boundaryKey, fileName, shareText),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

Future<void> _captureAndShare(BuildContext context, GlobalKey boundaryKey,
    String fileName, String shareText) async {
  final messenger = ScaffoldMessenger.of(context);
  if (kIsWeb) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Web版ではシェア機能は利用できません')));
    return;
  }
  try {
    final boundary = boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    await Share.shareXFiles([XFile(file.path)], text: shareText);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('シェアに失敗しました: $e')));
  }
}
