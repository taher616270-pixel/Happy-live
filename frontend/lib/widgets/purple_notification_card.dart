import 'package:flutter/material.dart';

/// Reusable black-and-purple technology background for Happy Live pages.
///
/// Example:
/// Scaffold(
///   body: PurpleTechBackground(
///     child: SafeArea(child: YourPageContent()),
///   ),
/// )
class PurpleTechBackground extends StatelessWidget {
  const PurpleTechBackground({
    super.key,
    this.child,
    this.showBorder = false,
    this.showGlow = false,
  });

  final Widget? child;
  final bool showBorder;
  final bool showGlow;

  static const Color backgroundColor = Color(0xFF0B0912);
  static const Color primaryPurple = Color(0xFF8B5CF6);
  static const Color lightPurple = Color(0xFFB58AFF);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: showBorder
            ? Border.all(color: primaryPurple, width: 2)
            : null,
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: primaryPurple.withOpacity(0.35),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(
            painter: _CircuitPatternPainter(),
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

class _CircuitPatternPainter extends CustomPainter {
  const _CircuitPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = PurpleTechBackground.primaryPurple.withOpacity(0.105)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final nodePaint = Paint()
      ..color = PurpleTechBackground.lightPurple.withOpacity(0.22)
      ..style = PaintingStyle.fill;

    const spacingX = 54.0;
    const spacingY = 48.0;

    for (double y = 12; y < size.height + spacingY; y += spacingY) {
      for (double x = 10; x < size.width + spacingX; x += spacingX) {
        final path = Path()
          ..moveTo(x, y)
          ..lineTo(x + 15, y)
          ..lineTo(x + 15, y + 12)
          ..lineTo(x + 34, y + 12);

        canvas.drawPath(path, linePaint);
        canvas.drawCircle(Offset(x + 34, y + 12), 1.6, nodePaint);

        if ((x / spacingX).floor().isEven) {
          final branch = Path()
            ..moveTo(x + 15, y + 12)
            ..lineTo(x + 15, y + 25);
          canvas.drawPath(branch, linePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CircuitPatternPainter oldDelegate) => false;
}

class _PurpleBokehPainter extends CustomPainter {
  const _PurpleBokehPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(25);

    for (var i = 0; i < 42; i++) {
      final center = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final radius = 1.5 + random.nextDouble() * 4.5;
      final opacity = 0.08 + random.nextDouble() * 0.22;

      final paint = Paint()
        ..color = PurpleTechBackground.lightPurple.withOpacity(opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PurpleBokehPainter oldDelegate) => false;
}


import 'package:flutter/material.dart';

/// Reusable notification banner matching the Happy Live purple neon style.
class PurpleNotificationCard extends StatelessWidget {
  const PurpleNotificationCard({super.key, required this.name, required this.message, required this.time, this.avatarUrl, this.avatar, this.unreadCount});
  final String name, message, time;
  final String? avatarUrl;
  final Widget? avatar;
  final int? unreadCount;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
    decoration: BoxDecoration(
      color: const Color(0xFF1B1128).withOpacity(.94),
      borderRadius: BorderRadius.circular(25),
      border: Border.all(color: const Color(0xFFB58AFF), width: 1.5),
      boxShadow: const [BoxShadow(color: Color(0x668B5CF6), blurRadius: 18, spreadRadius: 1)],
    ),
    child: Row(children: [
      Container(width: 68, height: 68, padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFD9A8FF), width: 2),
          boxShadow: const [BoxShadow(color: Color(0xAA9B63D9), blurRadius: 12)]),
        child: ClipOval(child: avatar ?? (avatarUrl == null || avatarUrl!.isEmpty
          ? const ColoredBox(color: Color(0xFF302044), child: Icon(Icons.person, color: Colors.white, size: 34))
          : Image.network(avatarUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF302044), child: Icon(Icons.person, color: Colors.white))))),
      ),
      const SizedBox(width: 13),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
        const SizedBox(height: 7),
        Text(message, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFD4C9E0), fontSize: 14, fontWeight: FontWeight.w600)),
      ])),
      const SizedBox(width: 8),
      Column(mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: const Color(0xFFB58AFF), borderRadius: BorderRadius.circular(24)), child: Text(time, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12))),
        if (unreadCount != null && unreadCount! > 0) ...[const SizedBox(height: 7), CircleAvatar(radius: 11, backgroundColor: const Color(0xFF9B63D9), child: Text('$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)))],
      ]),
    ]),
  );
}
