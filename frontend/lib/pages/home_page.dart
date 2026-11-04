import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'create_room_page.dart';
import 'room_page.dart';

/// Theme colors kept local so this page can be maintained independently.
class HappyHomeColors {
  static const background = Color(0xFF09080D);
  static const surface = Color(0xFF17131F);
  static const gold = Color(0xFFE8C477);
  static const purple = Color(0xFF9B63D9);
  static const muted = Color(0xFFAAA2B5);
}

class HappyHomeTab extends StatefulWidget {
  const HappyHomeTab({required this.name, required this.accessToken, required this.onDiscover, required this.onSoon});
  final String name;
  final String accessToken;
  final VoidCallback onDiscover;
  final ValueChanged<String> onSoon;

  @override
  State<HappyHomeTab> createState() => HappyHomeTabState();
}

class HappyHomeTabState extends State<HappyHomeTab> {
  final PageController _pageController = PageController();
  String _countryName = 'الدولة';
  int _currentPage = 0;
  Map<String, dynamic>? _myRoom;
  bool _loadingMyRoom = true;
  static const String _apiBase = 'https://happy-live-api.taher616270.workers.dev/api/v1';

  @override
  void initState() {
    super.initState();
    _loadCountry();
    _loadMyRoom();
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

  Future<void> _loadMyRoom() async {
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/rooms/mine'),
        headers: {'Authorization': 'Bearer ${widget.accessToken}'},
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body);
      if (data is Map && data['ok'] == true) {
        final value = data['room'];
        if (!mounted) return;
        setState(() {
          _myRoom = value is Map ? Map<String, dynamic>.from(value) : null;
          _loadingMyRoom = false;
        });
      }
    } catch (_) {
      // The create endpoint is idempotent too, so a temporary lookup failure
      // cannot create a duplicate room.
    } finally {
      if (mounted && _loadingMyRoom) setState(() => _loadingMyRoom = false);
    }
  }

  Future<void> _openMyRoom() async {
    final room = _myRoom;
    if (room != null) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => RoomPage(room: room, accessToken: widget.accessToken),
      ));
      await _loadMyRoom();
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CreateRoomPage(
        accessToken: widget.accessToken,
        onRoomCreated: (createdRoom) {
          if (mounted) setState(() => _myRoom = createdRoom);
        },
      ),
    ));
    await _loadMyRoom();
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
                    style: const TextStyle(color: HappyHomeColors.gold, fontSize: 12, fontWeight: FontWeight.w800))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOriginalHomeContent() => ListView(
    padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
    children: [
      const SizedBox(height: 24),
      MyPartyRoomButton(
        room: _myRoom,
        loading: _loadingMyRoom,
        onTap: _openMyRoom,
      ),
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
class MyPartyRoomButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Map<String, dynamic>? room;
  final bool loading;
  const MyPartyRoomButton({super.key, this.onTap, this.room, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final hasRoom = room != null;
    final imageUrl = (room?['imageUrl'] ?? '').toString();
    final roomName = (room?['name'] ?? '').toString().trim();
    final roomCode = (room?['roomCode'] ?? '').toString();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(19),
            child: Container(
              width: double.infinity,
              height: 86,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF211A31),
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: const Color(0xFFE6C87A).withOpacity(0.52)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: SizedBox(
                      width: 62,
                      height: 62,
                      child: imageUrl.startsWith('https://')
                          ? Image.network(imageUrl, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _roomPlaceholder())
                          : _roomPlaceholder(),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasRoom ? (roomName.isEmpty ? 'غرفتي' : roomName) : (loading ? 'جارٍ تحميل غرفتك...' : 'إنشاء غرفتي'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          hasRoom ? 'غرفتك الخاصة  •  $roomCode' : 'غرفتك تبقى محفوظة دائمًا',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFFB9A9CC), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(hasRoom ? Icons.arrow_back_ios_new_rounded : Icons.add_circle_rounded,
                    color: const Color(0xFFE6C87A), size: 23),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roomPlaceholder() => Container(
    color: const Color(0xFF342546),
    alignment: Alignment.center,
    child: const Icon(Icons.meeting_room_rounded, color: Color(0xFFE6C87A), size: 30),
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

