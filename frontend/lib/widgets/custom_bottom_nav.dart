import 'package:flutter/material.dart';

/// Persistent, controlled bottom navigation bar.
/// The parent page owns the single Scaffold, IndexedStack, and selected tab.
class CustomBottomNav extends StatefulWidget {
  const CustomBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  State<CustomBottomNav> createState() => _CustomBottomNavState();
}

class _CustomBottomNavState extends State<CustomBottomNav>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  static const items = <(int, IconData, String)>[
    (0, Icons.wifi_tethering_outlined, 'Happy Live'),
    (3, Icons.chat_bubble_outline_rounded, 'الرسائل'),
    (2, Icons.article_outlined, 'المنشورات'),
    (1, Icons.bed_outlined, 'غرفة'),
    (4, Icons.person_outline, 'الخاص بي'),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildNavigationBar();

  Widget _buildNavigationBar() {
    return SizedBox(
      width: double.infinity,
      child: Container(
        color: const Color(0xFF0B0912),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF191326),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: const Color(0xFF302344),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                for (final item in items)
                  Expanded(
                    flex: 1,
                    child: _buildItem(
                      index: item.$1,
                      icon: item.$2,
                      label: item.$3,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final active = widget.currentIndex == index;
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: double.infinity,
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
      decoration: BoxDecoration(
        color: active ? const Color(0x2E8B5CF6) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(
            icon,
            size: 23,
            color: active
                ? const Color(0xFFB58AFF)
                : const Color(0xFFA49AAF),
          ),
          const SizedBox(height: 2),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 10,
                  color: active ? Colors.white : const Color(0xFFA49AAF),
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (index != widget.currentIndex) widget.onTap(index);
      },
      child: CustomPaint(
        foregroundPainter: active
            ? _ActiveBorderPainter(animation: _ctrl)
            : null,
        child: content,
      ),
    );
  }
}

class _ActiveBorderPainter extends CustomPainter {
  _ActiveBorderPainter({required this.animation})
      : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.6),
      const Radius.circular(18),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF8B5CF6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(18)),
    );

    final metrics = (Path()..addRRect(rrect)).computeMetrics();
    if (metrics.isNotEmpty) {
      final metric = metrics.first;
      final progress = animation.value.clamp(0.0, 1.0).toDouble();
      final tangent = metric.getTangentForOffset(metric.length * progress);

      if (tangent != null) {
        final position = tangent.position;
        canvas.drawCircle(
          position,
          12,
          Paint()
            ..shader = const RadialGradient(
              colors: [
                Color(0xF2B58AFF),
                Color(0x738B5CF6),
                Color(0x008B5CF6),
              ],
              stops: [0.0, 0.45, 1.0],
            ).createShader(
              Rect.fromCircle(center: position, radius: 12),
            ),
        );
        canvas.drawCircle(
          position,
          2.5,
          Paint()..color = Colors.white,
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ActiveBorderPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
