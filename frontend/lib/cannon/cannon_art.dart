import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cannon_config.dart';

/// Uses a local airplane image for level 1 and the existing artwork for other levels.
class CannonArt extends StatelessWidget {
  final int level;
  final double size;
  final bool dim;
  final bool completed;
  const CannonArt({super.key, required this.level, this.size = 160, this.dim = false, this.completed = false});

  @override
  Widget build(BuildContext context) {
    final url = CannonConfig.cannonImages[level];
    final Widget art = completed
        ? _drawn()
        : level == 1
        ? Image.asset(
            'assets/images/cannon/airplane_lv1.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _drawn(),
          )
        : (url != null && url.isNotEmpty)
            ? Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _drawn(),
              )
            : _drawn();
    return Opacity(opacity: dim ? 0.4 : 1, child: art);
  }

  Widget _drawn() => SizedBox(width: size, height: size, child: CustomPaint(painter: _CannonPainter(level, completed: completed)));
}

class _CannonPainter extends CustomPainter {
  final int level;
  final bool completed;
  _CannonPainter(this.level, {this.completed = false});

  static const _palettes = <List<Color>>[
    [Color(0xFF64E7C5), Color(0xFF126A62)],
    [Color(0xFF8FE9E0), Color(0xFF245A70)],
    [Color(0xFFFFD98A), Color(0xFF95652B)],
    [Color(0xFFB6C8D0), Color(0xFF263A49)],
  ];
  static const _gold = [Color(0xFFFFF0B8), Color(0xFFD5A64E), Color(0xFF8C642A)];

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final pal = completed
        ? const [Color(0xFF20E58B), Color(0xFF075B3D)]
        : _palettes[(level - 1).clamp(0, 3).toInt()];
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
          Paint()..color = const Color(0xFFBCEFE4)..strokeWidth = w * 0.012);
      }
      canvas.drawCircle(c, r, rim);
      canvas.drawCircle(c, r * 0.18, Paint()..color = const Color(0xFFFFE5A0));
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
  bool shouldRepaint(covariant _CannonPainter old) => old.level != level || old.completed != completed;
}
