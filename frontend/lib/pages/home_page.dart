import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Theme colors kept local so this page can be maintained independently.
class HappyHomeColors {
  static const background = Color(0xFF09080D);
  static const surface = Color(0xFF17131F);
  static const gold = Color(0xFFE8C477);
  static const purple = Color(0xFF9B63D9);
  static const muted = Color(0xFFAAA2B5);
}

class HappyHomeTab extends StatefulWidget {
  const HappyHomeTab({required this.name, required this.onDiscover, required this.onSoon});
  final String name;
  final VoidCallback onDiscover;
  final ValueChanged<String> onSoon;

  @override
  State<HappyHomeTab> createState() => HappyHomeTabState();
}

class HappyHomeTabState extends State<HappyHomeTab> {
  final PageController _pageController = PageController();
  String _countryName = 'الدولة';
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _loadCountry();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadCountry() async {
    try {
      final response = await http.get(Uri.https('ipwho.is', '')).timeout(const Duration(seconds: 7));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map && data['success'] != false) {
        final country = (data['country'] ?? '').toString().trim();
        if (mounted && country.isNotEmpty) setState(() => _countryName = country);
      }
    } catch (_) {}
  }

  void _goToPage(int index) {
    if (index < 0 || index > 2) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
    );
  }

  Widget _topButton(int index, IconData icon, String label) {
    final selected = _currentPage == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: selected ? null : 43,
      constraints: BoxConstraints(minWidth: selected ? 104 : 43, maxWidth: selected ? 150 : 43),
      height: 40,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => _goToPage(index),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: selected ? 11 : 0),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0x665F4775)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: HappyHomeColors.gold),
                if (selected) ...[
                  const SizedBox(width: 7),
                  Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: HappyHomeColors.gold, fontSize: 11, fontWeight: FontWeight.w800))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOriginalHomeContent() => ListView(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
    children: [
      const SizedBox(height: 24),
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        decoration: BoxDecoration(color: HappyHomeColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF30263A))),
        child: Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.rectangle, borderRadius: BorderRadius.circular(12), color: const Color(0xFF30233D), border: Border.all(color: HappyHomeColors.purple)),
            child: const Icon(Icons.add_rounded, color: HappyHomeColors.gold, size: 26)),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('غرفة الحفلة الخاصة بي', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
            SizedBox(height: 4), Text('دردش مع أي شخص', style: TextStyle(color: HappyHomeColors.muted, fontSize: 11, height: 1.6)),
          ])),
        ])),
    ],
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
        child: Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _topButton(0, Icons.meeting_room_outlined, 'غرفتي'),
              const SizedBox(width: 5),
              _topButton(1, Icons.explore_outlined, 'استكشف'),
              const SizedBox(width: 5),
              _topButton(2, Icons.public_rounded, _countryName),
            ],
          ),
        ),
      ),
      Expanded(
        child: PageView(
          controller: _pageController,
          onPageChanged: (index) => setState(() => _currentPage = index),
          children: [
            _buildOriginalHomeContent(),
            const SizedBox.expand(),
            const SizedBox.expand(),
          ],
        ),
      ),
    ],
  );
}
class HappySectionTitle extends StatelessWidget {
  const HappySectionTitle({required this.title, required this.subtitle});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
      const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: HappyHomeColors.muted, fontSize: 10)),
    ])),
    const Icon(Icons.more_horiz_rounded, color: HappyHomeColors.muted),
  ]);
}

class HappyShortcut extends StatelessWidget {
  const HappyShortcut({required this.icon, required this.title, required this.tint, required this.onTap});
  final IconData icon; final String title; final Color tint; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(17),
    child: Container(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
      decoration: BoxDecoration(color: HappyHomeColors.surface, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFF30263A))),
      child: Column(children: [Icon(icon, color: tint, size: 26), const SizedBox(height: 8),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))])));
}

