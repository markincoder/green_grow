import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Brand marks for Telegram / VK / Max (simple path icons).
enum SocialBrand { telegram, vk, max }

class SocialBrandIcon extends StatelessWidget {
  const SocialBrandIcon({
    super.key,
    required this.brand,
    this.size = 22,
    this.color,
  });

  final SocialBrand brand;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SocialBrandPainter(
          brand: brand,
          color: color ?? IconTheme.of(context).color ?? Colors.black,
        ),
      ),
    );
  }
}

class _SocialBrandPainter extends CustomPainter {
  _SocialBrandPainter({required this.brand, required this.color});

  final SocialBrand brand;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Paths are authored in a 24×24 design space; fit + center in [size].
    final path = switch (brand) {
      SocialBrand.telegram => _telegram(),
      SocialBrand.vk => _vk(),
      SocialBrand.max => _max(),
    };

    // VK letters sit in a small box — fill more of the green tile.
    // Telegram plane is optically off-center in 24×24 — crop to glyph bounds.
    final Rect design = switch (brand) {
      SocialBrand.vk => path.getBounds().inflate(0.4),
      SocialBrand.telegram => path.getBounds().inflate(0.6),
      SocialBrand.max => const Rect.fromLTWH(0, 0, 24, 24),
    };

    final fill = switch (brand) {
      SocialBrand.vk => 0.92,
      SocialBrand.telegram => 0.82,
      SocialBrand.max => 0.82,
    };

    final sx = (size.width * fill) / design.width;
    final sy = (size.height * fill) / design.height;
    final scale = math.min(sx, sy);

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(
      -(design.left + design.width / 2),
      -(design.top + design.height / 2),
    );
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  Path _telegram() {
    return Path()
      ..moveTo(21.8, 4.4)
      ..cubicTo(22.1, 4.3, 22.4, 4.5, 22.4, 4.9)
      ..lineTo(20.3, 19.4)
      ..cubicTo(20.2, 20.1, 19.7, 20.4, 19.1, 20.1)
      ..lineTo(14.6, 16.8)
      ..lineTo(12.1, 19.2)
      ..cubicTo(11.8, 19.5, 11.4, 19.6, 11.0, 19.4)
      ..lineTo(11.4, 14.6)
      ..lineTo(20.1, 6.7)
      ..cubicTo(20.4, 6.4, 20.1, 6.0, 19.7, 6.3)
      ..lineTo(8.9, 13.1)
      ..lineTo(4.5, 11.7)
      ..cubicTo(3.7, 11.5, 3.7, 10.5, 4.6, 10.2)
      ..lineTo(21.8, 4.4)
      ..close();
  }

  Path _vk() {
    return Path()
      ..moveTo(12.8, 17.5)
      ..lineTo(11.3, 17.5)
      ..cubicTo(7.2, 17.5, 4.8, 14.7, 4.7, 10.0)
      ..lineTo(6.7, 10.0)
      ..cubicTo(6.8, 13.4, 7.8, 14.9, 9.2, 15.1)
      ..lineTo(9.2, 10.0)
      ..lineTo(11.3, 10.0)
      ..lineTo(11.3, 12.9)
      ..cubicTo(12.7, 12.7, 14.1, 11.2, 14.6, 10.0)
      ..lineTo(16.7, 10.0)
      ..cubicTo(16.3, 11.6, 15.0, 13.1, 14.0, 13.7)
      ..cubicTo(15.0, 14.2, 16.5, 15.5, 17.1, 17.5)
      ..lineTo(14.9, 17.5)
      ..cubicTo(14.4, 16.1, 13.3, 15.0, 11.8, 14.8)
      ..lineTo(11.8, 17.5)
      ..lineTo(12.8, 17.5)
      ..close();
  }

  Path _max() {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(12, 2.2)
      ..cubicTo(6.7, 2.2, 2.4, 6.2, 2.4, 11.2)
      ..cubicTo(2.4, 14.3, 4.1, 17.0, 6.7, 18.6)
      ..lineTo(5.2, 22)
      ..lineTo(9.7, 20.1)
      ..cubicTo(10.4, 20.3, 11.2, 20.4, 12, 20.4)
      ..cubicTo(17.3, 20.4, 21.6, 16.4, 21.6, 11.2)
      ..cubicTo(21.6, 6.0, 17.3, 2.2, 12, 2.2)
      ..close()
      ..moveTo(12, 4.8)
      ..cubicTo(15.9, 4.8, 19, 7.7, 19, 11.2)
      ..cubicTo(19, 14.7, 15.9, 17.6, 12, 17.6)
      ..cubicTo(11.2, 17.6, 10.4, 17.5, 9.7, 17.3)
      ..lineTo(7.2, 18.4)
      ..lineTo(7.7, 16.3)
      ..cubicTo(6.1, 14.9, 5, 13.2, 5, 11.2)
      ..cubicTo(5, 7.7, 8.1, 4.8, 12, 4.8)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _SocialBrandPainter oldDelegate) =>
      oldDelegate.brand != brand || oldDelegate.color != color;
}
