import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'create_room_page.dart';
import 'room_page.dart';

/// Theme colors kept local so this page can be maintained independently.
class HappyHomeColors {
  static const background = Color(0xFFF6F7FB);
  static const surface = Colors.white;
  static const gold = Color(0xFFD9A93C);
  static const purple = Color(0xFFD9A93C);
  static const muted = Color(0xFF9A98AD);
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
      await Navigator.of(context).push(PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, __, ___) => RoomPage(room: room, accessToken: widget.accessToken),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 180),
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

  Future<void> _searchRoomById() async {
    final controller = TextEditingController();
    bool searching = false;
    String? error;
    Map<String, dynamic>? foundRoom;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: HappyHomeColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0x66D9A93C))),
          title: const Text('البحث عن غرفة', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF1E2233), fontSize: 20, letterSpacing: 3, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'أدخل ID الغرفة',
                    hintStyle: const TextStyle(color: HappyHomeColors.muted, fontSize: 14, letterSpacing: 0),
                    filled: true, fillColor: const Color(0xFFFAF6EA),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: Color(0xFFE4E4EC))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: HappyHomeColors.gold)),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: const TextStyle(color: Color(0xFFFF7777), fontSize: 12), textAlign: TextAlign.center),
                ],
                if (foundRoom != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFAF6EA), borderRadius: BorderRadius.circular(13), border: Border.all(color: HappyHomeColors.gold.withOpacity(.5))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text((foundRoom!['name'] ?? 'غرفة صوتية').toString(), textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFF1E2233), fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('ID: ${foundRoom!['roomCode'] ?? controller.text.trim()}', textAlign: TextAlign.right, style: const TextStyle(color: HappyHomeColors.gold, fontSize: 12)),
                    ]),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: searching ? null : () => Navigator.pop(dialogContext), child: const Text('إغلاق', style: TextStyle(color: HappyHomeColors.muted))),
            if (foundRoom != null)
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: HappyHomeColors.gold, foregroundColor: Colors.black),
                onPressed: () {
                  final room = Map<String, dynamic>.from(foundRoom!);
                  Navigator.pop(dialogContext);
                  Navigator.of(this.context).push(PageRouteBuilder<void>(
                    opaque: false, barrierColor: Colors.transparent,
                    pageBuilder: (_, __, ___) => RoomPage(room: room, accessToken: widget.accessToken),
                    transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
                    transitionDuration: const Duration(milliseconds: 180),
                  ));
                },
                child: const Text('دخول الغرفة', style: TextStyle(fontWeight: FontWeight.bold)),
              )
            else
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: HappyHomeColors.purple, foregroundColor: const Color(0xFF5A4630)),
                onPressed: searching ? null : () async {
                  final code = controller.text.trim();
                  if (!RegExp(r'^\d{8}$').hasMatch(code)) {
                    setDialogState(() { error = 'أدخل ID صحيحاً مكوّناً من 8 أرقام'; });
                    return;
                  }
                  setDialogState(() { searching = true; error = null; });
                  try {
                    final response = await http.get(
                      Uri.parse('$_apiBase/rooms/by-code/${Uri.encodeComponent(code)}'),
                      headers: {'Authorization': 'Bearer ${widget.accessToken}'},
                    ).timeout(const Duration(seconds: 10));
                    final data = jsonDecode(response.body);
                    if (response.statusCode == 200 && data is Map && data['ok'] == true && data['room'] is Map) {
                      setDialogState(() { foundRoom = Map<String, dynamic>.from(data['room'] as Map); });
                    } else {
                      setDialogState(() { error = response.statusCode == 404 ? 'لم يتم العثور على غرفة نشطة بهذا ID' : 'تعذر البحث الآن، حاول مرة أخرى'; });
                    }
                  } catch (_) {
                    setDialogState(() { error = 'تعذر الاتصال بالخادم، تحقق من الإنترنت'; });
                  } finally {
                    setDialogState(() { searching = false; });
                  }
                },
                child: searching
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('بحث', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
    controller.dispose();
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
      const SizedBox(height: 14),
      LiveHouseCard(
        title: 'غرف صوتية',
        subtitle: 'اكتشف الأجواء وشارك الجميع',
        coverUrl: '',
        avatarUrls: const [],
        listeners: 0,
        onTap: () => widget.onSoon('غرف صوتية'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    height: double.infinity,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF7EBCB), Color(0xFFFAF6EA), Color(0xFFF6F7FB)],
        stops: [0.0, 0.3, 0.55],
      ),
    ),
    child: Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
        child: Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: Colors.white,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'البحث عن غرفة بواسطة ID',
                  onPressed: _searchRoomById,
                  icon: const Icon(Icons.search_rounded, color: HappyHomeColors.gold, size: 21),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                ),
              ),
              const SizedBox(width: 5),
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
    ),
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
    final roomName = (room?['name'] ?? '').toString().trim();
    final title = hasRoom
        ? (roomName.isEmpty ? 'غرفة الحفلة الخاصة بي' : roomName)
        : 'غرفة الحفلة الخاصة بي';
    final subtitle = hasRoom
        ? 'اضغط لفتح غرفتك'
        : (loading ? 'جارٍ تحميل غرفتك...' : 'دردش مع أي شخص');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: double.infinity,
                height: 74,
                padding: const EdgeInsets.only(left: 16, right: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFF0A62B).withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 92),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              softWrap: true,
                              overflow: TextOverflow.fade,
                              style: const TextStyle(
                                color: Color(0xFF1E2233),
                                fontSize: 15,
                                height: 1.15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF9A98AD),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAEDC8),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFD9A93C),
                          width: 1.8,
                        ),
                      ),
                      child: Icon(
                        hasRoom ? Icons.arrow_forward_ios_rounded : Icons.add,
                        color: const Color(0xFFD9A93C),
                        size: hasRoom ? 15 : 21,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: -15,
              top: -49,
              bottom: -20,
              child: Image.asset(
                'assets/images/boy_headset.png.png',
                width: 105,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ExperimentalFeatureButton extends StatelessWidget {
  const ExperimentalFeatureButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 76,
            width: double.infinity,
            padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFFD9A93C).withOpacity(0.75),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD9A93C).withOpacity(0.14),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'تجريبي',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF6EA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFF0A62B).withOpacity(0.8),
                      width: 1.2,
                    ),
                  ),
                  child: const Icon(
                    Icons.image_outlined,
                    color: Color(0xFFF0A62B),
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HappySectionTitle extends StatelessWidget {
  const HappySectionTitle({required this.title, required this.subtitle});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: Color(0xFF1E2233), fontSize: 16, fontWeight: FontWeight.w900)),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFE4E4EC))),
      child: Column(children: [Icon(icon, color: tint, size: 26), const SizedBox(height: 8),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF1E2233), fontSize: 11, fontWeight: FontWeight.w800))])));
}



const kCardBg = Colors.white;
const kNeon = Color(0xFFD9A93C);
const kNeonLight = Color(0xFFE9C26A);
const kPill = Color(0xFFF6D27A);
const kPillText = Color(0xFF5A4630);
const kSubtitle = Color(0xFF9A98AD);

class LiveHouseCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String coverUrl;
  final List<String> avatarUrls;
  final int listeners;
  final VoidCallback? onTap;

  const LiveHouseCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.avatarUrls,
    required this.listeners,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kCardBg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: kNeon.withAlpha(190), width: 1.4),
            boxShadow: [
              BoxShadow(
                color: kNeon.withAlpha(90),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: kNeonLight, width: 2.5),
                      boxShadow: [
                        BoxShadow(color: kNeon.withAlpha(150), blurRadius: 14),
                      ],
                    ),
                    child: ClipOval(child: _buildCover()),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF1E2233),
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: kSubtitle, fontSize: 11),
                        ),
                        const SizedBox(height: 9),
                        if (avatarUrls.isNotEmpty)
                          SizedBox(
                            height: 27,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              reverse: true,
                              itemCount: math.min(avatarUrls.length, 7),
                              separatorBuilder: (_, __) => const SizedBox(width: 5),
                              itemBuilder: (context, index) => ClipOval(
                                child: Image.network(
                                  avatarUrls[index],
                                  width: 27,
                                  height: 27,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _avatarFallback(),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 27),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: kPill,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$listeners',
                        style: const TextStyle(
                          color: kPillText,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.headphones_rounded, color: kPillText, size: 14),
                      const SizedBox(width: 6),
                      const _Equalizer(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCover() {
    if (coverUrl.trim().isEmpty) {
      return Container(
        color: const Color(0xFFFAF6EA),
        child: const Icon(Icons.graphic_eq_rounded, color: kNeonLight, size: 38),
      );
    }
    return Image.network(
      coverUrl,
      width: 82,
      height: 82,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: const Color(0xFFFAF6EA),
        child: const Icon(Icons.graphic_eq_rounded, color: kNeonLight, size: 38),
      ),
    );
  }

  Widget _avatarFallback() => Container(
    width: 27,
    height: 27,
    color: const Color(0xFFFAF6EA),
    child: const Icon(Icons.person, color: kNeonLight, size: 16),
  );
}

class _Equalizer extends StatefulWidget {
  const _Equalizer();

  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: 19,
          height: 15,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(4, (index) {
              final phase = (_controller.value + index * 0.19) % 1.0;
              final height = 4 + (math.sin(phase * math.pi) * 10);
              return Container(
                width: 3,
                height: height,
                decoration: BoxDecoration(
                  color: kPillText,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
