// ranking_sheet_pro.dart
// نسخة Flutter مطوّرة (مستوى تطبيق عالمي) من شيت "تصنيف المساهمين في الغرفة"
// انسخ هذا الملف داخل مشروع Flutter (مثلاً lib/main.dart) وشغّله مباشرة.
// لا يحتاج أي package خارجي — فقط Flutter SDK الأساسي.

import 'dart:async';
import 'package:flutter/material.dart';

void main() => runApp(const RankingDemoApp());

class RankingDemoApp extends StatelessWidget {
  const RankingDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Directionality(textDirection: TextDirection.rtl, child: child!);
      },
      home: const LiveRoomMock(),
    );
  }
}

/// ===================== شاشة الخلفية (غرفة البث) =====================
class LiveRoomMock extends StatelessWidget {
  const LiveRoomMock({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF2a2a28), Color(0xFF000000)],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Icon(Icons.close, color: Colors.white, size: 22),
                          Row(children: const [
                            Icon(Icons.camera_alt_outlined, color: Colors.white70, size: 20),
                            SizedBox(width: 12),
                            Icon(Icons.emoji_events_outlined, color: Colors.amber, size: 20),
                            SizedBox(width: 4),
                            Text('0', style: TextStyle(color: Colors.white, fontSize: 13)),
                          ]),
                          Row(children: const [
                            CircleAvatar(radius: 14, backgroundColor: Colors.white24),
                            SizedBox(width: 6),
                            Text('اليافعي', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ]),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const RankingSheet(),
        ],
      ),
    );
  }
}

/// ===================== الشيت الرئيسي =====================
class RankingSheet extends StatefulWidget {
  const RankingSheet({super.key});

  @override
  State<RankingSheet> createState() => _RankingSheetState();
}

class _RankingSheetState extends State<RankingSheet> with TickerProviderStateMixin {
  int _selectedTab = 0;
  final List<String> _tabs = const ['اليومي', 'أسبوعي', 'شهريا'];

  static const Color sheetTop = Color(0xFF080808);
  static const Color sheetMid = Color(0xFF030303);
  static const Color sheetBottom = Color(0xFF000000);

  // تحكم النبض المستمر (النقطة الخضراء + توهج الذهبي + البريق)
  late final AnimationController _pulseCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  // مفاتيح إعادة التشغيل للدخول المتدرج لكل تبويب
  Key _entranceKey = UniqueKey();

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _selectTab(int i) {
    if (i == _selectedTab) return;
    setState(() {
      _selectedTab = i;
      _entranceKey = UniqueKey(); // يعيد تشغيل أنيميشن الدخول عند تغيير التبويب
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final sheetTopOffset = mq.size.height * 0.30;

    return Positioned(
      top: sheetTopOffset,
      left: 0,
      right: 0,
      bottom: 0,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF101010), Color(0xFF050505), Color(0xFF000000)],
              stops: [0.0, 0.38, 1.0],
            ),
          ),
          child: Stack(
            children: [
              // توهجات خلفية متحركة (Aurora) بسيطة
              Positioned.fill(child: _AuroraBackground(controller: _pulseCtrl)),

              CustomScrollView(
                slivers: [
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 10, bottom: 2),
                      child: Center(child: _Grabber()),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _HeaderDelegate(
                      tabs: _tabs,
                      selectedIndex: _selectedTab,
                      onTabTap: _selectTab,
                      pulse: _pulseCtrl,
                      backgroundColorBuilder: (shrink) => Color.lerp(const Color(0xFF101010), const Color(0xFF050505), shrink)!,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _Podium(key: _entranceKey, pulse: _pulseCtrl),
                  ),
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 2),
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          Colors.white.withOpacity(0),
                          Colors.white.withOpacity(.14),
                          Colors.white.withOpacity(0),
                        ]),
                      ),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _RankRow(rank: index + 4, name: 'سيتم تحديده'),
                      childCount: 23,
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// توهجات خلفية ناعمة متحركة خلف الشيت بالكامل
class _AuroraBackground extends StatelessWidget {
  final Animation<double> controller;
  const _AuroraBackground({required this.controller});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final t = controller.value;
          return Stack(
            children: [
              _blob(-60, null, 10 + t * 14, const Color(0x443F8BFF), top: -60, right: -40),
              _blob(null, -60, 10 - t * 10, const Color(0x444C4CFF), top: 40, left: -60),
              _blob(30, null, 8 + t * 10, const Color(0x3338C9B8), bottom: 60, right: 30, size: 160),
            ],
          );
        },
      ),
    );
  }

  Widget _blob(double? r, double? l, double dy, Color color,
      {double? top, double? bottom, double? right, double? left, double size = 220}) {
    return Positioned(
      top: top,
      bottom: bottom,
      right: right,
      left: left,
      child: Transform.translate(
        offset: Offset(0, dy),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 4,
      decoration: BoxDecoration(color: Colors.white.withOpacity(.35), borderRadius: BorderRadius.circular(4)),
    );
  }
}

/// ===================== الهيدر الثابت (عنوان + شارة مباشر + تبويبات) =====================
class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabTap;
  final Color Function(double shrinkRatio) backgroundColorBuilder;
  final Animation<double> pulse;

  _HeaderDelegate({
    required this.tabs,
    required this.selectedIndex,
    required this.onTabTap,
    required this.backgroundColorBuilder,
    required this.pulse,
  });

  static const double _maxExtentVal = 112;
  static const double _minExtentVal = 96;

  @override
  double get maxExtent => _maxExtentVal;
  @override
  double get minExtent => _minExtentVal;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final shrinkRatio = (shrinkOffset / (_maxExtentVal - _minExtentVal)).clamp(0.0, 1.0);
    return Container(
      color: backgroundColorBuilder(shrinkRatio),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Text(
            'تصنيف المساهمين في الغرفة',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 6),
          _LivePill(pulse: pulse),
          const SizedBox(height: 10),
          _SlidingTabs(tabs: tabs, selectedIndex: selectedIndex, onTabTap: onTabTap),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _HeaderDelegate oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex || oldDelegate.tabs != tabs;
  }
}

class _LivePill extends StatelessWidget {
  final Animation<double> pulse;
  const _LivePill({required this.pulse});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.1), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: pulse,
            builder: (context, _) {
              final v = pulse.value;
              return Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFF38E07A),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF38E07A).withOpacity((1 - v) * .6),
                      blurRadius: 6 * v,
                      spreadRadius: 4 * v,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 5),
          Text('تحديث مباشر', style: TextStyle(color: Colors.white.withOpacity(.65), fontSize: 10.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// تبويبات مع مؤشر أبيض ينزلق بسلاسة بين الخيارات
class _SlidingTabs extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabTap;

  const _SlidingTabs({required this.tabs, required this.selectedIndex, required this.onTabTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final totalWidth = constraints.maxWidth - 8; // padding 4 على كل جهة
      final tabWidth = totalWidth / tabs.length;
      return Container(
        height: 40,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Colors.white.withOpacity(.14), borderRadius: BorderRadius.circular(999)),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              // في RTL أول عنصر (index 0) يكون أقصى اليمين، لذا نحسب من اليمين
              right: selectedIndex * tabWidth,
              top: 0,
              bottom: 0,
              width: tabWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [BoxShadow(color: const Color(0xFF7EDBFF).withOpacity(.20), blurRadius: 14, offset: const Offset(0, 4))],
                ),
              ),
            ),
            Row(
              children: List.generate(tabs.length, (i) {
                final selected = i == selectedIndex;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTabTap(i),
                    child: Center(
                      child: Text(
                        tabs[i],
                        style: TextStyle(
                          color: selected ? const Color(0xFF163A22) : Colors.white.withOpacity(.75),
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      );
    });
  }
}

/// ===================== منصة أفضل 3 (مع دخول متدرج + درجات 3D) =====================
class _Podium extends StatelessWidget {
  final Animation<double> pulse;
  const _Podium({super.key, required this.pulse});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _EnteringCrest(
            delayMs: 200,
            child: _Crest(
              rank: 3,
              width: 96,
              stepHeight: 40,
              colors: const [Color(0xFFFFD6B0), Color(0xFFCF8254), Color(0xFF98502F), Color(0xFF542719)],
              nameColor: const Color(0xFF492316),
            ),
          ),
          const SizedBox(width: 8),
          _EnteringCrest(
            delayMs: 50,
            child: _Crest(
              rank: 1,
              width: 112,
              stepHeight: 66,
              isFirst: true,
              pulse: pulse,
              colors: const [Color(0xFFFFF7D9), Color(0xFFFFD66E), Color(0xFFD99A28), Color(0xFF765016)],
              nameColor: const Color(0xFF583707),
            ),
          ),
          const SizedBox(width: 8),
          _EnteringCrest(
            delayMs: 350,
            child: _Crest(
              rank: 2,
              width: 96,
              stepHeight: 50,
              colors: const [Color(0xFFF4F8FF), Color(0xFFC8D8EB), Color(0xFF829BB8), Color(0xFF354B67)],
              nameColor: const Color(0xFF263A52),
            ),
          ),
        ],
      ),
    );
  }
}

/// غلاف يتحكم بأنيميشن الدخول المتدرج (ظهور + تكبير بسيط) لكل عمود
class _EnteringCrest extends StatefulWidget {
  final Widget child;
  final int delayMs;
  const _EnteringCrest({required this.child, required this.delayMs});

  @override
  State<_EnteringCrest> createState() => _EnteringCrestState();
}

class _EnteringCrestState extends State<_EnteringCrest> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, .12),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// بطاقة الدرع + الدرجة ثلاثية الأبعاد تحتها
class _Crest extends StatelessWidget {
  final int rank;
  final double width;
  final double stepHeight;
  final bool isFirst;
  final List<Color> colors; // [فاتح جدًا, فاتح, غامق, غامق جدًا]
  final Color nameColor;
  final Animation<double>? pulse;

  const _Crest({
    required this.rank,
    required this.width,
    required this.stepHeight,
    required this.colors,
    required this.nameColor,
    this.isFirst = false,
    this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    final height = width * 1.28;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          height: height + (isFirst ? 26 : 0),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              if (isFirst)
                const Positioned(
                  top: 0,
                  child: _CrownPop(),
                ),
              if (isFirst) ...[
                const Positioned(top: 10, left: 2, child: _Sparkle(delayMs: 200)),
                const Positioned(top: 34, right: -6, child: _Sparkle(delayMs: 800)),
              ],
              Positioned(
                bottom: 0,
                child: ClipPath(
                  clipper: _ShieldClipper(),
                  child: Container(
                    width: width,
                    height: height,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: colors,
                        stops: const [0.0, 0.45, 0.78, 1.0],
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(top: height * 0.13),
                      child: Column(
                        children: [
                          _Avatar(isFirst: isFirst, size: width * 0.56, pulse: pulse),
                          SizedBox(height: height * 0.07),
                          Text('سيتم تحديده',
                              style: TextStyle(color: nameColor, fontWeight: FontWeight.w800, fontSize: 9.5)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // الدرجة (step) أسفل الدرع مباشرة
        Transform.translate(
          offset: const Offset(0, -4),
          child: Container(
            width: width * 0.88,
            height: stepHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12), bottom: Radius.circular(5)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [colors[1], colors[3]],
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: Container(
                    height: stepHeight * 0.45,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.white.withOpacity(.38), Colors.white.withOpacity(0)],
                      ),
                    ),
                  ),
                ),
                Text('$rank',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19, shadows: [
                      Shadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1)),
                    ])),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CrownPop extends StatefulWidget {
  const _CrownPop();
  @override
  State<_CrownPop> createState() => _CrownPopState();
}

class _CrownPopState extends State<_CrownPop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
  late final Animation<double> _scale = CurvedAnimation(parent: _c, curve: Curves.elasticOut);

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: const Text('👑', style: TextStyle(fontSize: 27)),
    );
  }
}

class _Sparkle extends StatefulWidget {
  final int delayMs;
  const _Sparkle({required this.delayMs});
  @override
  State<_Sparkle> createState() => _SparkleState();
}

class _SparkleState extends State<_Sparkle> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
        ..repeat();
  late final Animation<double> _opacity = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 1),
  ]).animate(_c);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: const Text('✨', style: TextStyle(fontSize: 11)),
    );
  }
}

class _Avatar extends StatelessWidget {
  final bool isFirst;
  final double size;
  final Animation<double>? pulse;
  const _Avatar({required this.isFirst, required this.size, this.pulse});

  @override
  Widget build(BuildContext context) {
    final core = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF272727),
        shape: BoxShape.circle,
        border: Border.all(color: isFirst ? const Color(0xFFFFF3CF) : Colors.white.withOpacity(.6), width: 3),
      ),
      child: const Icon(Icons.person, color: Colors.white38, size: 20),
    );

    if (!isFirst || pulse == null) return core;

    return SizedBox(
      width: size + 16,
      height: size + 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: pulse!,
            builder: (context, _) {
              final v = pulse!.value;
              return Container(
                width: size + 14 * v,
                height: size + 14 * v,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFFE696).withOpacity(1 - v), width: 1.4),
                ),
              );
            },
          ),
          core,
        ],
      ),
    );
  }
}

/// شكل الدرع (Shield)
class _ShieldClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    path.moveTo(w * 0.50, 0);
    path.lineTo(w * 0.88, h * 0.12);
    path.lineTo(w * 1.00, h * 0.38);
    path.lineTo(w * 0.88, h * 0.78);
    path.lineTo(w * 0.50, h * 1.00);
    path.lineTo(w * 0.12, h * 0.78);
    path.lineTo(w * 0.00, h * 0.38);
    path.lineTo(w * 0.12, h * 0.12);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// ===================== صف واحد في باقي القائمة =====================
class _RankRow extends StatelessWidget {
  final int rank;
  final String name;
  const _RankRow({required this.rank, required this.name});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashColor: Colors.white.withOpacity(.06),
        highlightColor: Colors.white.withOpacity(.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text('$rank',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(.8), fontWeight: FontWeight.bold, fontSize: 13.5)),
              ),
              const SizedBox(width: 10),
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [Color(0xFF454B48), Color(0xFF2A2E2C)]),
                ),
                child: const Icon(Icons.person, color: Colors.white54, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}