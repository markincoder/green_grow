import 'package:flutter/material.dart';

import '../models/plant.dart';
import '../theme/app_theme.dart';

enum StageGlyphKind { soak, germinate, grow, dueToday }

StageGlyphKind stageGlyphKind(GrowthStage stage) => switch (stage) {
      GrowthStage.soak => StageGlyphKind.soak,
      GrowthStage.germinate => StageGlyphKind.germinate,
      GrowthStage.grow || GrowthStage.harvest => StageGlyphKind.grow,
    };

StageGlyphKind reminderGlyphKind(DueActionKind? kind) => switch (kind) {
      DueActionKind.sow => StageGlyphKind.soak,
      DueActionKind.toLight => StageGlyphKind.germinate,
      DueActionKind.harvest ||
      DueActionKind.water ||
      null =>
        StageGlyphKind.grow,
    };

class StageGlyph extends StatelessWidget {
  const StageGlyph({
    super.key,
    required this.kind,
    this.size = 22,
    this.color,
  });

  final StageGlyphKind kind;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ??
        IconTheme.of(context).color ??
        AppColors.forest;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _StageGlyphPainter(kind: kind, color: resolved),
      ),
    );
  }
}

/// Harvest basket for «Выращено».
class HarvestGlyph extends StatelessWidget {
  const HarvestGlyph({
    super.key,
    this.size = 26,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Transform.scale(
          scale: 1.42,
          child: Image.asset(
            'assets/harvest_basket.png',
            width: size,
            height: size,
            filterQuality: FilterQuality.medium,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

class _StageGlyphPainter extends CustomPainter {
  const _StageGlyphPainter({required this.kind, required this.color});

  final StageGlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.scale(s / 24, s / 24);
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    switch (kind) {
      case StageGlyphKind.soak:
        _paintDrop(canvas, fill);
      case StageGlyphKind.germinate:
        _paintSeed(canvas, fill);
      case StageGlyphKind.grow:
        _paintSprout(canvas, fill);
      case StageGlyphKind.dueToday:
        _paintBell(canvas, fill);
    }
    canvas.restore();
  }

  void _paintDrop(Canvas canvas, Paint fill) {
    final path = Path()
      ..moveTo(12, 2.6)
      ..cubicTo(12, 2.6, 4.6, 11.4, 4.6, 16.1)
      ..cubicTo(4.6, 20.5, 7.9, 23.4, 12, 23.4)
      ..cubicTo(16.1, 23.4, 19.4, 20.5, 19.4, 16.1)
      ..cubicTo(19.4, 11.4, 12, 2.6, 12, 2.6)
      ..close();
    canvas.drawPath(path, fill);
  }

  void _paintSeed(Canvas canvas, Paint fill) {
    canvas.save();
    canvas.translate(10.4, 8.8);
    canvas.rotate(-0.42);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 12.2, height: 8.4),
      fill,
    );
    canvas.restore();

    final tail = Path()
      ..moveTo(14.2, 12.4)
      ..cubicTo(19.6, 15.2, 20.2, 20.4, 15.0, 22.6)
      ..cubicTo(14.2, 23.0, 13.6, 21.8, 14.4, 21.4)
      ..cubicTo(18.0, 19.6, 17.2, 16.2, 13.2, 13.8)
      ..close();
    canvas.drawPath(tail, fill);
  }

  void _paintSprout(Canvas canvas, Paint fill) {
    final stem = Paint()
      ..color = fill.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawLine(const Offset(12, 21.8), const Offset(12, 11.2), stem);

    canvas.save();
    canvas.translate(7.8, 8.6);
    canvas.rotate(-0.72);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 8.6, height: 5.1),
      fill,
    );
    canvas.restore();

    canvas.save();
    canvas.translate(16.2, 8.6);
    canvas.rotate(0.72);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 8.6, height: 5.1),
      fill,
    );
    canvas.restore();
  }

  void _paintBell(Canvas canvas, Paint fill) {
    final body = Path()
      ..moveTo(6.0, 10.0)
      ..cubicTo(6.0, 6.0, 8.6, 3.2, 12, 3.2)
      ..cubicTo(15.4, 3.2, 18.0, 6.0, 18.0, 10.0)
      ..lineTo(19.6, 17.6)
      ..lineTo(4.4, 17.6)
      ..close();
    canvas.drawPath(body, fill);
    canvas.drawRRect(
      RRect.fromLTRBR(4.0, 16.8, 20.0, 19.2, const Radius.circular(1.6)),
      fill,
    );
    canvas.drawCircle(const Offset(12, 21.5), 1.55, fill);
    canvas.drawRRect(
      RRect.fromLTRBR(10.6, 1.8, 13.4, 4.0, const Radius.circular(1.2)),
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _StageGlyphPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
