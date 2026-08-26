import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Star drawn with CustomPaint so it stays visible even if MaterialIcons fail.
class FavoriteStar extends StatelessWidget {
  const FavoriteStar({
    super.key,
    required this.filled,
    this.size = 24,
    this.color,
  });

  final bool filled;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? (filled ? AppColors.sun : AppColors.leaf);
    final star = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _StarPainter(filled: filled, color: resolved),
      ),
    );
    if (!filled) return star;

    final box = size + 10;
    return Container(
      width: box,
      height: box,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(box * 0.28),
        border: Border.all(
          color: AppColors.leaf.withValues(alpha: 0.5),
          width: 1.25,
        ),
      ),
      child: star,
    );
  }
}

class _StarPainter extends CustomPainter {
  const _StarPainter({required this.filled, required this.color});

  final bool filled;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outer = size.shortestSide * 0.48;
    final inner = outer * 0.45;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final x = cx + r * math.cos(a);
      final y = cy + r * math.sin(a);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    if (filled) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill
          ..isAntiAlias = true,
      );
    } else {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.shortestSide * 0.1
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) =>
      oldDelegate.filled != filled || oldDelegate.color != color;
}
