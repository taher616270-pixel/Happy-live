import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:happy_live/widgets/happy_network_image.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'create_room_page.dart';
import 'room_page.dart';
import 'voice_rooms_page.dart';
import 'public_profile_page.dart';
import 'explore_banner_destination_page.dart';

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
  static const int _exploreFirstPage = 3;
  static const int _countryPage = 9;
  final ScrollController _exploreChipScroll = ScrollController();
  final List<GlobalKey> _exploreChipKeys = List.generate(6, (_) => GlobalKey());
  Timer? _exploreBannerTimer;
  List<Map<String, dynamic>> _exploreBanners = <Map<String, dynamic>>[];
  int _exploreBannerIndex = 0;
  final ValueNotifier<int> _exploreBannerIndexNotifier = ValueNotifier<int>(0);
  int _exploreBannerIntervalSeconds = 4;
  String _countryCode = 'ALL';
  String _countryName = 'الدولة';
  int _currentPage = 0;
  int _lastInnerIndex = 0;
  int _lastExploreIndex = 0;
  Map<String, dynamic>? _myRoom;
  bool _loadingMyRoom = true;
  List<Map<String, dynamic>> _recentRooms = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _recommendedRooms = <Map<String, dynamic>>[];
  bool _loadingRecommendedRooms = false;
  bool _exploreRefreshInFlight = false;
  String? _recommendedRoomsError;
  bool _loadingRecentRooms = false;
  String? _recentRoomsError;
  bool _myRoomLookupInFlight = false;
  bool _myRoomRetryScheduled = false;
  static const String _apiBase = 'https://happy-live-api.taher616270.workers.dev/api/v1';

  // The access token is an opaque, account-specific session key. Hash it so
  // each signed-in account gets its own small local room cache without storing
  // the token as a preference key.
  String get _myRoomCacheKey {
    var hash = 0;
    for (final unit in widget.accessToken.codeUnits) {
      hash = ((hash << 5) - hash + unit) & 0x7fffffff;
    }
    return 'happy_live_my_room_v1_${hash.toRadixString(16)}';
  }

  Future<void> _saveMyRoomCache(Map<String, dynamic> room) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_myRoomCacheKey, jsonEncode(room));
    } catch (_) {
      // The server remains the source of truth if local storage is unavailable.
    }
  }

  void _rememberMyRoom(Map<String, dynamic> room) {
    if (mounted) {
      setState(() {
        _myRoom = Map<String, dynamic>.from(room);
        _loadingMyRoom = false;
      });
    }
    _saveMyRoomCache(room);
  }

  @override
  void initState() {
    super.initState();
    _loadCountry();
    _loadMyRoom();
    _loadRecentRooms();
    _loadRecommendedRooms();
    _loadExploreBanners();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _exploreChipScroll.dispose();
    _exploreBannerIndexNotifier.dispose();
    _exploreBannerTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCountry() async {
    try {
      final response = await http
          .get(Uri.https('ipwho.is', ''))
          .timeout(const Duration(seconds: 7));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] != false) {
        final country = (data['country'] ?? '').toString().trim();
        final countryCode =
            (data['country_code'] ?? '').toString().trim().toUpperCase();
        if (mounted && country.isNotEmpty) {
          setState(() {
            _countryName = country;
            if (RegExp(r'^[A-Z]{2}$').hasMatch(countryCode)) {
              _countryCode = countryCode;
            }
          });
          await _loadExploreBanners();
        }
      }
    } catch (_) {}
  }

  Future<void> _loadRecentRooms() async {
    if (_loadingRecentRooms || widget.accessToken.isEmpty) return;
    if (mounted) setState(() { _loadingRecentRooms = true; _recentRoomsError = null; });
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/rooms/recent'),
        headers: {'Authorization': 'Bearer ${widget.accessToken}'},
      ).timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map && data['ok'] == true && data['rooms'] is List) {
        final rooms = (data['rooms'] as List).whereType<Map>()
            .map((room) => Map<String, dynamic>.from(room)).toList();
        if (mounted) setState(() { _recentRooms = rooms; _recentRoomsError = null; });
      } else {
        if (mounted) setState(() => _recentRoomsError = 'تعذر تحميل الغرف التي زرتها');
      }
    } catch (_) {
      if (mounted) setState(() => _recentRoomsError = 'تحقق من اتصال الإنترنت ثم حاول التحديث');
    } finally {
      if (mounted) setState(() => _loadingRecentRooms = false);
    }
  }

  Future<List<Map<String, dynamic>>?> _fetchRecommendedRooms() async {
    if (widget.accessToken.isEmpty) return null;
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/rooms/recommended'),
        headers: {'Authorization': 'Bearer ${widget.accessToken}'},
      ).timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data is! Map ||
          data['ok'] != true || data['rooms'] is! List) return null;
      return (data['rooms'] as List).whereType<Map>()
          .map((room) => Map<String, dynamic>.from(room)).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadRecommendedRooms({bool force = false}) async {
    if ((_loadingRecommendedRooms && !force) || widget.accessToken.isEmpty) return;
    if (!force && _recommendedRooms.isNotEmpty) return;
    if (mounted) setState(() {
      _loadingRecommendedRooms = true;
      _recommendedRoomsError = null;
    });
    final rooms = await _fetchRecommendedRooms();
    if (!mounted) return;
    setState(() {
      if (rooms != null) {
        _recommendedRooms = rooms;
        _recommendedRoomsError = null;
      } else if (_recommendedRooms.isEmpty) {
        _recommendedRoomsError = 'تعذر تحميل الغرف الموصى بها';
      }
      _loadingRecommendedRooms = false;
    });
  }

  Future<List<Map<String, dynamic>>?> _fetchExploreBanners() async {
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/explore/banners?country=${Uri.encodeQueryComponent(_countryCode)}'),
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data is! Map || data['ok'] != true) return null;
      return data['banners'] is List
          ? (data['banners'] as List).whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where((item) => (item['imageUrl'] ?? '').toString().startsWith('https://'))
              .toList()
          : <Map<String, dynamic>>[];
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadExploreBanners() async {
    final banners = await _fetchExploreBanners();
    if (!mounted || banners == null) return;
    final oldUrl = _exploreBanners.isEmpty ? '' :
        (_exploreBanners[_exploreBannerIndex.clamp(0, _exploreBanners.length - 1)]['imageUrl'] ?? '').toString();
    final found = banners.indexWhere((item) => (item['imageUrl'] ?? '').toString() == oldUrl);
    setState(() {
      _exploreBanners = banners;
      _exploreBannerIndex = found >= 0 ? found : 0;
    });
    _exploreBannerIndexNotifier.value = _exploreBannerIndex;
    _restartExploreBannerTimer();
  }

  Future<void> refreshExplorePage() async {
    if (!mounted || _currentPage < _exploreFirstPage || _currentPage > 8 ||
        _exploreRefreshInFlight) return;
    _exploreRefreshInFlight = true;
    try {
      final results = await Future.wait<dynamic>([
        _fetchExploreBanners(),
        _fetchRecommendedRooms(),
      ]);
      if (!mounted) return;
      final banners = results[0] as List<Map<String, dynamic>>?;
      final rooms = results[1] as List<Map<String, dynamic>>?;
      final oldUrl = _exploreBanners.isEmpty ? '' :
          (_exploreBanners[_exploreBannerIndex.clamp(0, _exploreBanners.length - 1)]['imageUrl'] ?? '').toString();
      final found = banners?.indexWhere((item) => (item['imageUrl'] ?? '').toString() == oldUrl);
      // Replace both feeds in one commit; retain cached content on endpoint errors.
      setState(() {
        if (banners != null) {
          _exploreBanners = banners;
          _exploreBannerIndex = found != null && found >= 0 ? found : 0;
        }
        if (rooms != null) {
          _recommendedRooms = rooms;
          _recommendedRoomsError = null;
        }
      });
      if (banners != null) {
        _exploreBannerIndexNotifier.value = _exploreBannerIndex;
        _restartExploreBannerTimer();
      }
    } finally {
      _exploreRefreshInFlight = false;
    }
  }

  Widget _homeRefreshWrapper(Widget child) => child;

  Future<void> _openRecommendedRoom(Map<String, dynamic> room) async {
    if ((room['status'] ?? 'active').toString() != 'active') return;
    await Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      pageBuilder: (_, __, ___) =>
          RoomPage(room: room, accessToken: widget.accessToken),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 180),
    ));
    if (mounted) _loadRecommendedRooms(force: true);
  }

  Future<void> _openRecentRoom(Map<String, dynamic> room) async {
    await Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      pageBuilder: (_, __, ___) => RoomPage(room: room, accessToken: widget.accessToken),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 180),
    ));
    if (mounted) _loadRecentRooms();
  }

  Future<void> _loadMyRoom() async {
    if (_myRoomLookupInFlight) return;
    _myRoomLookupInFlight = true;

    try {
      // Read the last confirmed room first. This keeps the create action hidden
      // immediately on weak/offline connections after a room was created.
      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString(_myRoomCacheKey);
        if (cached != null && cached.isNotEmpty) {
          final decoded = jsonDecode(cached);
          if (decoded is Map && decoded['id'] != null && mounted) {
            setState(() {
              _myRoom = Map<String, dynamic>.from(decoded);
              _loadingMyRoom = false;
            });
          }
        }
      } catch (_) {}

      final response = await http.get(
        Uri.parse('$_apiBase/rooms/mine'),
        headers: {'Authorization': 'Bearer ${widget.accessToken}'},
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw Exception('my_room_lookup_failed');
      }

      final data = jsonDecode(response.body);
      if (data is! Map || data['ok'] != true) {
        throw Exception('my_room_lookup_invalid_response');
      }

      final value = data['room'];
      if (value is Map && value['id'] != null) {
        final room = Map<String, dynamic>.from(value);
        _rememberMyRoom(room);
      } else if (_myRoom == null && mounted) {
        // Only show the create action after the server positively confirms
        // that this account has never created a room.
        setState(() => _loadingMyRoom = false);
      } else if (mounted) {
        // A cached permanent room must never be forgotten because of a stale
        // or inconsistent response.
        setState(() => _loadingMyRoom = false);
      }
    } catch (_) {
      // If we cannot confirm the account's room state, do not show a create
      // action that could be mistaken for permission to create another room.
      if (_myRoom == null && mounted) {
        setState(() => _loadingMyRoom = true);
        if (!_myRoomRetryScheduled) {
          _myRoomRetryScheduled = true;
          Future<void>.delayed(const Duration(seconds: 5), () {
            _myRoomRetryScheduled = false;
            if (mounted) _loadMyRoom();
          });
        }
      }
    } finally {
      _myRoomLookupInFlight = false;
    }
  }

  Future<void> _openMyRoom() async {
    if (_loadingMyRoom) {
      await _loadMyRoom();
      return;
    }
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
        onRoomCreated: _rememberMyRoom,
      ),
    ));
    await _loadMyRoom();
  }

  Future<void> _searchUserById() async {
    final controller = TextEditingController();
    bool searching = false;
    String? error;
    Map<String, dynamic>? foundUser;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: HappyHomeColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0x66D9A93C)),
          ),
          title: const Text('البحث عن شخص', textAlign: TextAlign.right,
            style: TextStyle(color: Color(0xFF1E2233), fontWeight: FontWeight.w800)),
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('اكتب ID المستخدم للوصول إلى ملفه الشخصي',
                textAlign: TextAlign.center,
                style: TextStyle(color: HappyHomeColors.muted, fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                controller: controller, keyboardType: TextInputType.number,
                maxLength: 8, textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Color(0xFF1E2233), fontSize: 20,
                  letterSpacing: 3, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  counterText: '', hintText: 'أدخل ID الشخص',
                  filled: true, fillColor: const Color(0xFFFAF6EA),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
                    borderSide: const BorderSide(color: Color(0xFFE4E4EC))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
                    borderSide: const BorderSide(color: HappyHomeColors.gold)),
                ),
              ),
              if (error != null) Text(error!, textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFD9534F), fontSize: 12)),
              if (foundUser != null) ...[
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: HappyNetworkAvatar(
                    url: (foundUser!['avatarUrl'] ?? '').toString(),
                    size: 40,
                    backgroundColor: const Color(0xFFEFE3C7),
                    fallback: const Icon(Icons.person, color: HappyHomeColors.gold),
                  ),
                  title: Text((foundUser!['name'] ?? 'مستخدم').toString(),
                    style: const TextStyle(color: Color(0xFF1E2233), fontWeight: FontWeight.bold)),
                  subtitle: Text('ID: ' + (foundUser!['userCode'] ?? controller.text).toString(),
                    style: const TextStyle(color: HappyHomeColors.gold)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15,
                    color: HappyHomeColors.gold),
                  onTap: () {
                    final user = Map<String, dynamic>.from(foundUser!);
                    Navigator.pop(dialogContext);
                    Navigator.of(this.context).push(MaterialPageRoute<void>(
                      builder: (_) => PublicProfilePage(
                        name: (user['name'] ?? 'مستخدم').toString(),
                        userId: (user['id'] ?? '').toString(),
                        accessToken: widget.accessToken,
                        userCode: (user['userCode'] ?? '').toString(),
                        photoUrl: (user['avatarUrl'] ?? '').toString(),
                      ),
                    ));
                  },
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: searching ? null : () => Navigator.pop(dialogContext),
              child: const Text('إغلاق')),
            if (foundUser == null) ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: HappyHomeColors.gold,
                foregroundColor: Colors.black),
              onPressed: searching ? null : () async {
                final code = controller.text.trim();
                if (!RegExp(r'^\d{8}$').hasMatch(code)) {
                  setDialogState(() => error = 'أدخل ID صحيحاً مكوّناً من 8 أرقام');
                  return;
                }
                setDialogState(() { searching = true; error = null; });
                try {
                  final response = await http.get(
                    Uri.parse(_apiBase + '/users/by-code/' + Uri.encodeComponent(code)),
                    headers: {'Authorization': 'Bearer ' + widget.accessToken},
                  ).timeout(const Duration(seconds: 10));
                  final data = jsonDecode(response.body);
                  if (response.statusCode == 200 && data is Map &&
                      data['ok'] == true && data['user'] is Map) {
                    setDialogState(() => foundUser =
                      Map<String, dynamic>.from(data['user'] as Map));
                  } else {
                    setDialogState(() => error = response.statusCode == 404
                      ? 'لم يتم العثور على مستخدم بهذا ID'
                      : 'تعذر البحث الآن، حاول مرة أخرى');
                  }
                } catch (_) {
                  setDialogState(() => error = 'تعذر الاتصال بالخادم، تحقق من الإنترنت');
                } finally {
                  setDialogState(() => searching = false);
                }
              },
              child: searching
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('بحث'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  void _goToPage(int index) {
    final target = index == 0
        ? _lastInnerIndex
        : index == 3
            ? _exploreFirstPage + _lastExploreIndex
            : index == 2
                ? _countryPage
                : -1;
    if (target < 0 || !_pageController.hasClients) return;
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
    );
  }

  Widget _topButton(int index, IconData icon, String label) {
    final selected = (index == 0 && _currentPage <= 2) ||
        (index == 3 && _currentPage >= 3 && _currentPage <= 8) ||
        (index == 2 && _currentPage == _countryPage);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: selected ? null : 43,
      constraints: BoxConstraints(minWidth: selected ? 104 : 43, maxWidth: selected ? 150 : 43),
      height: 40,
      child: Material(
        color: Colors.transparent,
        child: InkWell(          borderRadius: BorderRadius.circular(13),
          onTap: () => _goToPage(index),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: selected ? 11 : 0),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0xFFE4E4EC)),
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

  Widget _buildMyRoomsPage(int innerIndex) => Directionality(
    textDirection: TextDirection.rtl,
    child: Padding(
      padding: const EdgeInsets.only(top: 8),
      child: innerIndex == 2
          ? _buildRecentRoomsContent()
          : ListView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 180,
                  child: _buildMyRoomsTabContent(
                    innerIndex == 0
                        ? 'لا توجد غرف تتابعها حالياً'
                        : 'لا توجد غرف للانضمام إليها حالياً',
                  ),
                ),
              ],
            ),
    ),
  );

  Widget _buildRecentRoomsContent() {
    if (_loadingRecentRooms && _recentRooms.isEmpty) {
      return const Center(child: _FiveBarRefreshAnimation());
    }
    if (_recentRoomsError != null && _recentRooms.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_recentRoomsError!, textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF9A98AD), fontSize: 11)),
        TextButton(onPressed: refreshExplorePage,
          child: const Text('إعادة المحاولة', style: TextStyle(color: HappyHomeColors.gold, fontSize: 11))),
      ]));
    }
    if (_recentRooms.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        children: const [
          SizedBox(height: 90),
          Center(
            child: Text(
              'لا توجد غرف زرتها مؤخراً',
              style: TextStyle(color: Color(0xFF9A98AD), fontSize: 12),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      key: const PageStorageKey<String>('happy-live-recent-rooms-scroll'),
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 0),
      itemCount: _recentRooms.length,
      separatorBuilder: (_, __) => const SizedBox(height: 7),
      itemBuilder: (context, index) {
        final room = _recentRooms[index];
        final name = (room['name'] ?? 'غرفة صوتية').toString();
        final announcement = (room['announcement'] ?? room['description'] ?? '').toString().trim();
        final image = (room['imageUrl'] ?? '').toString();
        final status = (room['status'] ?? 'active').toString();
        final level = (room['experienceLevel'] ?? 1) is num
            ? (room['experienceLevel'] as num).toInt() : 1;
        final membersCount = (room['membersCount'] ?? room['members_count'] ?? 0) is num
            ? ((room['membersCount'] ?? room['members_count'] ?? 0) as num).toInt()
            : int.tryParse((room['membersCount'] ?? room['members_count'] ?? '0').toString()) ?? 0;
        return SizedBox(
          width: double.infinity,
          child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          child: InkWell(
            borderRadius: BorderRadius.circular(17),
            onTap: status == 'active' ? () => _openRecentRoom(room) : null,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x66D9A93C), width: 1.2),
                boxShadow: const [BoxShadow(color: Color(0x0AD9A93C), blurRadius: 8, offset: Offset(0, 2))],
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: SizedBox(width: 66, height: 66,
                    child: image.startsWith('https://')
                      ? HappyNetworkImage(image, width: 54, height: 54, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _recentRoomPlaceholder())
                      : _recentRoomPlaceholder()),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF1E2233), fontSize: 14, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 5),
                    Text(announcement.isEmpty ? 'لا يوجد إعلان للغرفة' : announcement,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: HappyHomeColors.muted, fontSize: 11, height: 1.25)),
                    const SizedBox(height: 7),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3D5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFD9A93C).withOpacity(0.65)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.workspace_premium_rounded, size: 13, color: HappyHomeColors.gold),
                          const SizedBox(width: 4),
                          Text('Lv.$level', style: const TextStyle(color: Color(0xFF8A6420), fontSize: 10, fontWeight: FontWeight.w900)),
                        ]),
                      ),
                    ),
                  ],
                )),
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3D5),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0x66D9A93C)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const _RoomMemberWave(count: 3),
                    const SizedBox(width: 4),
                    Text('$membersCount',
                      style: const TextStyle(color: Color(0xFF8A6420), fontSize: 11, fontWeight: FontWeight.w900)),
                  ]),
                ),
              ]),
            ),
          ),
          ),
        );
      },
    );
  }

  Widget _recentRoomPlaceholder() => Container(
    color: const Color(0xFFFAF6EA),
    alignment: Alignment.center,
    child: const Icon(Icons.graphic_eq_rounded, color: HappyHomeColors.gold, size: 22),
  );

  void _restartExploreBannerTimer() {
    _exploreBannerTimer?.cancel();
    if (!mounted || _exploreBanners.length < 2) return;
    _exploreBannerTimer = Timer.periodic(
      Duration(seconds: _exploreBannerIntervalSeconds),
      (_) {
        if (!mounted || _exploreBanners.length < 2) return;
        _exploreBannerIndex = (_exploreBannerIndex + 1) % _exploreBanners.length;
        _exploreBannerIndexNotifier.value = _exploreBannerIndex;
      },
    );
  }

  void _openExploreBanner(Map<String, dynamic> banner) {
    final type = (banner['destinationType'] ?? 'none').toString();
    if (type == 'none') return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ExploreBannerDestinationPage(banner: banner),
    ));
  }

  Widget _buildExploreBanner() {
    return ValueListenableBuilder<int>(
      valueListenable: _exploreBannerIndexNotifier,
      builder: (context, bannerIndex, _) {
        final hasBanners = _exploreBanners.isNotEmpty;
        final safeIndex = hasBanners ? bannerIndex.clamp(0, _exploreBanners.length - 1).toInt() : 0;
        final banner = hasBanners ? _exploreBanners[safeIndex] : null;
        return AspectRatio(
          aspectRatio: 4.1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (banner != null)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openExploreBanner(banner),
                    child: CachedNetworkImage(
                      imageUrl: (banner['imageUrl'] ?? '').toString(),
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder: (_, __) => _exploreBannerFallback(),
                      errorWidget: (_, __, ___) => _exploreBannerFallback(),
                    ),
                  )
                else
                  _exploreBannerFallback(),
                if (_exploreBanners.length > 1)
                  Positioned(
                    left: 0, right: 0, bottom: 6,
                    child: IgnorePointer(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_exploreBanners.length, (index) {
                          final selected = index == safeIndex;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: selected ? 15 : 6, height: 6,
                            decoration: BoxDecoration(
                              color: selected ? HappyHomeColors.gold : const Color(0xFFCEC8BB),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _exploreBannerFallback() => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFFAF6EA),
      border: Border.all(color: const Color(0xFFE8E4DA)),
      borderRadius: BorderRadius.circular(14),
    ),
  );

  Widget _buildSmallExploreBanner(int index) {
    if (index >= _exploreBanners.length) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE8E4DA)),
          borderRadius: BorderRadius.circular(14),
        ),
      );
    }
    final banner = _exploreBanners[index];
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openExploreBanner(banner),
        child: CachedNetworkImage(
          imageUrl: (banner['imageUrl'] ?? '').toString(),
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholder: (_, __) => _exploreBannerFallback(),
          errorWidget: (_, __, ___) => _exploreBannerFallback(),
        ),
      ),
    );
  }

  List<Widget> _buildRecommendedRoomsSlivers() {
    if (_loadingRecommendedRooms && _recommendedRooms.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: _FiveBarRefreshAnimation()),
        ),
      ];
    }
    if (_recommendedRoomsError != null && _recommendedRooms.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_recommendedRoomsError!, textAlign: TextAlign.center,
                  style: const TextStyle(color: HappyHomeColors.muted, fontSize: 11)),
                TextButton(
                  onPressed: _loadRecentRooms,
                  child: const Text('إعادة المحاولة',
                    style: TextStyle(color: HappyHomeColors.gold, fontSize: 11)),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    if (_recommendedRooms.isEmpty) {
      return const [
        SliverToBoxAdapter(child: SizedBox(height: 90)),
        SliverToBoxAdapter(
          child: Center(
            child: Text(
              'لا توجد غرف نشطة حالياً',
              style: TextStyle(color: HappyHomeColors.muted, fontSize: 12),
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 16),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final room = _recommendedRooms[index];
              return _RecommendedRoomCard(
                room: room,
                onTap: () => _openRecommendedRoom(room),
              );
            },
            childCount: _recommendedRooms.length,
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
        ),
      ),
    ];
  }

  Widget _buildExploreHeader() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 0),
      child: Column(
        children: [
          _buildExploreBanner(),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SizedBox(height: 82, child: _buildSmallExploreBanner(1))),
              const SizedBox(width: 8),
              Expanded(child: SizedBox(height: 82, child: _buildSmallExploreBanner(2))),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildExploreTabs() {
    const labels = ['توصية', 'لعبة', 'مبارزة', 'البث المباشر', 'لعبة الفائز السوبر', 'الفيديو'];
    return SizedBox(
      height: 46,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _exploreChipScroll,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: List.generate(labels.length, (index) {
              final selected = _currentPage == _exploreFirstPage + index;
              return Padding(
                padding: EdgeInsetsDirectional.only(end: index == labels.length - 1 ? 0 : 8),
                child: GestureDetector(
                  key: _exploreChipKeys[index],
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _goToAbsolutePage(_exploreFirstPage + index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFF1AD3BB) : const Color(0xFFF3F5F4),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      labels[index],
                      style: TextStyle(
                        color: selected ? Colors.white : const Color(0xFF858D8A),
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildExploreTabSlivers(int index) {
    if (index == 0) return _buildRecommendedRoomsSlivers();
    final title = switch (index) {
      1 => 'لعبة',
      2 => 'مبارزة',
      3 => 'البث المباشر',
      4 => 'لعبة الفائز السوبر',
      _ => 'الفيديو',
    };
    return [
      SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF9A98AD),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ];
  }

  // Each swipe page owns its complete header and content. This keeps the
  // explore banner/actions/tabs moving as one full page instead of swapping
  // a separate header above a shortened PageView viewport.
  Widget _buildMyRoomsHomePage(int tabIndex) {
    return Column(
      children: [
        const SizedBox(height: 24),
        MyPartyRoomButton(
          room: _myRoom,
          loading: _loadingMyRoom,
          onTap: _openMyRoom,
        ),
        const SizedBox(height: 14),
        _buildMyRoomsTabs(),
        const SizedBox(height: 8),
        Expanded(child: _buildMyRoomsPage(tabIndex)),
      ],
    );
  }

  Widget _buildExploreHomePage(int tabIndex) {
    // A single scroll position owns the entire Explore page. Tab content is
    // rendered as slivers (never as a nested ListView/GridView), so a
    // downward drag begun over any tab content moves the banner, action
    // cards, tabs and content together and reaches the page refresh at top.
    return CustomScrollView(
      key: const PageStorageKey<String>('happy-live-explore-scroll'),
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        CupertinoSliverRefreshControl(
          onRefresh: refreshExplorePage,
          refreshTriggerPullDistance: 82,
          refreshIndicatorExtent: 48,
          builder: (context, mode, pulledExtent, triggerDistance, indicatorExtent) {
            final visible = mode == RefreshIndicatorMode.drag ||
                mode == RefreshIndicatorMode.armed ||
                mode == RefreshIndicatorMode.refresh;
            return Container(
              color: Colors.white,
              alignment: Alignment.center,
              child: visible
                  ? const SizedBox(
                      width: 17, height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        valueColor: AlwaysStoppedAnimation<Color>(HappyHomeColors.gold),
                      ),
                    )
                  : const SizedBox.shrink(),
            );
          },
        ),
        SliverAppBar(
          primary: false,
          toolbarHeight: 0,
          collapsedHeight: 0,
          expandedHeight: 204,
          pinned: false,
          floating: false,
          automaticallyImplyLeading: false,
          backgroundColor: HappyHomeColors.background,
          flexibleSpace: FlexibleSpaceBar(background: _buildExploreHeader()),
        ),
        SliverToBoxAdapter(child: _buildExploreTabs()),
        ..._buildExploreTabSlivers(tabIndex),
      ],
    );
  }

  void _goToAbsolutePage(int page) {
    if (!_pageController.hasClients || page < 0 || page > _countryPage) return;
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
    );
  }

  // The country section is a separate top-level page in the same swipe sequence.
  // Its content is intentionally limited to the currently detected country until
  // a country-specific room feed is available from the API.
  Widget _buildCountryPage() {
    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      key: const PageStorageKey<String>('happy-live-country-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0x66D9A93C)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(
                  color: Color(0x1FD9A93C),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.public_rounded,
                    color: HappyHomeColors.gold, size: 30),
              ),
              const SizedBox(height: 12),
              const Text(
                'الدولة',
                style: TextStyle(
                  color: Color(0xFF1E2233),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _countryName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: HappyHomeColors.gold,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMyRoomsTabContent(String emptyMessage) {
    return Center(
      child: Text(
        emptyMessage,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF9A98AD), fontSize: 12),
      ),
    );
  }

  Widget _buildMyRoomsTabs() {
    const labels = ['متابعة', 'انضم', 'مؤخراً'];
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 18, end: 18),
      child: SizedBox(
        height: 46,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(labels.length, (index) {
                final selected = _currentPage == index;
                return Padding(
                  padding: EdgeInsetsDirectional.only(end: index == labels.length - 1 ? 0 : 8),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _goToAbsolutePage(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFF1AD3BB) : const Color(0xFFF3F5F4),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 180),
                        style: TextStyle(
                          color: selected ? Colors.white : const Color(0xFF858D8A),
                          fontSize: 13.5,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                        child: Text(labels[index]),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }


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
          child: SizedBox(
            width: double.infinity,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _topButton(0, Icons.meeting_room_outlined, 'غرفتي'),
                      const SizedBox(width: 5),
                      _topButton(3, Icons.explore_outlined, 'استكشف'),
                      const SizedBox(width: 5),
                      _topButton(2, Icons.public_rounded, _countryName),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'البحث عن شخص بواسطة ID',
                      onPressed: _searchUserById,
                      icon: const Icon(Icons.search_rounded, color: HappyHomeColors.gold, size: 21),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _homeRefreshWrapper(
            Directionality(
              textDirection: TextDirection.ltr,
              child: PageView(
                key: const PageStorageKey<String>('happy-live-unified-home-pager'),
                controller: _pageController,
                reverse: true,
                // Disable horizontal swiping across all home sections.
                // Vertical scrolling inside each page remains unchanged.
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                    if (index <= 2) {
                      _lastInnerIndex = index;
                    } else if (index >= _exploreFirstPage && index <= 8) {
                      _lastExploreIndex = index - _exploreFirstPage;
                    }
                  });
                  if (index >= _exploreFirstPage && index <= 8) {
                    final chipIndex = index - _exploreFirstPage;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted || _exploreChipKeys[chipIndex].currentContext == null) return;
                      Scrollable.ensureVisible(
                        _exploreChipKeys[chipIndex].currentContext!,
                        alignment: 0.5,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                      );
                    });
                  }
                  if (index == _exploreFirstPage) {
                    _loadRecommendedRooms(force: true);
                  }
                },
                children: [
                  for (var i = 0; i < 3; i++)
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: _buildMyRoomsHomePage(i),
                    ),
                  for (var i = 0; i < 6; i++)
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: _buildExploreHomePage(i),
                    ),
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: Column(
                      children: [
                        Expanded(child: _buildCountryPage()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
      ],
    ),
  );
}
class _RecommendedRoomCard extends StatelessWidget {
  const _RecommendedRoomCard({
    required this.room,
    required this.onTap,
  });

  final Map<String, dynamic> room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = (room['name'] ?? 'غرفة صوتية').toString();
    final country = (room['countryName'] ??
            room['country_name'] ??
            room['country'] ??
            room['countryLabel'] ??
            room['country_label'] ??
            '')
        .toString()
        .trim();
    final image = (room['imageUrl'] ?? '').toString();
    final membersValue = room['membersCount'] ?? room['members_count'] ?? 0;
    final membersCount = membersValue is num
        ? membersValue.toInt()
        : int.tryParse(membersValue.toString()) ?? 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      image.startsWith('https://')
                          ? CachedNetworkImage(
                              imageUrl: image,
                              fit: BoxFit.cover,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              placeholder: (_, __) => _roomFallback(),
                              errorWidget: (_, __, ___) => _roomFallback(),
                            )
                          : _roomFallback(),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsetsDirectional.fromSTEB(8, 15, 8, 7),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xCC000000)],
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              const _RoomMemberWave(count: 3),
                              const SizedBox(width: 6),
                              Text(
                                '$membersCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF1E2233),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (country.isNotEmpty) ...[
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        country,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: HappyHomeColors.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roomFallback() => Container(
        color: const Color(0xFFFAF6EA),
        alignment: Alignment.center,
        child: const Icon(
          Icons.graphic_eq_rounded,
          color: HappyHomeColors.gold,
          size: 28,
        ),
      );
}

class _ExploreTabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ExploreTabsHeaderDelegate({
    required this.height,
    required this.child,
  });

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: const Color(0xFFFAF6EA),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _ExploreTabsHeaderDelegate oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}

class _ExploreTabPlaceholder extends StatelessWidget {
  final String title;
  const _ExploreTabPlaceholder(this.title);

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: PageStorageKey<String>('happy-live-explore-placeholder-$title'),
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF9A98AD),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class MyPartyRoomButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Map<String, dynamic>? room;
  final bool loading;
  const MyPartyRoomButton({super.key, this.onTap, this.room, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final hasRoom = room != null;
    final roomCoverUrl = (room?['imageUrl'] ??
            room?['image_url'] ??
            room?['coverUrl'] ??
            room?['cover_url'] ??
            '')
        .toString()
        .trim();
    final roomName = (room?['name'] ?? '').toString().trim();
    final title = hasRoom
        ? (roomName.isEmpty ? 'غرفة الحفلة الخاصة بي' : roomName)
        : 'غرفة الحفلة الخاصة بي';
    final subtitle = hasRoom
        ? 'اضغط لفتح غرفتك'
        : (loading ? 'جارٍ التحقق من غرفتك...' : 'دردش مع أي شخص');

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
                      child: loading
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFD9A93C),
                              ),
                            )
                          : Icon(
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
              right: 8,
              top: 8,
              bottom: 8,
              child: hasRoom
                  ? SizedBox(
                      width: 58,
                      height: 58,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: roomCoverUrl.startsWith('https://')
                            ? HappyNetworkImage(
                                roomCoverUrl,
                                width: 58,
                                height: 58,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: const Color(0xFFFAEDC8),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.meeting_room_rounded,
                                    color: Color(0xFFD9A93C),
                                    size: 34,
                                  ),
                                ),
                              )
                            : Container(
                                color: const Color(0xFFFAEDC8),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.meeting_room_rounded,
                                  color: Color(0xFFD9A93C),
                                  size: 34,
                                ),
                              ),
                      ),
                    )
                  : Image.asset(
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
                      color: Color(0xFF1E2233),
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
                              physics: const NeverScrollableScrollPhysics(),
                              reverse: true,
                              itemCount: math.min(avatarUrls.length, 7),
                              separatorBuilder: (_, __) => const SizedBox(width: 5),
                              itemBuilder: (context, index) => ClipOval(
                                child: HappyNetworkImage(
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
                      _RoomMemberWave(),
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
    return HappyNetworkImage(
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


class _FiveBarRefreshAnimation extends StatefulWidget {
  const _FiveBarRefreshAnimation();

  @override
  State<_FiveBarRefreshAnimation> createState() => _FiveBarRefreshAnimationState();
}

class _FiveBarRefreshAnimationState extends State<_FiveBarRefreshAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const heights = [9.0, 15.0, 21.0, 15.0, 9.0];
    const colors = [
      Color(0xFFD9A93C),
      Color(0xFFE8C978),
      Color(0xFFFFF3D6),
      Color(0xFFE8C978),
      Color(0xFFD9A93C),
    ];
    return AnimatedBuilder(
      animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(5, (index) {
            final phase = (_controller.value * 2 * math.pi) + index * 0.9;
            final height = heights[index] * (0.55 + 0.45 * math.sin(phase).abs());
            return Container(
              width: 3,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: colors[index],
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      );
  }
}

class _RoomMemberWave extends StatefulWidget {
  const _RoomMemberWave({this.count = 5});

  final int count;

  @override
  State<_RoomMemberWave> createState() => _RoomMemberWaveState();
}

class _RoomMemberWaveState extends State<_RoomMemberWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List<Widget>.generate(widget.count, (index) {
              final phase = (_controller.value * 2 * math.pi) + (index * 0.85);
              final barHeight = 4.0 + (math.sin(phase).abs() * 10.0);
              return Container(
                width: 2,
                height: barHeight,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: kNeonLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}