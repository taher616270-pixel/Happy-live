import 'dart:math';
import 'package:flutter/material.dart';

/// Animated neon-purple background used throughout Happy Live.
class NeonBackground extends StatefulWidget {
  final Widget? child;
  const NeonBackground({super.key, this.child});

  @override
  State<NeonBackground> createState() => _NeonBackgroundState();
}

/// Backwards-compatible name used by main.dart.
class PurpleTechBackground extends NeonBackground {
  const PurpleTechBackground({super.key, super.child});
}

class _NeonBackgroundState extends State<NeonBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final rnd = Random(7);
    _particles = List.generate(40, (_) {
      final left = rnd.nextBool();
      final x = left ? rnd.nextDouble() * 0.3 : 0.7 + rnd.nextDouble() * 0.3;
      return _Particle(
        x: rnd.nextDouble() < 0.2 ? rnd.nextDouble() : x,
        y: rnd.nextDouble(),
        r: 2 + rnd.nextDouble() * 12,
        a: 0.25 + rnd.nextDouble() * 0.55,
        speed: 0.3 + rnd.nextDouble() * 0.7,
      );
    });
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(
              painter: _NeonPainter(_particles, _c.value),
            ),
          ),
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _Particle {
  final double x, y, r, a, speed;
  _Particle({
    required this.x,
    required this.y,
    required this.r,
    required this.a,
    required this.speed,
  });
}

class _NeonPainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;
  _NeonPainter(this.particles, this.t);

  static const _purple = Color(0xFF7C4DFF);
  static const _light = Color(0xFFA78BFA);

  @override
  void paint(Canvas canvas, Size size) {
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

    final border = rect.deflate(size.width * 0.022);
    canvas.drawRect(
      border,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.12
        ..color = _purple.withOpacity(0.18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.08),
    );

    void neon(double w, double blur, double op, Color c) {
      canvas.drawRect(
        border,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..color = c.withOpacity(op)
          ..maskFilter =
              blur > 0 ? MaskFilter.blur(BlurStyle.normal, blur) : null,
      );
    }

    neon(16, 22, 0.40, _purple);
    neon(7, 9, 0.65, _purple);
    neon(2.2, 0, 1.0, _light);

    for (final p in particles) {
      final y = ((p.y - t * p.speed) % 1.0 + 1.0) % 1.0;
      final pos = Offset(p.x * size.width, y * size.height);
      final paint = Paint()..color = _light.withOpacity(p.a * 0.7);
      if (p.r > 6) {
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, p.r * 0.5);
      }
      canvas.drawCircle(pos, p.r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NeonPainter old) => old.t != t;
}
