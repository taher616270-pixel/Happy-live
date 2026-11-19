import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cannon_config.dart';

/// Uses an optional ImageKit image; otherwise draws the cannon in Flutter.
class CannonArt extends StatelessWidget {
  final int level;
  final double size;
  final bool dim;
  const CannonArt({super.key, required this.level, this.size = 160, this.dim = false});

  @override
  Widget build(BuildContext context) {
    final url = CannonConfig.cannonImages[level];
    final Widget art = (url != null && url.isNotEmpty)
      ? Image.network(url, width: size, height: size, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _drawn())
      : _drawn();
    return Opacity(opacity: dim ? 0.4 : 1, child: art);
  }

  Widget _drawn() => SizedBox(width: size, height: size, child: CustomPaint(painter: _CannonPainter(level)));
}

class _CannonPainter extends CustomPainter {
  final int level;
  _CannonPainter(this.level);

  static const _palettes = <List<Color>>[
    [Color(0xFF1F9A5C), Color(0xFF0B4D2C)],
    [Color(0xFF8A5CC8), Color(0xFF3A1F66)],
    [Color(0xFF3F74E0), Color(0xFF142C6B)],
    [Color(0xFF2A2A2E), Color(0xFF08080A)],
  ];
  static const _gold = [Color(0xFFFFE08A), Color(0xFFB8791B)];

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final pal = _palettes[(level - 1).clamp(0, 3)];
    final goldPaint = (Rect r) => Paint()
      ..shader = const LinearGradient(colors: _gold, begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(r);

    void wheel(Offset c, double r) {
      final rim = Paint()
        ..shader = const LinearGradient(colors: _gold).createShader(Rect.fromCircle(center: c, radius: r))
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.035;
      canvas.drawCircle(c, r, Paint()..color = const Color(0xFF3A2A12));
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * r,
          Paint()..color = const Color(0xFFE0A93C)..strokeWidth = w * 0.012);
      }
      canvas.drawCircle(c, r, rim);
      canvas.drawCircle(c, r * 0.18, Paint()..color = const Color(0xFFFFD66B));
    }

    wheel(Offset(w * 0.40, w * 0.74), w * 0.17);
    wheel(Offset(w * 0.68, w * 0.76), w * 0.15);
    canvas.save();
    canvas.translate(w * 0.5, w * 0.44);
    canvas.rotate(-0.5);
    final body = RRect.fromRectAndRadius(
      Rect.fromLTRB(-w * 0.32, -w * 0.12, w * 0.2, w * 0.12), Radius.circular(w * 0.05));
    canvas.drawRRect(body, Paint()
      ..shader = LinearGradient(colors: pal, begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(body.outerRect));
    for (final x in [-0.22, -0.02]) {
      final band = Rect.fromLTRB(w * x, -w * 0.125, w * (x + 0.045), w * 0.125);
      canvas.drawRect(band, goldPaint(band));
    }
    final mouth = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.19, -w * 0.17, w * 0.31, w * 0.17), Radius.circular(w * 0.04));
    canvas.drawRRect(mouth, goldPaint(mouth.outerRect));
    canvas.drawOval(Rect.fromLTRB(w * 0.27, -w * 0.12, w * 0.33, w * 0.12), Paint()..color = const Color(0xFF120A02));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CannonPainter old) => old.level != level;
}
