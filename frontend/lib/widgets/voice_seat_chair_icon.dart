import 'package:flutter/material.dart';

/// ويدجت أيقونة كرسي المايك الصوتي المعتمدة بدقة متجهة
class VoiceSeatChairIcon extends StatelessWidget {
  final double size;
  final Color color;
  final double? strokeWidth;
  final bool showBackgroundCircle;
  final Color backgroundColor;
  final Color borderColor;

  const VoiceSeatChairIcon({
    Key? key,
    this.size = 40.0,
    this.color = const Color(0xFF9A98A6),
    this.strokeWidth,
    this.showBackgroundCircle = true,
    this.backgroundColor = const Color(0xFF1E1C2B),
    this.borderColor = const Color(0xFF2D2A3E),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final effectiveStroke = strokeWidth ?? (4.0 * (size / 68.0));
    final chair = CustomPaint(
      size: Size(
        size * (showBackgroundCircle ? 0.58 : 1.0),
        size * (showBackgroundCircle ? 0.58 : 1.0),
      ),
      painter: ChairCustomPainter(
        color: color,
        strokeWidth: effectiveStroke,
      ),
    );

    if (!showBackgroundCircle) return chair;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
        border: Border.all(
          color: borderColor,
          width: size >= 60 ? 2.0 : 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: chair,
    );
  }
}

/// الرسام المتجهي للكرسي (يدعم الرسم داخل أي ويدجت بحجمه الطبيعي)
class ChairCustomPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const ChairCustomPainter({
    this.color = const Color(0xFF9A98A6),
    this.strokeWidth = 2.4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    double sx(double x) => (x / 100.0) * w;
    double sy(double y) => (y / 100.0) * h;

    // 1. ظهر الكرسي المقوس (Backrest Dome Arch)
    final backrest = Path()
      ..moveTo(sx(35), sy(36))
      ..cubicTo(sx(35), sy(21), sx(42), sy(18), sx(50), sy(18))
      ..cubicTo(sx(58), sy(18), sx(65), sy(21), sx(65), sy(36));
    canvas.drawPath(backrest, paint);

    // 2. جسم الكرسي، مساند الأذرع وقاعدة المقعد (Armrests & Seat Base)
    final body = Path()
      ..moveTo(sx(32), sy(68))
      ..lineTo(sx(68), sy(68))
      ..cubicTo(sx(72), sy(68), sx(74), sy(65.5), sx(74), sy(61.5))
      ..lineTo(sx(74), sy(44))
      ..cubicTo(sx(74), sy(39.5), sx(70), sy(37.5), sx(66), sy(37.5))
      ..cubicTo(sx(62.5), sy(37.5), sx(60.5), sy(40), sx(60), sy(44))
      ..cubicTo(sx(59.5), sy(48.5), sx(57), sy(50), sx(53), sy(50))
      ..lineTo(sx(47), sy(50))
      ..cubicTo(sx(43), sy(50), sx(40.5), sy(48.5), sx(40), sy(44))
      ..cubicTo(sx(39.5), sy(40), sx(37.5), sy(37.5), sx(34), sy(37.5))
      ..cubicTo(sx(30), sy(37.5), sx(26), sy(39.5), sx(26), sy(44))
      ..lineTo(sx(26), sy(61.5))
      ..cubicTo(sx(26), sy(65.5), sx(28), sy(68), sx(32), sy(68))
      ..close();
    canvas.drawPath(body, paint);

    // 3. أرجل الكرسي السفلية (Vertical Legs)
    final legs = Path()
      ..moveTo(sx(36), sy(68.5))
      ..lineTo(sx(36), sy(76.0))
      ..moveTo(sx(64), sy(68.5))
      ..lineTo(sx(64), sy(76.0));
    canvas.drawPath(legs, paint);
  }

  @override
  bool shouldRepaint(covariant ChairCustomPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
