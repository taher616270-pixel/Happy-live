// نافذة PK المرئية فقط — لا تشغّل المبارزة ولا تتصل بالخادم.
import 'dart:math' as math;
import 'package:flutter/material.dart';

Future<void> showPkSheet(
  BuildContext context, {
  required bool isPkVisualMode,
  required VoidCallback onToggle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: _PkSheet(isPkVisualMode: isPkVisualMode, onToggle: onToggle),
    ),
  );
}

const _purple = [Color(0xFF9620F8), Color(0xFFB12FF2)];

class _PkSheet extends StatelessWidget {
  final bool isPkVisualMode;
  final VoidCallback onToggle;

  const _PkSheet({required this.isPkVisualMode, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        padding: EdgeInsets.fromLTRB(16, 13, 16, 14 + MediaQuery.of(context).padding.bottom),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: [0, 0.5, 1],
            colors: [Color(0xFF5A1228), Color(0xFF2A1060), Color(0xFF141480)],
          ),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 32,
            child: Stack(alignment: Alignment.center, children: [
              const Text('PK', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    width: 32, height: 32,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x1FFFFFFF)),
                    child: const Icon(Icons.question_mark_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 21),
          const Text(
            'يتنافس الفريقان الأحمر والأزرق في تحدي الـPK، والفريق الذي يحقق أعلى نقاط هو الفائز.',
            style: TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.25),
          ),
          const SizedBox(height: 14),
          const _Preview(),
          const SizedBox(height: 16),
          const Text('مدة كل جولة', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Row(children: [
            for (final m in const [5, 15, 30, 120]) ...[
              if (m != 5) const SizedBox(width: 16),
              _Chip(minutes: m, selected: m == 5),
            ],
          ]),
          const SizedBox(height: 22),
          const Text(
            'ملاحظة: في أوضاع 15 و20 و30 مقعدًا صوتيًا، لا يمكن المشاركة في الـ PK إلا للمضيفين الموجودين في أول 12 مقعدًا صوتيًا',
            style: TextStyle(color: Color(0x73FFFFFF), fontSize: 12.5, height: 1.35),
          ),
          const SizedBox(height: 26),
          _Btn(
            label: isPkVisualMode ? 'إغلاق' : 'فتح',
            gradient: true,
            onTap: () {
              // Change the room state while the parent route is still mounted.
              onToggle();
              Navigator.of(context).pop();
            },
          ),
        ]),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview();
  static const double h = 104;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      const d = 43.0;
      Widget seat(double fx) => Positioned(
        left: w * fx - d / 2,
        top: (h - d) / 2,
        child: Container(
          width: d, height: d,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0x38FFFFFF),
            border: Border.all(color: const Color(0x22FFFFFF)),
          ),
          child: const Icon(Icons.chair_alt_outlined, color: Color(0xBFFFFFFF), size: 24),
        ),
      );
      return SizedBox(height: h, child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: CustomPaint(painter: _TeamsPainter())),
        for (final fx in const [0.099, 0.227, 0.355]) seat(fx),
        for (final fx in const [0.645, 0.773, 0.901]) seat(fx),
        const Positioned.fill(child: Center(child: _PkHexBadge(size: 53))),
      ]));
    });
  }
}

Path _roundedPoly(List<Offset> pts, double r) {
  final path = Path();
  final n = pts.length;
  for (var i = 0; i < n; i++) {
    final p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n];
    final v1 = p0 - p1, v2 = p2 - p1;
    final l1 = v1.distance, l2 = v2.distance;
    final rr = math.min(r, math.min(l1, l2) / 2);
    final a = p1 + v1 / l1 * rr;
    final b = p1 + v2 / l2 * rr;
    if (i == 0) { path.moveTo(a.dx, a.dy); } else { path.lineTo(a.dx, a.dy); }
    path.quadraticBezierTo(p1.dx, p1.dy, b.dx, b.dy);
  }
  path.close();
  return path;
}

class _TeamsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height, cx = w / 2;
    final red = _roundedPoly([Offset(0, 0), Offset(cx + 5, 0), Offset(cx - 15, h), Offset(0, h)], 15);
    final blue = _roundedPoly([Offset(cx + 13, 0), Offset(w, 0), Offset(w, h), Offset(cx - 5, h)], 15);
    canvas.drawPath(red, Paint()..shader = const LinearGradient(
      begin: Alignment.topRight, end: Alignment.bottomLeft,
      colors: [Color(0xFFC22B4C), Color(0xFF8F1E3F)],
    ).createShader(Rect.fromLTWH(0, 0, w, h)));
    canvas.drawPath(red, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = const Color(0x66FF8DA6));
    canvas.drawPath(blue, Paint()..shader = const LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFF2F4BE0), Color(0xFF2236B8)],
    ).createShader(Rect.fromLTWH(0, 0, w, h)));
    canvas.drawPath(blue, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = const Color(0x665F7FFF));
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _PkHexBadge extends StatelessWidget {
  final double size;
  const _PkHexBadge({required this.size});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size, height: size,
    child: CustomPaint(
      painter: _HexBadgePainter(),
      child: const Center(child: Text('PK', style: TextStyle(
        color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900,
        fontStyle: FontStyle.italic, shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
      ))),
    ),
  );
}

class _HexBadgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final cx = size.width / 2, cy = size.height / 2, r = size.width * .48;
    for (var i = 0; i < 6; i++) {
      final a = (math.pi / 3 * i) - math.pi / 2;
      final p = Offset(cx + r * math.cos(a), cy + r * math.sin(a));
      if (i == 0) { path.moveTo(p.dx, p.dy); } else { path.lineTo(p.dx, p.dy); }
    }
    path.close();
    canvas.drawPath(path, Paint()..shader = const LinearGradient(
      colors: [Color(0xFFFFC45D), Color(0xFFB56A20), Color(0xFF5A2B18)],
      begin: Alignment.topLeft, end: Alignment.bottomRight,
    ).createShader(Offset.zero & size));
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFFFFE6A0));
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _Chip extends StatelessWidget {
  final int minutes;
  final bool selected;
  const _Chip({required this.minutes, required this.selected});
  @override
  Widget build(BuildContext context) => Container(
    width: 63, height: 31, alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: selected ? const Color(0x22FFFFFF) : const Color(0x18FFFFFF),
      border: selected ? Border.all(color: Colors.white, width: 1.6) : null,
    ),
    child: FittedBox(fit: BoxFit.scaleDown, child: Text('$minutes دقائق',
      style: TextStyle(
        color: selected ? Colors.white : const Color(0x66FFFFFF),
        fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ))),
  );
}

class _Btn extends StatelessWidget {
  final String label;
  final bool gradient;
  final VoidCallback onTap;
  const _Btn({required this.label, required this.onTap, this.gradient = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 48, width: double.infinity, alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: gradient ? const LinearGradient(colors: _purple) : null,
        color: gradient ? null : const Color(0x33FFFFFF),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
    ),
  );
}
