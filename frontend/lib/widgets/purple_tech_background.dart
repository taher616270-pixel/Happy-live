import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Dark electronic background with a restrained purple neon frame.
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

  static const Color backgroundColor = Color(0xFF0B0912);
  static const Color primaryPurple = Color(0xFF8B5CF6);
  static const Color lightPurple = Color(0xFFB58AFF);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: showBorder
            ? Border.all(color: primaryPurple.withOpacity(0.78), width: 1.5)
            : null,
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: primaryPurple.withOpacity(0.22),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(
            painter: _CircuitPatternPainter(),
            isComplex: true,
          ),
          const CustomPaint(
            painter: _PurpleBokehPainter(),
            isComplex: true,
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}

class _CircuitPatternPainter extends CustomPainter {
  const _CircuitPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = PurpleTechBackground.primaryPurple.withOpacity(0.065)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final nodePaint = Paint()
      ..color = PurpleTechBackground.lightPurple.withOpacity(0.13)
      ..style = PaintingStyle.fill;

    const spacingX = 58.0;
    const spacingY = 52.0;

    for (double y = 14; y < size.height + spacingY; y += spacingY) {
      for (double x = 12; x < size.width + spacingX; x += spacingX) {
        final path = Path()
          ..moveTo(x, y)
          ..lineTo(x + 14, y)
          ..lineTo(x + 14, y + 11)
          ..lineTo(x + 32, y + 11);
        canvas.drawPath(path, linePaint);
        canvas.drawCircle(Offset(x + 32, y + 11), 1.35, nodePaint);

        if ((x / spacingX).floor().isEven) {
          final branch = Path()
            ..moveTo(x + 14, y + 11)
            ..lineTo(x + 14, y + 23);
          canvas.drawPath(branch, linePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CircuitPatternPainter oldDelegate) => false;
}

class _PurpleBokehPainter extends CustomPainter {
  const _PurpleBokehPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(25);
    for (var i = 0; i < 28; i++) {
      final center = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final radius = 1.2 + random.nextDouble() * 2.8;
      final paint = Paint()
        ..color = PurpleTechBackground.lightPurple.withOpacity(0.09)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PurpleBokehPainter oldDelegate) => false;
}
