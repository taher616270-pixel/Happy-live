import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Royal, symmetrical purple ornamental background for Happy Live.
class RoyalPurpleBackground extends StatelessWidget {
  const RoyalPurpleBackground({
    super.key,
    this.child,
  });

  final Widget? child;

  static const Color backgroundColor = Color(0xFF0B0912);
  static const Color ornamentColor = Color(0xFF8B5CF6);
  static const Color frameColor = Color(0xFFA56EFF);
  static const Color watermarkColor = Color(0xFF1A1630);

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: const BoxDecoration(color: backgroundColor),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const CustomPaint(
              painter: _RoyalOrnamentPainter(),
              isComplex: true,
              willChange: false,
            ),
            if (child != null) child!,
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: frameColor,
                      width: 1.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x998B5CF6),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Backward-compatible wrapper for existing pages using PurpleTechBackground.
class PurpleTechBackground extends StatelessWidget {
  const PurpleTechBackground({
    super.key,
    this.child,
    this.showBorder = true,
    this.showGlow = true,
  });

  final Widget? child;
  final bool showBorder;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    if (showBorder && showGlow) {
      return RoyalPurpleBackground(child: child);
    }

    return SizedBox.expand(
      child: ColoredBox(
        color: RoyalPurpleBackground.backgroundColor,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const CustomPaint(
              painter: _RoyalOrnamentPainter(),
              isComplex: true,
              willChange: false,
            ),
            if (child != null) child!,
            if (showBorder)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: RoyalPurpleBackground.frameColor,
                        width: 1.5,
                      ),
                      boxShadow: showGlow
                          ? const [
                              BoxShadow(
                                color: Color(0x998B5CF6),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoyalOrnamentPainter extends CustomPainter {
  const _RoyalOrnamentPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Very subtle dark-purple watermark ornaments along the side edges.
    final watermarkOpacity = Paint()
      ..color = RoyalPurpleBackground.watermarkColor.withOpacity(0.40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    final sideWidth = math.min(size.width * 0.20, 76.0);
    for (var i = 0; i < 9; i++) {
      final y = size.height * (i + 0.5) / 9;
      _drawSmallWatermark(
        canvas,
        Offset(sideWidth * 0.48, y),
        sideWidth * 0.34,
        watermarkOpacity,
      );
      _drawSmallWatermark(
        canvas,
        Offset(size.width - sideWidth * 0.48, y),
        sideWidth * 0.34,
        watermarkOpacity,
      );
    }

    // Seven large diamond ornaments, vertically aligned through the center.
    final diamondWidth = math.min(size.width * 0.56, size.height * 0.29);
    final diamondHeight = math.min(size.height * 0.112, size.width * 0.30);
    final centerX = size.width / 2;

    for (var i = 0; i < 7; i++) {
      final centerY = size.height * (i + 1) / 8;
      final distanceFromCenter = (i - 3).abs() / 3.0;
      final opacity = 0.65 - (0.40 * distanceFromCenter);
      _drawDiamondOrnament(
        canvas,
        Offset(centerX, centerY),
        diamondWidth,
        diamondHeight,
        opacity,
      );
    }
  }

  void _drawDiamondOrnament(
    Canvas canvas,
    Offset center,
    double width,
    double height,
    double opacity,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(width / 2, height / 2);

    final stroke = Paint()
      ..color = RoyalPurpleBackground.ornamentColor.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.010
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fineStroke = Paint()
      ..color = RoyalPurpleBackground.ornamentColor.withOpacity(opacity * 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.005
      ..strokeCap = StrokeCap.round;

    // Outer diamond and a second fine inner contour.
    final diamond = Path()
      ..moveTo(0, -1)
      ..lineTo(1, 0)
      ..lineTo(0, 1)
      ..lineTo(-1, 0)
      ..close();
    canvas.drawPath(diamond, stroke);

    final innerDiamond = Path()
      ..moveTo(0, -0.88)
      ..lineTo(0.88, 0)
      ..lineTo(0, 0.88)
      ..lineTo(-0.88, 0)
      ..close();
    canvas.drawPath(innerDiamond, fineStroke);

    // Four matching floral petals joined at the center.
    for (var quarter = 0; quarter < 4; quarter++) {
      canvas.save();
      canvas.rotate(quarter * math.pi / 2);

      final petal = Path()
        ..moveTo(0, 0.035)
        ..cubicTo(-0.10, -0.16, -0.18, -0.43, 0, -0.73)
        ..cubicTo(0.18, -0.43, 0.10, -0.16, 0, 0.035);
      canvas.drawPath(petal, stroke);

      final vein = Path()
        ..moveTo(0, -0.03)
        ..cubicTo(0.015, -0.22, 0.015, -0.43, 0, -0.67);
      canvas.drawPath(vein, fineStroke);

      // Small leaf curls on both sides of each petal.
      final leftLeaf = Path()
        ..moveTo(-0.025, -0.20)
        ..cubicTo(-0.16, -0.22, -0.20, -0.36, -0.12, -0.43)
        ..cubicTo(-0.07, -0.38, -0.045, -0.29, -0.025, -0.20);
      final rightLeaf = Path()
        ..moveTo(0.025, -0.20)
        ..cubicTo(0.16, -0.22, 0.20, -0.36, 0.12, -0.43)
        ..cubicTo(0.07, -0.38, 0.045, -0.29, 0.025, -0.20);
      canvas.drawPath(leftLeaf, fineStroke);
      canvas.drawPath(rightLeaf, fineStroke);

      // Fine connector from each petal to the next, creating one joined motif.
      final connector = Path()
        ..moveTo(-0.11, -0.11)
        ..quadraticBezierTo(0, -0.17, 0.11, -0.11);
      canvas.drawPath(connector, fineStroke);

      canvas.restore();
    }

    // Small eight-point star at the exact center.
    final star = Path();
    for (var point = 0; point < 16; point++) {
      final angle = -math.pi / 2 + point * math.pi / 8;
      final radius = point.isEven ? 0.105 : 0.047;
      final x = math.cos(angle) * radius;
      final y = math.sin(angle) * radius;
      if (point == 0) {
        star.moveTo(x, y);
      } else {
        star.lineTo(x, y);
      }
    }
    star.close();
    canvas.drawPath(star, stroke);
    canvas.drawCircle(
      Offset.zero,
      0.018,
      Paint()
        ..color = RoyalPurpleBackground.ornamentColor.withOpacity(opacity),
    );

    canvas.restore();
  }

  void _drawSmallWatermark(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(radius, radius);

    final diamond = Path()
      ..moveTo(0, -1)
      ..lineTo(0.72, 0)
      ..lineTo(0, 1)
      ..lineTo(-0.72, 0)
      ..close();
    canvas.drawPath(diamond, paint);

    for (var i = 0; i < 4; i++) {
      canvas.save();
      canvas.rotate(i * math.pi / 2);
      final leaf = Path()
        ..moveTo(0, 0)
        ..cubicTo(-0.25, -0.28, -0.18, -0.62, 0, -0.78)
        ..cubicTo(0.18, -0.62, 0.25, -0.28, 0, 0);
      canvas.drawPath(leaf, paint);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RoyalOrnamentPainter oldDelegate) => false;
}
