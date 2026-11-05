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

  static const items = <(int, IconData, String)>[
    (4, Icons.person_outline, 'الخاص بي'),
    (3, Icons.chat_bubble_outline_rounded, 'الرسائل'),
    (2, Icons.article_outlined, 'المنشورات'),
    (1, Icons.bed_outlined, 'غرفة'),
    (0, Icons.wifi_tethering_outlined, 'Happy Live'),
  ];

  @override
  State<CustomBottomNav> createState() => _CustomBottomNavState();
}

class _CustomBottomNavState extends State<CustomBottomNav>
    with SingleTickerProviderStateMixin {
  late final AnimationController _orbitController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _orbitController.dispose();
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
                for (final item in CustomBottomNav.items)
                  Expanded(
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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (index != widget.currentIndex) widget.onTap(index);
      },
      child: SizedBox(
        height: 56,
        child: AnimatedBuilder(
          animation: _orbitController,
          builder: (context, child) {
            return Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
                  decoration: BoxDecoration(
                    color: active ? const Color(0x2E8B5CF6) : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    border: active
                        ? Border.all(color: const Color(0xFF8B5CF6), width: 1.2)
                        : null,
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
                ),
                if (active)
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _OrbitDotPainter(_orbitController.value),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OrbitDotPainter extends CustomPainter {
  const _OrbitDotPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(2.5),
      const Radius.circular(16),
    );
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    if (metrics.isEmpty) return;

    final metric = metrics.first;
    final tangent = metric.getTangentForOffset(metric.length * progress);
    if (tangent == null) return;

    final point = tangent.position;
    final glow = Paint()
      ..color = const Color(0xFFB98CFF).withOpacity(0.75)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final core = Paint()..color = const Color(0xFFFFFFFF);

    canvas.drawCircle(point, 4.2, glow);
    canvas.drawCircle(point, 2.1, core);
  }

  @override
  bool shouldRepaint(covariant _OrbitDotPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
