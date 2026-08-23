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
