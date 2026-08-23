import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';

Future<void> showCompletionCelebration(
    BuildContext context, GachaSeries series) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'コンプリート',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 500),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _CelebrationDialog(seriesName: series.name);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.elasticOut);
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: curved, child: child),
      );
    },
  );
}

class _CelebrationDialog extends StatefulWidget {
  final String seriesName;
  const _CelebrationDialog({required this.seriesName});

  @override
  State<_CelebrationDialog> createState() => _CelebrationDialogState();
}

class _CelebrationDialogState extends State<_CelebrationDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.deepPurple[400]!, Colors.deepPurple[700]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        for (int i = 0; i < 8; i++)
                          Transform.translate(
                            offset: Offset(
                              math.cos(i * math.pi / 4 +
                                      _controller.value * 2 * math.pi) *
                                  58,
                              math.sin(i * math.pi / 4 +
                                      _controller.value * 2 * math.pi) *
                                  58,
                            ),
                            child: Icon(
                              Icons.star,
                              size: 16 +
                                  6 *
                                      math.sin(
                                          _controller.value * 2 * math.pi + i),
                              color: Colors.amberAccent,
                            ),
                          ),
                        const Icon(Icons.emoji_events,
                            size: 80,
                            color: Colors.amber,
                            shadows: [
                              Shadow(color: Colors.black38, blurRadius: 12)
                            ]),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              const Text('シリーズコンプリート！',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 8),
              Text(widget.seriesName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: Colors.white70)),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black87),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('やったー！'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
