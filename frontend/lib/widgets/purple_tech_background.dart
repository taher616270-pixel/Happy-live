import 'dart:math';
import 'package:flutter/material.dart';

/// Static neon-purple background used throughout Happy Live.
class NeonBackground extends StatelessWidget {
  final Widget? child;
  const NeonBackground({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const RepaintBoundary(
          child: CustomPaint(painter: _NeonPainter()),
        ),
        if (child != null) child!,
      ],
    );
  }
}

/// Backwards-compatible name used by main.dart.
class PurpleTechBackground extends NeonBackground {
  const PurpleTechBackground({super.key, super.child});
}

class _Particle {
  final double x, y, r, a;
  const _Particle({
    required this.x,
    required this.y,
    required this.r,
    required this.a,
  });
}

class _NeonPainter extends CustomPainter {
  const _NeonPainter();

  static const _purple = Color(0xFF7C4DFF);
  static const _light = Color(0xFFA78BFA);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          radius: 1.0,
          colors: [Color(0xFF07050D), Color(0xFF1B1038)],
          stops: [0.35, 1.0],
        ).createShader(rect),
    );

    final rnd = Random(3);
    final line = Paint()
      ..color = _purple.withOpacity(0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final dot = Paint()..color = _purple.withOpacity(0.18);

    for (int i = 0; i < 30; i++) {
      final left = rnd.nextBool();
      double x = left
          ? size.width * rnd.nextDouble() * 0.3
          : size.width * (0.7 + rnd.nextDouble() * 0.3);
      double y = size.height * rnd.nextDouble();
      final path = Path()..moveTo(x, y);
      for (int s = 0; s < 4; s++) {
        if (s.isEven) {
          x += (rnd.nextDouble() - 0.5) * 120;
        } else {
          y += (rnd.nextDouble() - 0.5) * 120;
        }
        path.lineTo(x, y);
      }
      canvas.drawPath(path, line);
      canvas.drawCircle(Offset(x, y), 2.5, dot);
    }

    // Expanded frame: reduce the inset so the frame is wider and taller.
    final border = rect.deflate(size.width * 0.012);
    canvas.drawRect(
      border,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.12
        ..color = _purple.withOpacity(0.18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.08),
    );

    void neon(double width, double blur, double opacity, Color color) {
      canvas.drawRect(
        border,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = color.withOpacity(opacity)
          ..maskFilter =
              blur > 0 ? MaskFilter.blur(BlurStyle.normal, blur) : null,
      );
    }

    neon(16, 22, 0.40, _purple);
    neon(7, 9, 0.65, _purple);
    neon(2.2, 0, 1.0, _light);

    // Fixed light particles: no animation or movement.
    final particleRandom = Random(7);
    final particles = List.generate(40, (_) {
      final left = particleRandom.nextBool();
      final x = left
          ? particleRandom.nextDouble() * 0.3
          : 0.7 + particleRandom.nextDouble() * 0.3;
      return _Particle(
        x: particleRandom.nextDouble() < 0.2
            ? particleRandom.nextDouble()
            : x,
        y: particleRandom.nextDouble(),
        r: 2 + particleRandom.nextDouble() * 12,
        a: 0.25 + particleRandom.nextDouble() * 0.55,
      );
    });

    for (final particle in particles) {
      final position = Offset(
        particle.x * size.width,
        particle.y * size.height,
      );
      final paint = Paint()..color = _light.withOpacity(particle.a * 0.7);
      if (particle.r > 6) {
        paint.maskFilter =
            MaskFilter.blur(BlurStyle.normal, particle.r * 0.5);
      }
      canvas.drawCircle(position, particle.r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NeonPainter oldDelegate) => false;
}
