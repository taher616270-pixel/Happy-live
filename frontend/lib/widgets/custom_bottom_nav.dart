import 'package:flutter/material.dart';

/// A fixed five-item navigation bar owned by SessionHomePage.
/// It is intentionally stateless: every item stays in the layout on every tab.
class CustomBottomNav extends StatelessWidget {
  const CustomBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const List<_NavItem> _items = [
    _NavItem(0, Icons.wifi_tethering_outlined, 'Happy Live'),
    _NavItem(3, Icons.chat_bubble_outline_rounded, 'الرسائل'),
    _NavItem(2, Icons.article_outlined, 'المنشورات'),
    _NavItem(1, Icons.bed_outlined, 'غرفة'),
    _NavItem(4, Icons.person_outline_rounded, 'الخاص بي'),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0B0912),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 9),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF191326),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFF39294B),
                width: 1,
              ),
            ),
            child: SizedBox(
              height: 66,
              width: double.infinity,
              child: Row(
                textDirection: Directionality.of(context),
                children: [
                  for (final item in _items)
                    Expanded(
                      child: _NavigationButton(
                        item: item,
                        selected: currentIndex == item.index,
                        onPressed: () {
                          if (currentIndex != item.index) {
                            onTap(item.index);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.index, this.icon, this.label);

  final int index;
  final IconData icon;
  final String label;
}

class _NavigationButton extends StatelessWidget {
  const _NavigationButton({
    required this.item,
    required this.selected,
    required this.onPressed,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground =
        selected ? const Color(0xFFE5C5FF) : const Color(0xFFA49AAF);

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: selected ? const Color(0xFF38234D) : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(17),
            child: SizedBox.expand(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Icon(item.icon, size: 23, color: foreground),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        item.label,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: selected ? Colors.white : foreground,
                          fontSize: 10,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
