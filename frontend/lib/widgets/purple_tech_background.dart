import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Reusable black-and-purple technology background for Happy Live pages.
///
/// Example:
/// Scaffold(
///   body: PurpleTechBackground(
///     child: SafeArea(child: YourPageContent()),
///   ),
/// )
class PurpleTechBackground extends StatelessWidget {
  const PurpleTechBackground({
    super.key,
    this.child,
    this.showBorder = false,
    this.showGlow = false,
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
            ? Border.all(color: primaryPurple, width: 2)
            : null,
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: primaryPurple.withOpacity(0.35),
                  blurRadius: 20,
                  spreadRadius: 2,
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
      ..color = PurpleTechBackground.primaryPurple.withOpacity(0.105)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final nodePaint = Paint()
      ..color = PurpleTechBackground.lightPurple.withOpacity(0.22)
      ..style = PaintingStyle.fill;

    const spacingX = 54.0;
    const spacingY = 48.0;

    for (double y = 12; y < size.height + spacingY; y += spacingY) {
      for (double x = 10; x < size.width + spacingX; x += spacingX) {
        final path = Path()
          ..moveTo(x, y)
          ..lineTo(x + 15, y)
          ..lineTo(x + 15, y + 12)
          ..lineTo(x + 34, y + 12);

        canvas.drawPath(path, linePaint);
        canvas.drawCircle(Offset(x + 34, y + 12), 1.6, nodePaint);

        if ((x / spacingX).floor().isEven) {
          final branch = Path()
            ..moveTo(x + 15, y + 12)
            ..lineTo(x + 15, y + 25);
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

    for (var i = 0; i < 42; i++) {
      final center = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final radius = 1.5 + random.nextDouble() * 4.5;
      final opacity = 0.08 + random.nextDouble() * 0.22;

      final paint = Paint()
        ..color = PurpleTechBackground.lightPurple.withOpacity(opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PurpleBokehPainter oldDelegate) => false;
}
