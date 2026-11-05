import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Dark audio-inspired background for Happy Live voice rooms and chat screens.
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

  static const Color backgroundColor = Color(0xFF090710);
  static const Color primaryPurple = Color(0xFF8B5CF6);
  static const Color lightPurple = Color(0xFFB58AFF);
  static const Color audioBlue = Color(0xFF596CFF);

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
            painter: _AudioAtmospherePainter(),
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

/// Subtle sound waves and audio rings stay near the edges so the UI remains clear.
class _AudioAtmospherePainter extends CustomPainter {
  const _AudioAtmospherePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final glowPaint = Paint()..style = PaintingStyle.fill;

    glowPaint.shader = RadialGradient(
      colors: [
        PurpleTechBackground.primaryPurple.withOpacity(0.15),
        PurpleTechBackground.primaryPurple.withOpacity(0.035),
        Colors.transparent,
      ],
    ).createShader(
      Rect.fromCircle(
        center: Offset(size.width * 0.08, size.height * 0.82),
        radius: size.width * 0.58,
      ),
    );
    canvas.drawRect(Offset.zero & size, glowPaint);

    glowPaint.shader = RadialGradient(
      colors: [
        PurpleTechBackground.audioBlue.withOpacity(0.10),
        Colors.transparent,
      ],
    ).createShader(
      Rect.fromCircle(
        center: Offset(size.width * 0.94, size.height * 0.18),
        radius: size.width * 0.48,
      ),
    );
    canvas.drawRect(Offset.zero & size, glowPaint);

    _drawSoundRings(
      canvas,
      Offset(size.width * 0.02, size.height * 0.78),
      math.min(size.width, size.height) * 0.42,
      PurpleTechBackground.primaryPurple,
    );
    _drawSoundRings(
      canvas,
      Offset(size.width * 0.98, size.height * 0.20),
      math.min(size.width, size.height) * 0.32,
      PurpleTechBackground.audioBlue,
    );

    _drawWaveform(canvas, size);
  }

  void _drawSoundRings(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
  ) {
    final paint = Paint()
      ..color = color.withOpacity(0.075)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    for (var i = 1; i <= 5; i++) {
      final currentRadius = radius * (0.35 + i * 0.17);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: currentRadius),
        -math.pi * 0.38,
        math.pi * 0.76,
        false,
        paint,
      );
    }
  }

  void _drawWaveform(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round;

    final baseY = size.height * 0.88;
    for (var row = 0; row < 3; row++) {
      linePaint.color =
          PurpleTechBackground.lightPurple.withOpacity(0.045 - row * 0.009);
      final path = Path();
      for (var step = 0; step <= 120; step++) {
        final x = size.width * step / 120;
        final envelope = math.sin(math.pi * step / 120).abs();
        final wave = math.sin(step * 0.24 + row * 0.8) *
            (5 + row * 3) *
            envelope;
        final y = baseY + row * 10 + wave;
        if (step == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    // Small equalizer bars near the bottom corners.
    final barPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;
    for (var side = 0; side < 2; side++) {
      final originX = side == 0 ? size.width * 0.08 : size.width * 0.92;
      for (var i = 0; i < 9; i++) {
        final x = originX + (i - 4) * 6.0;
        final height = 4.0 + (math.sin(i * 1.7).abs() * 13.0);
        barPaint.color =
            PurpleTechBackground.primaryPurple.withOpacity(0.10);
        canvas.drawLine(
          Offset(x, size.height * 0.96 - height / 2),
          Offset(x, size.height * 0.96 + height / 2),
          barPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AudioAtmospherePainter oldDelegate) => false;
}

class _PurpleBokehPainter extends CustomPainter {
  const _PurpleBokehPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(25);
    for (var i = 0; i < 22; i++) {
      final center = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final radius = 1.0 + random.nextDouble() * 2.2;
      final paint = Paint()
        ..color = PurpleTechBackground.lightPurple.withOpacity(0.065)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PurpleBokehPainter oldDelegate) => false;
}
