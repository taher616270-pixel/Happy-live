// ranking_sheet.dart
// نسخة Flutter من شيت "تصنيف المساهمين في الغرفة"
// انسخ هذا الملف داخل مشروع Flutter (مثلاً lib/main.dart) وشغّله مباشرة.
// يحتاج فقط لحزمة Flutter الأساسية (ما يحتاج أي package خارجي).

import 'package:flutter/material.dart';

void main() => runApp(const RankingDemoApp());

class RankingDemoApp extends StatelessWidget {
  const RankingDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      builder: (context, child) {
        // نفرض اتجاه RTL للنصوص العربية
        return Directionality(textDirection: TextDirection.rtl, child: child!);
      },
      home: const LiveRoomMock(),
    );
  }
}

/// ===================== شاشة الخلفية (غرفة البث) =====================
/// خلفية مبسطة تمثل شاشة البث خلف الشيت، فوقها الشيت نفسه.
class LiveRoomMock extends StatelessWidget {
  const LiveRoomMock({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // خلفية الغرفة (تمثيل مبسط لمشهد البث المظلم)
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
                      const SizedBox(height: 10),
                      Row(children: List.generate(4, (i) {
                        return Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Column(children: [
                            const CircleAvatar(radius: 16, backgroundColor: Colors.white12,
                                child: Icon(Icons.chat_bubble_outline, color: Colors.white54, size: 15)),
                            const SizedBox(height: 2),
                            Text('${5 - i}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                          ]),
                        );
                      })),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // الشيت نفسه فوق الخلفية
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

class _RankingSheetState extends State<RankingSheet> {
  int _selectedTab = 0; // 0 = اليومي, 1 = أسبوعي, 2 = شهريا
  final List<String> _tabs = const ['اليومي', 'أسبوعي', 'شهريا'];

  // ألوان الخلفية (مأخوذة من تدرج التصميم الأصلي)
  static const Color sheetTop = Color(0xFF0C8A30);
  static const Color sheetMid = Color(0xFF0A3D24);
  static const Color sheetBottom = Color(0xFF04140F);

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final sheetTopOffset = mq.size.height * 0.30; // نفس موقع بداية الشيت تقريبًا

    return Positioned(
      top: sheetTopOffset,
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [sheetTop, sheetMid, sheetBottom],
            stops: [0.0, 0.32, 0.65],
          ),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          child: CustomScrollView(
            slivers: [
              // شريط صغير للسحب
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 10, bottom: 4),
                  child: Center(
                    child: _Grabber(),
                  ),
                ),
              ),

              // الهيدر الثابت (العنوان + التبويبات)
              SliverPersistentHeader(
                pinned: true,
                delegate: _HeaderDelegate(
                  tabs: _tabs,
                  selectedIndex: _selectedTab,
                  onTabTap: (i) => setState(() => _selectedTab = i),
                  backgroundColorBuilder: (shrink) {
                    // عند التمرير تختفي الخلفية الخضراء الفاتحة ويبقى اللون الغامق
                    return Color.lerp(sheetTop, sheetMid, shrink)!;
                  },
                ),
              ),

              // المنصة (أفضل 3)
              SliverToBoxAdapter(
                child: _Podium(key: ValueKey(_selectedTab)),
              ),

              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                  height: 1,
                  color: Colors.white.withOpacity(.08),
                ),
              ),

              // بقية القائمة من 4 إلى 26
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final rank = index + 4;
                    return _RankRow(rank: rank, name: 'سيتم تحديده');
                  },
                  childCount: 23, // من 4 إلى 26
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
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
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.35),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// ===================== الهيدر الثابت (عنوان + تبويبات) =====================
class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabTap;
  final Color Function(double shrinkRatio) backgroundColorBuilder;

  _HeaderDelegate({
    required this.tabs,
    required this.selectedIndex,
    required this.onTabTap,
    required this.backgroundColorBuilder,
  });

  static const double _maxExtentVal = 92;
  static const double _minExtentVal = 76;

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
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: List.generate(tabs.length, (i) {
                final selected = i == selectedIndex;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onTabTap(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: selected ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        tabs[i],
                        style: TextStyle(
                          color: selected ? const Color(0xFF163A22) : Colors.white.withOpacity(.75),
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _HeaderDelegate oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex || oldDelegate.tabs != tabs;
  }
}

/// ===================== منصة أفضل 3 =====================
class _Podium extends StatelessWidget {
  const _Podium({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Crest(
                rank: 3,
                size: 96,
                colors: const [Color(0xFFF3C9B7), Color(0xFFC07A5F), Color(0xFF5A372C)],
                nameColor: const Color(0xFF5A3A2C),
              ),
              const SizedBox(width: 10),
              _Crest(
                rank: 1,
                size: 110,
                isFirst: true,
                colors: const [Color(0xFFFFE9A8), Color(0xFFD98A4A), Color(0xFF8A5A2A)],
                nameColor: const Color(0xFF7A4A1E),
              ),
              const SizedBox(width: 10),
              _Crest(
                rank: 2,
                size: 96,
                colors: const [Color(0xFFDFE6F5), Color(0xFF7EA3C4), Color(0xFF3A4A5A)],
                nameColor: const Color(0xFF2F4152),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('3', style: TextStyle(color: Colors.white.withOpacity(.55), fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(width: 46),
              const Text('1', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(width: 46),
              Text('2', style: TextStyle(color: Colors.white.withOpacity(.55), fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }
}

/// بطاقة الدرع لكل مركز من المراكز الثلاثة الأولى
class _Crest extends StatelessWidget {
  final int rank;
  final double size;
  final bool isFirst;
  final List<Color> colors; // [فاتح, وسط, غامق]
  final Color nameColor;

  const _Crest({
    required this.rank,
    required this.size,
    required this.colors,
    required this.nameColor,
    this.isFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    final height = size * 1.3;
    return SizedBox(
      width: size,
      height: height + 28,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          if (isFirst)
            const Positioned(
              top: -4,
              child: Text('👑', style: TextStyle(fontSize: 26)),
            ),
          Positioned(
            top: isFirst ? 22 : 0,
            child: ClipPath(
              clipper: _ShieldClipper(),
              child: Container(
                width: size,
                height: height,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.only(top: height * 0.13),
                  child: Column(
                    children: [
                      Container(
                        width: size * 0.58,
                        height: size * 0.58,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2B2B2B),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isFirst ? const Color(0xFFFFE9A8) : Colors.white.withOpacity(.55),
                            width: 3,
                          ),
                        ),
                        child: const Icon(Icons.person, color: Colors.white38, size: 22),
                      ),
                      SizedBox(height: height * 0.08),
                      Text(
                        'سيتم تحديده',
                        style: TextStyle(
                          color: nameColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(.8), width: 2),
                gradient: LinearGradient(colors: [colors[0], colors[1]]),
              ),
              child: Text(
                '$rank',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// شكل الدرع (Shield) المستخدم في بطاقات المراكز الثلاثة
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

/// ===================== صف واحد في باقي القائمة (من 4 إلى 26) =====================
class _RankRow extends StatelessWidget {
  final int rank;
  final String name;

  const _RankRow({required this.rank, required this.name});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(.85), fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(color: Color(0xFF3A3F3D), shape: BoxShape.circle),
            child: const Icon(Icons.person, color: Colors.white54, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}