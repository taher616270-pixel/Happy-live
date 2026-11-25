// lib/tabs/swipe_chip_tabs.dart
// تبويبات كبسولات + صفحات تتبدل بسحب الإصبع (بالاتجاه العربي RTL)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SwipeChipTabs extends StatefulWidget {
  /// عناوين التبويبات (الأول يطلع يمين)
  final List<String> titles;

  /// صفحة لكل تبويب (تنبني عند الحاجة وتبقى محفوظة)
  final List<WidgetBuilder> pages;

  final int initial;
  final ValueChanged<int>? onChanged;

  final Color selectedColor;
  final Color chipColor;
  final Color selectedText;
  final Color unselectedText;
  final bool keepPagesAlive;

  const SwipeChipTabs({
    super.key,
    required this.titles,
    required this.pages,
    this.initial = 0,
    this.onChanged,
    this.selectedColor = const Color(0xFF1AD3BB),
    this.chipColor = const Color(0xFF1B2927),
    this.selectedText = Colors.white,
    this.unselectedText = const Color(0xFF9DB0AC),
    this.keepPagesAlive = true,
  }) : assert(titles.length == pages.length);

  @override
  State<SwipeChipTabs> createState() => SwipeChipTabsState();
}

class SwipeChipTabsState extends State<SwipeChipTabs> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  final ScrollController _row = ScrollController();
  late final List<GlobalKey> _keys = List.generate(widget.titles.length, (_) => GlobalKey());
  late int _sel = widget.initial;

  int get selected => _sel;

  /// انتقل لتبويب معين من برا
  void goTo(int i) {
    if (!_pc.hasClients) return;
    _pc.animateToPage(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  @override
  void initState() {
    super.initState();
    _pc.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(_sel, animate: false));
  }

  @override
  void dispose() {
    _pc.removeListener(_onScroll);
    _pc.dispose();
    _row.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_pc.hasClients || !_pc.position.haveDimensions) return;
    final p = _pc.page;
    if (p == null) return;
    final r = p.round().clamp(0, widget.titles.length - 1);
    if (r != _sel) {
      _sel = r;
      HapticFeedback.selectionClick();
      _reveal(r);
      widget.onChanged?.call(r);
      setState(() {});
    }
  }

  /// يمرر صف التبويبات لين يظهر التبويب المختار بالنص
  void _reveal(int i, {bool animate = true}) {
    final ctx = _keys[i].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: animate ? const Duration(milliseconds: 320) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.titles.length;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(children: [
        // صف التبويبات (يتحرك بسحب الإصبع)
        SizedBox(
          height: 46,
          child: SingleChildScrollView(
            controller: _row,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                _Chip(
                  key: _keys[i],
                  index: i,
                  title: widget.titles[i],
                  pc: _pc,
                  fallbackPage: _sel,
                  w: widget,
                  onTap: () => goTo(i),
                ),
              ],
            ]),
          ),
        ),
        // الصفحات (سحب أفقي)
        Expanded(
          child: PageView.builder(
            controller: _pc,
            itemCount: n,
            itemBuilder: (context, i) => widget.keepPagesAlive
                ? _KeepAlive(child: Builder(builder: widget.pages[i]))
                : Builder(builder: widget.pages[i]),
          ),
        ),
      ]),
    );
  }
}

/// كبسولة: اللون والخط يتدرجون مع حركة الإصبع (t من 0 إلى 1)
class _Chip extends StatelessWidget {
  final int index;
  final String title;
  final PageController pc;
  final int fallbackPage;
  final SwipeChipTabs w;
  final VoidCallback onTap;
  const _Chip({
    super.key,
    required this.index,
    required this.title,
    required this.pc,
    required this.fallbackPage,
    required this.w,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedBuilder(
        animation: pc,
        builder: (_, __) {
          double p = fallbackPage.toDouble();
          if (pc.hasClients && pc.position.haveDimensions) p = pc.page ?? p;
          final t = (1 - (p - index).abs()).clamp(0.0, 1.0).toDouble();
          return Transform.scale(
            scale: 1 + 0.03 * t,
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color.lerp(w.chipColor, w.selectedColor, t),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                title,
                style: TextStyle(
                  color: Color.lerp(w.unselectedText, w.selectedText, t),
                  fontSize: 13.5,
                  fontWeight: t > 0.5 ? FontWeight.w700 : FontWeight.w500,
                  height: 1.1,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
