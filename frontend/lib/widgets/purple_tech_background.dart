import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Static premium background for Happy Live's social and audio experience.
/// It is drawn locally with Canvas: no image downloads, animation, or network work.
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

  static const Color backgroundColor = Color(0xFF09070F);
  static const Color primaryPurple = Color(0xFF8B5CF6);
  static const Color lightPurple = Color(0xFFB58AFF);
  static const Color softGold = Color(0xFFE8C477);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF100B1B),
            Color(0xFF09070F),
            Color(0xFF0D0915),
          ],
          stops: [0, 0.52, 1],
        ),
        border: showBorder
            ? Border.all(
                color: primaryPurple.withOpacity(0.62),
                width: 1.2,
              )
            : null,
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: primaryPurple.withOpacity(0.14),
                  blurRadius: 20,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(
            child: CustomPaint(
              painter: _HappyLiveAudioAtmospherePainter(),
            ),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}

/// Restrained sound-wave contours and soft light, kept behind all UI content.
class _HappyLiveAudioAtmospherePainter extends CustomPainter {
  const _HappyLiveAudioAtmospherePainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final width = size.width;
    final height = size.height;

    // Soft ambient light in opposite corners.
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          PurpleTechBackground.primaryPurple.withOpacity(0.15),
          PurpleTechBackground.primaryPurple.withOpacity(0.045),
          Colors.transparent,
        ],
        stops: const [0, 0.48, 1],
      ).createShader(
        Rect.fromCircle(
          center: Offset(width * 0.04, height * 0.16),
          radius: math.max(width, height) * 0.62,
        ),
      );
    canvas.drawRect(Offset.zero & size, glowPaint);

    final lowerGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF6540A8).withOpacity(0.12),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(width * 0.98, height * 0.88),
          radius: math.max(width, height) * 0.48,
        ),
      );
    canvas.drawRect(Offset.zero & size, lowerGlow);

    _drawSideSoundRings(canvas, size);
    _drawSoftWaveLines(canvas, size);
    _drawTinyLightPoints(canvas, size);
  }

  void _drawSideSoundRings(Canvas canvas, Size size) {
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = PurpleTechBackground.lightPurple.withOpacity(0.075);

    final faintRingPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = PurpleTechBackground.primaryPurple.withOpacity(0.045);

    // Rings intentionally sit mostly outside the content area.
    final centers = [
      Offset(size.width * 1.015, size.height * 0.27),
      Offset(size.width * -0.015, size.height * 0.79),
    ];

    for (var side = 0; side < centers.length; side++) {
      final center = centers[side];
      for (var i = 0; i < 6; i++) {
        final radius = 62.0 + i * 25.0;
        final rect = Rect.fromCircle(center: center, radius: radius);
        canvas.drawArc(
          rect,
          side == 0 ? math.pi * 0.48 : -math.pi * 0.48,
          math.pi * 1.04,
          false,
          i.isEven ? ringPaint : faintRingPaint,
        );
      }
    }
  }

  void _drawSoftWaveLines(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05
      ..strokeCap = StrokeCap.round
      ..color = PurpleTechBackground.primaryPurple.withOpacity(0.055);

    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round
      ..color = PurpleTechBackground.softGold.withOpacity(0.025);

    for (var row = 0; row < 3; row++) {
      final baseY = size.height * (0.19 + row * 0.31);
      final path = Path();
      for (var step = 0; step <= 100; step++) {
        final x = size.width * step / 100;
        final envelope = math.sin(math.pi * step / 100);
        final wave = math.sin((step / 100 * math.pi * 5) + row * 0.9);
        final y = baseY + wave * (5 + row * 1.4) * envelope;
        if (step == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);

      if (row == 1) {
        final secondary = Path();
        for (var step = 0; step <= 100; step++) {
          final x = size.width * step / 100;
          final envelope = math.sin(math.pi * step / 100);
          final wave = math.sin((step / 100 * math.pi * 5) + 1.15);
          final y = baseY + wave * 10 * envelope + 8;
          if (step == 0) {
            secondary.moveTo(x, y);
          } else {
            secondary.lineTo(x, y);
          }
        }
        canvas.drawPath(secondary, highlight);
      }
    }
  }

  void _drawTinyLightPoints(Canvas canvas, Size size) {
    final random = math.Random(42);
    final pointPaint = Paint()
      ..color = PurpleTechBackground.lightPurple.withOpacity(0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    for (var i = 0; i < 22; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final radius = 1 + random.nextDouble() * 1.5;
      canvas.drawCircle(Offset(x, y), radius, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HappyLiveAudioAtmospherePainter oldDelegate) =>
      false;
}
