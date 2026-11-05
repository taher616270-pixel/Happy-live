import 'dart:math';
import 'package:flutter/material.dart';

/// Neon purple technology background for Happy Live.
/// The background is drawn locally and does not use images, animation, or network requests.
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

  static const Color backgroundColor = Color(0xFF0A0714);
  static const Color neonPurple = Color(0xFFA56EFF);
  static const Color primaryPurple = Color(0xFF8B5CF6);

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;

    // Keep the frame proportional on small and large phones/tablets.
    final framePadding = (shortestSide * 0.025).clamp(7.0, 12.0).toDouble();
    final frameWidth = (shortestSide * 0.0045).clamp(1.1, 1.8).toDouble();

    return ColoredBox(
      color: backgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(
            child: CustomPaint(
              painter: _NeonBgPainter(),
            ),
          ),
          if (child != null) child!,
          if (showBorder)
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.all(framePadding),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: neonPurple,
                        width: frameWidth,
                      ),
                      boxShadow: showGlow
                          ? [
                              BoxShadow(
                                color: primaryPurple.withOpacity(0.8),
                                blurRadius: 15,
                                spreadRadius: 1,
                              ),
                              BoxShadow(
                                color: neonPurple.withOpacity(0.4),
                                blurRadius: 30,
                                spreadRadius: 2,
                              ),
                            ]
                          : const [],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NeonBgPainter extends CustomPainter {
  const _NeonBgPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final random = Random(42);

    // Base background.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = PurpleTechBackground.backgroundColor,
    );

    // Subtle technology lines.
    final linePaint = Paint()
      ..color = const Color(0xFF2A1F4A).withOpacity(0.15)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < 15; i++) {
      final x = random.nextDouble() * size.width;
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(
          x + random.nextDouble() * 30 - 15,
          size.height * 0.7,
        )
        ..lineTo(
          x + random.nextDouble() * 40 - 20,
          size.height * 0.4,
        );
      canvas.drawPath(path, linePaint);
    }

    // Purple glowing particles.
    for (var i = 0; i < 45; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final radius = random.nextDouble() * 8 + 1;
      final opacity = random.nextDouble() * 0.6 + 0.1;

      final particlePaint = Paint()
        ..color = Color.lerp(
          const Color(0xFF8B5CF6),
          const Color(0xFFD8B4FE),
          random.nextDouble(),
        )!.withOpacity(opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius);

      canvas.drawCircle(Offset(x, y), radius, particlePaint);

      // Small white center for the brighter particles.
      if (radius > 4) {
        canvas.drawCircle(
          Offset(x, y),
          1.5,
          Paint()..color = Colors.white.withOpacity(opacity),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NeonBgPainter oldDelegate) => false;
}
