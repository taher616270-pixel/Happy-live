// lib/pk/pk_score_bar.dart
// شريط النقاط: أزرق (يسار) / أحمر (يمين) + كبسولة بالنص + أسهم متحركة + أرقام تعد + تاب تحت
import 'dart:math' as math;
import 'package:flutter/material.dart';

String _fmt(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

class PkScoreBar extends StatefulWidget {
  final int red, blue;
  final Widget? tab;
  final VoidCallback? onTapTab;

  const PkScoreBar({super.key, required this.red, required this.blue, this.tab, this.onTapTab});

  static const double barH = 18;
  static const double stripH = 11;
  static const double tabH = 21;
  static const double tabW = 132;
  static const double capW = 26;
  static const double headerH = barH + stripH;
  static const double height = barH + 2 + tabH;

  @override
  State<PkScoreBar> createState() => _PkScoreBarState();
}

class _PkScoreBarState extends State<PkScoreBar> with TickerProviderStateMixin {
  late final AnimationController _flow =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  late final AnimationController _bump =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 550));

  int _redEvt = 0, _blueEvt = 0, _redDelta = 0, _blueDelta = 0;

  @override
  void didUpdateWidget(covariant PkScoreBar old) {
    super.didUpdateWidget(old);
    final dr = widget.red - old.red;
    final db = widget.blue - old.blue;
    if (dr > 0) {
      _redEvt++;
      _redDelta = dr;
    }
    if (db > 0) {
      _blueEvt++;
      _blueDelta = db;
    }
    if (dr != 0 || db != 0) _bump.forward(from: 0);
  }

  @override
  void dispose() {
    _flow.dispose();
    _bump.dispose();
    super.dispose();
  }

  double get _frac {
    final total = widget.red + widget.blue;
    if (total <= 0) return 0.5;
    return (widget.blue / total).clamp(0.08, 0.92).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: PkScoreBar.height,
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          return TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.5, end: _frac),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, f, _) {
              return Stack(clipBehavior: Clip.none, children: [
                Positioned(
                  top: 0, left: 0, right: 0, height: PkScoreBar.headerH,
                  child: CustomPaint(painter: _BarPainter(frac: f, flow: _flow, bump: _bump)),
                ),
                Positioned(left: 8, top: 1, child: _Num(value: widget.blue)),
                Positioned(right: 8, top: 1, child: _Num(value: widget.red)),
                if (_blueEvt > 0)
                  Positioned(
                    left: 10, top: PkScoreBar.barH,
                    child: _FloatUp(key: ValueKey('b$_blueEvt'), text: '+${_fmt(_blueDelta)}', color: const Color(0xFFA9B8FF)),
                  ),
                if (_redEvt > 0)
                  Positioned(
                    right: 10, top: PkScoreBar.barH,
                    child: _FloatUp(key: ValueKey('r$_redEvt'), text: '+${_fmt(_redDelta)}', color: const Color(0xFFFFB3CF)),
                  ),
                Positioned(
                  top: PkScoreBar.barH + 2,
                  left: (w - PkScoreBar.tabW) / 2,
                  width: PkScoreBar.tabW,
                  height: PkScoreBar.tabH,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onTapTab,
                    child: CustomPaint(
                      painter: const _TabPainter(),
                      child: Center(child: widget.tab),
                    ),
                  ),
                ),
              ]);
            },
          );
        }),
      ),
    );
  }
}

class _Num extends StatelessWidget {
  final int value;
  const _Num({required this.value});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<int>(
        tween: IntTween(begin: 0, end: value),
        duration: const Duration(milliseconds: 700),
        builder: (_, v, __) => Text(
          _fmt(v),
          style: const TextStyle(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, height: 1.2,
            shadows: [Shadow(color: Color(0x55000000), blurRadius: 2)],
          ),
        ),
      );
}

class _FloatUp extends StatelessWidget {
  final String text;
  final Color color;
  const _FloatUp({super.key, required this.text, required this.color});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1000),
        builder: (_, t, __) => Opacity(
          opacity: (1 - t).clamp(0.0, 1.0).toDouble(),
          child: Transform.translate(
            offset: Offset(0, 16 * t),
            child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ),
      );
}

class _BarPainter extends CustomPainter {
  final double frac;
  final Animation<double> flow, bump;

  _BarPainter({required this.frac, required this.flow, required this.bump})
      : super(repaint: Listenable.merge([flow, bump]));

  static const _sparks = <List<double>>[
    [0.15, 0.25, 0.00, 1.4],
    [0.35, 0.70, 0.20, 1.0],
    [0.55, 0.30, 0.45, 1.6],
    [0.70, 0.65, 0.60, 1.1],
    [0.85, 0.35, 0.80, 0.9],
    [0.45, 0.50, 0.35, 0.8],
    [0.25, 0.55, 0.70, 1.2],
  ];

  void _chevrons(Canvas canvas, Rect area, {required bool toRight, required double t}) {
    if (area.width <= 0) return;
    const gap = 24.0;
    const h = PkScoreBar.barH;
    final off = (toRight ? t : -t) * gap;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeJoin = StrokeJoin.miter
      ..color = const Color(0x24FFFFFF);
    canvas.save();
    canvas.clipRect(area);
    for (double cx = -gap * 2 + (off % gap); cx < area.right + gap; cx += gap) {
      final path = Path();
      if (toRight) {
        path..moveTo(cx - 4, 0)..lineTo(cx + 4, h / 2)..lineTo(cx - 4, h);
      } else {
        path..moveTo(cx + 4, 0)..lineTo(cx - 4, h / 2)..lineTo(cx + 4, h);
      }
      canvas.drawPath(path, p);
    }
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    const h = PkScoreBar.barH;
    const capW = PkScoreBar.capW;
    final x = w * frac;
    final t = flow.value;

    final bar = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRect(
      bar,
      Paint()..shader = const LinearGradient(colors: [Color(0xFFE02672), Color(0xFFD01F66)]).createShader(bar),
    );

    final blueRect = Rect.fromLTRB(0, 0, x + h / 2, h);
    canvas.drawRect(
      blueRect,
      Paint()..shader = const LinearGradient(colors: [Color(0xFF2A47FF), Color(0xFF2038E8)]).createShader(blueRect),
    );

    _chevrons(canvas, Rect.fromLTRB(0, 0, x, h), toRight: true, t: t);
    _chevrons(canvas, Rect.fromLTRB(x + capW, 0, w, h), toRight: false, t: t);

    final sx = (x + 6).clamp(0.0, w).toDouble();
    canvas.drawRect(Rect.fromLTRB(0, h, sx, h + PkScoreBar.stripH), Paint()..color = const Color(0xFF28208F));
    canvas.drawRect(Rect.fromLTRB(sx, h, w, h + PkScoreBar.stripH), Paint()..color = const Color(0xFF7A0A3D));

    final k = 1 + 0.14 * math.sin(bump.value * math.pi);
    final glow = math.sin(bump.value * math.pi);
    final capL = x, capR = x + capW;
    canvas.save();
    final c = Offset(capL + h / 2, h / 2);
    canvas.translate(c.dx, c.dy);
    canvas.scale(k);
    canvas.translate(-c.dx, -c.dy);

    final cap = RRect.fromLTRBAndCorners(
      capL, -1, capR, h + 1,
      topLeft: const Radius.circular(h / 2 + 1),
      bottomLeft: const Radius.circular(h / 2 + 1),
      topRight: const Radius.circular(4),
      bottomRight: const Radius.circular(4),
    );
    canvas.drawRRect(
      cap,
      Paint()
        ..color = Color.fromARGB((90 + 120 * glow).round(), 255, 255, 255)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + 6 * glow),
    );
    canvas.drawRRect(
      cap,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFFFC2D9), Color(0x00E02672)],
          stops: [0, 0.55, 1],
        ).createShader(Rect.fromLTRB(capL, 0, capR, h)),
    );

    for (final sp in _sparks) {
      final ph = sp[2];
      final tw = (math.sin(2 * math.pi * (t * 2 + ph)) + 1) / 2;
      final drift = -3 * ((t + ph) % 1.0);
      canvas.drawCircle(
        Offset(capL + sp[0] * capW, sp[1] * h + drift),
        sp[3],
        Paint()..color = Color.fromARGB((tw * 235).round(), 255, 255, 255),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.frac != frac;
}

class _TabPainter extends CustomPainter {
  const _TabPainter();
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    const inset = 10.0, r = 8.0;

    // Mirror the same tab silhouette vertically; dimensions, curves and colors stay unchanged.
    canvas.save();
    canvas.translate(0, h);
    canvas.scale(1, -1);

    final open = Path()
      ..moveTo(0, h)
      ..lineTo(inset, r)
      ..quadraticBezierTo(inset + 1, 0, inset + r + 1, 0)
      ..lineTo(w - inset - r - 1, 0)
      ..quadraticBezierTo(w - inset - 1, 0, w - inset, r)
      ..lineTo(w, h);
    final fill = Path.from(open)..close();
    final rect = Rect.fromLTWH(0, 0, w, h);

    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(colors: [Color(0xFF3447D8), Color(0xFF8A2FA8), Color(0xFFD02A78)])
            .createShader(rect),
    );
    canvas.drawPath(
      open,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = const LinearGradient(colors: [Color(0xFF7F8CFF), Color(0xFFFF73B8)]).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
