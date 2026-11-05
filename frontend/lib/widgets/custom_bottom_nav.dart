import 'package:flutter/material.dart';

const _gold = Color(0xFFF0A62B);
const _inactive = Color(0xFFC9CAD6);

/// Persistent, controlled bottom navigation bar.
/// The parent page owns the single Scaffold, IndexedStack, and selected tab.
class CustomBottomNav extends StatelessWidget {
  const CustomBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  // Keep the existing five destinations, their indices, labels, and icons.
  static const items = <(int, IconData, String)>[
    (0, Icons.wifi_tethering_outlined, 'Happy Live'),
    (1, Icons.bed_outlined, 'غرفة'),
    (2, Icons.article_outlined, 'المنشورات'),
    (3, Icons.chat_bubble_outline_rounded, 'الرسائل'),
    (4, Icons.person_outline, 'الخاص بي'),
  ];

  @override
  Widget build(BuildContext context) => _buildNavigationBar(context);

  Widget _buildNavigationBar(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return SizedBox(
      width: double.infinity,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(12, 6, 12, 6 + bottomInset),
        decoration: const BoxDecoration(
          color: Color(0xFFFAFAFD),
          border: Border(
            top: BorderSide(color: Color(0xFFEDEDF3)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            for (final item in items)
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
    );
  }

  Widget _buildItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final active = currentIndex == index;
    final color = active ? _gold : _inactive;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (index != currentIndex) onTap(index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEDEDF2) : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 27, color: color),
            const SizedBox(height: 2),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: color,
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
