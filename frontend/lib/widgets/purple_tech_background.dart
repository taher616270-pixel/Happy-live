import 'package:flutter/material.dart';

/// Shared dark-purple neon background used across Happy Live.
class PurpleTechBackground extends StatelessWidget {
  const PurpleTechBackground({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.0, -0.35),
          radius: 1.25,
          colors: [
            Color(0xFF211332),
            Color(0xFF100B19),
            Color(0xFF09080D),
          ],
          stops: [0.0, 0.58, 1.0],
        ),
      ),
      child: CustomPaint(
        painter: _PurpleTechPainter(),
        child: child == null ? const SizedBox.expand() : SizedBox.expand(child: child),
      ),
    );
  }
}

class _PurpleTechPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0x268B5CF6);

    final center = Offset(size.width * 0.5, size.height * 0.34);
    for (var i = 0; i < 7; i++) {
      final rect = Rect.fromCenter(
        center: center,
        width: size.width * (0.38 + i * 0.13),
        height: size.width * (0.38 + i * 0.13),
      );
      canvas.drawOval(rect, glow);
    }

    final linePaint = Paint()
      ..color = const Color(0x168B5CF6)
      ..strokeWidth = 1;
    for (var i = 0; i < 8; i++) {
      final y = size.height * (0.16 + i * 0.105);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final cornerPaint = Paint()
      ..color = const Color(0x338B5CF6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const corner = 28.0;
    canvas.drawLine(const Offset(12, 12), const Offset(12 + corner, 12), cornerPaint);
    canvas.drawLine(const Offset(12, 12), const Offset(12, 12 + corner), cornerPaint);
    canvas.drawLine(Offset(size.width - 12, 12), Offset(size.width - 12 - corner, 12), cornerPaint);
    canvas.drawLine(Offset(size.width - 12, 12), Offset(size.width - 12, 12 + corner), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant _PurpleTechPainter oldDelegate) => false;
}
