import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

class PublicProfilePage extends StatefulWidget {
  const PublicProfilePage({
    super.key,
    required this.name,
    required this.userId,
    required this.accessToken,
    this.userCode = '',
    this.photoUrl,
    this.bio = '',
    this.posts = const [],
    this.onChat,
    this.onFollow,
  });

  final String name;
  final String userId;
  final String accessToken;
  final String userCode;
  final String? photoUrl;
  final String bio;
  final List<Map<String, dynamic>> posts;
  final VoidCallback? onChat;
  final VoidCallback? onFollow;

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  // ===== الألوان (نفس تصميم الصورة: كريمي + ذهبي) =====
  static const _brown = Color(0xFF1F1F1F); // لون النص الأساسي
  static const _brownDark = Color(0xFF3A2A08); // نص فوق الذهبي
  static const _brownMid = Color(0xFF4A4A4A);
  static const _brownLight = Color(0xFFD9A93E); // ذهبي غامق (مؤشرات/أزرار)
  static const _gold = Color(0xFFEFCB77);
  static const _cream = Color(0xFFFFF3DC);
  static const _paper = Colors.white;
  static const _muted = Color(0xFF9A9A9F);
  static const _chip = Color(0xFFF3F3F3);

  // ===== أبعاد الهيدر =====
  static const double _coverH = 300; // ارتفاع الغلاف
  static const double _barH = 56; // الشريط العلوي
  static const double _tabsH = 52; // شريط التابات
  static const double _cardH = 226; // بطاقة المعلومات تحت الغلاف
  static const double _cardLift = 28; // مقدار تداخل البطاقة مع الغلاف
  static const double _expandedH = (_coverH - _cardLift) + _cardH;

  int _tab = 2;
  final PageController _pageController = PageController(initialPage: 2);
  int _coverIndex = 0;
  final ScrollController _profileScrollController = ScrollController();
  bool _loading = true;
  String? _loadError;
  Map<String, dynamic> _profile = {};
  List<Map<String, dynamic>> _posts = [];
  bool _isFollowing = false;
  bool _isMine = false;
  bool _followBusy = false;

  Map<String, dynamic> get _stats =>
      Map<String, dynamic>.from((_profile['stats'] as Map?) ?? const {});

  int _number(String key) {
    final value = _stats[key] ?? _profile[key];
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  String _text(String key, [String fallback = '']) =>
      (_profile[key] ?? fallback).toString().trim();

  String _firstText(List<String> keys, [String fallback = '']) {
    for (final key in keys) {
      final value = _text(key);
      if (value.isNotEmpty && value != 'null') return value;
    }
    return fallback;
  }

  String _commentTimeAgo(dynamic value) {
    final date = DateTime.tryParse((value ?? '').toString())?.toLocal();
    if (date == null) return 'الآن';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return 'قبل ${diff.inMinutes} دقيقة';
    if (diff.inDays < 1) return 'قبل ${diff.inHours} ساعة';
    if (diff.inDays == 1) return 'قبل يوم';
    return 'قبل ${diff.inDays} يوم';
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // ترتيب الصفحات في PageView: المنشورات(0)، الوكالات(1)، الشخصية(2).
  // Directionality RTL يجعل الصفحة 2 في اليمين والصفحة 0 في اليسار.
  void _changeProfileTab(int index) {
    if (index == _tab || !mounted || index < 0 || index > 2) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _profileScrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile({bool showErrorView = true}) async {
    try {
      final response = await http.get(
        Uri.parse('https://happy-live-api.taher616270.workers.dev/api/v1/users/${Uri.encodeComponent(widget.userId)}/profile'),
        headers: {'Authorization': 'Bearer ${widget.accessToken}'},
      ).timeout(const Duration(seconds: 18));
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200 || decoded is! Map || decoded['ok'] != true) {
        throw Exception(decoded is Map
            ? (decoded['message'] ?? decoded['error'] ?? 'تعذر تحميل الملف الشخصي').toString()
            : 'تعذر تحميل الملف الشخصي');
      }
      final profile = Map<String, dynamic>.from(decoded['profile'] as Map);
      final posts = (profile['posts'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _posts = posts;
        _isFollowing = profile['isFollowing'] == true;
        _isMine = profile['isMine'] == true;
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (showErrorView) {
          _loadError = 'تعذر تحميل البيانات الحقيقية. تحقق من اتصال الخادم.';
        }
      });
      if (!showErrorView) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحديث الملف الشخصي. حاول مرة أخرى.')),
        );
      }
    }
  }

  Future<void> _refreshProfile() => _loadProfile(showErrorView: false);

  Future<void> _toggleFollow() async {
    if (_followBusy || _isMine) return;
    setState(() => _followBusy = true);
    try {
      final response = await http.post(
        Uri.parse('https://happy-live-api.taher616270.workers.dev/api/v1/users/${Uri.encodeComponent(widget.userId)}/follow'),
        headers: {'Authorization': 'Bearer ${widget.accessToken}'},
      ).timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200 || decoded is! Map || decoded['ok'] != true) {
        throw Exception(decoded is Map
            ? (decoded['message'] ?? decoded['error'] ?? 'تعذر تحديث المتابعة').toString()
            : 'تعذر تحديث المتابعة');
      }
      if (!mounted) return;
      setState(() {
        _isFollowing = decoded['following'] == true;
        final stats = Map<String, dynamic>.from(
          (_profile['stats'] as Map?) ?? const {},
        );
        final followers = _number('followers');
        stats['followers'] = (followers + (_isFollowing ? 1 : -1)).clamp(0, 0x7fffffff);
        _profile = {..._profile, 'stats': stats, 'isFollowing': _isFollowing};
      });
      await _loadProfile(showErrorView: false);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحديث المتابعة. حاول مرة أخرى.')),
        );
      }
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }


  String _timeAgo(dynamic value) {
    final date = DateTime.tryParse((value ?? '').toString())?.toLocal();
    if (date == null) return 'الآن';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return 'قبل ${diff.inMinutes} د';
    if (diff.inDays < 1) return 'قبل ${diff.inHours} س';
    return 'قبل ${diff.inDays} يوم';
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: _paper,
          extendBodyBehindAppBar: true,
          body: SafeArea(
            top: false,
            bottom: false,
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _brownLight))
                : _loadError != null
                    ? _errorView()
                    : Stack(
                        children: [
                          NestedScrollView(
                              controller: _profileScrollController,
                              physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                                CupertinoSliverRefreshControl(
                                  onRefresh: _refreshProfile,
                                  builder: (context, mode, pulledExtent,
                                      refreshTriggerPullDistance, refreshIndicatorExtent) {
                                    return SizedBox(
                                      height: pulledExtent,
                                      child: const Center(
                                        child: _FiveLineRefreshIndicator(),
                                      ),
                                    );
                                  },
                                ),
                                SliverAppBar(
                                  pinned: true,
                                  primary: true,
                                  automaticallyImplyLeading: false,
                                  backgroundColor: Colors.transparent,
                                  surfaceTintColor: Colors.transparent,
                                  elevation: 0,
                                  scrolledUnderElevation: 0,
                                  toolbarHeight: _barH,
                                  expandedHeight: _expandedH,
                                  bottom: _tabsBar(),
                                  flexibleSpace: LayoutBuilder(builder: (context, c) {
                                    final topPad = MediaQuery.of(context).padding.top;
                                    final shift = (topPad + _expandedH - c.maxHeight)
                                        .clamp(0.0, double.infinity);
                                    final p = (shift / 80).clamp(0.0, 1.0);
                                    final iconColor = Color.lerp(Colors.white, _brown, p)!;
                                    return ClipRect(
                                      child: Stack(fit: StackFit.expand, children: [
                                        // الغلاف + البطاقة يطلعون مع الإصبع 1:1
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          top: -shift,
                                          height: (_coverH - _cardLift) + _cardH + topPad,
                                          child: _heroStack(topPad),
                                        ),
                                        // خلفية الشريط العلوي (كريمي تدريجياً)
                                        Positioned(
                                          top: 0,
                                          left: 0,
                                          right: 0,
                                          height: topPad + _barH,
                                          child: IgnorePointer(
                                            child: Opacity(
                                              opacity: p,
                                              child: const DecoratedBox(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topCenter,
                                                    end: Alignment.bottomCenter,
                                                    colors: [_cream, Colors.white],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        // الأزرار والاسم
                                        Positioned(
                                          top: topPad,
                                          left: 8,
                                          right: 8,
                                          height: _barH,
                                          child: Row(children: [
                                            IconButton(
                                              icon: Icon(Icons.arrow_forward_rounded,
                                                  color: iconColor, size: 28),
                                              onPressed: () => Navigator.of(context).maybePop(),
                                            ),
                                            Expanded(
                                              child: Center(
                                                child: Opacity(
                                                  opacity: p,
                                                  child: Text(
                                                    _firstText(
                                                        ['name', 'displayName', 'display_name'],
                                                        widget.name),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Color(0xFF292929),
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              icon: Icon(Icons.more_horiz_rounded,
                                                  color: iconColor, size: 28),
                                              onPressed: () {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                      content: Text('لا توجد خيارات إضافية حالياً')),
                                                );
                                              },
                                            ),
                                          ]),
                                        ),
                                      ]),
                                    );
                                  }),
                                ),
                              ],
                              body: _profileContent(),
                            ),
                          Positioned(
                            left: 14,
                            right: 14,
                            bottom: 10 + MediaQuery.of(context).padding.bottom,
                            child: _actionBar(),
                          ),
                        ],
                      ),
          ),
        ),
      );

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, color: _brownLight, size: 42),
            const SizedBox(height: 12),
            Text(_loadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _brown, fontSize: 14)),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _loadError = null;
                });
                _loadProfile();
              },
              child: const Text('إعادة المحاولة'),
            ),
          ]),
        ),
      );

  // ====================== الغلاف + بطاقة المعلومات ======================

  List<String> _coverList() {
    final list = <String>[];
    final raw = _profile['covers'];
    if (raw is List) {
      for (final e in raw) {
        final u = e is Map
            ? (e['url'] ?? e['imageUrl'] ?? e['image_url'] ?? '').toString()
            : e.toString();
        if (u.isNotEmpty && u != 'null') list.add(u);
      }
    }
    if (list.isEmpty) {
      final c = _text('coverUrl');
      if (c.isNotEmpty && c != 'null') list.add(c);
    }
    return list;
  }

  // علم الدولة من رمز مكوّن من حرفين (مثال: SA)
  String _flagEmoji() {
    final code = _firstText(['countryCode', 'country_code', 'country']).toUpperCase();
    if (code.length != 2) return '';
    final a = code.codeUnitAt(0), b = code.codeUnitAt(1);
    if (a < 65 || a > 90 || b < 65 || b > 90) return '';
    return String.fromCharCodes([0x1F1E6 + a - 65, 0x1F1E6 + b - 65]);
  }

  // 'f' أنثى، 'm' ذكر، '' غير معروف
  String _genderKind() {
    final g = _firstText(['gender', 'sex']).toLowerCase();
    if (g == 'female' || g == 'f' || g == 'أنثى' || g == 'انثى') return 'f';
    if (g == 'male' || g == 'm' || g == 'ذكر') return 'm';
    return '';
  }

  Widget _heroStack(double topPad) {
    final covers = _coverList();
    final name = _firstText(['name', 'displayName', 'display_name'], widget.name);
    final code = _firstText(['userCode', 'user_code', 'gabo_id'], widget.userCode);
    final avatar = _firstText(['avatarUrl', 'avatar', 'photo_url'], widget.photoUrl ?? '');
    final badge = _firstText(['badgeName', 'badge', 'titleBadge']);
    final level = _firstText(['levelName', 'level', 'userLevel']);
    final vip = _firstText(['vipText', 'vipLevel', 'vip_level']);
    final flag = _flagEmoji();
    final gender = _genderKind();
    final cardTop = _coverH + topPad - _cardLift;

    return Stack(clipBehavior: Clip.none, children: [
      // الغلاف
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: _coverH + topPad,
        child: Stack(fit: StackFit.expand, children: [
          if (covers.isEmpty)
            _coverFallback()
          else
            PageView.builder(
              itemCount: covers.length,
              onPageChanged: (i) => setState(() => _coverIndex = i),
              itemBuilder: (_, i) => Image.network(
                covers[i],
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) => _coverFallback(),
              ),
            ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(.35), Colors.transparent],
                  stops: const [0, .35],
                ),
              ),
            ),
          ),
        ]),
      ),
      // بطاقة المعلومات
      Positioned(
        top: cardTop,
        left: 0,
        right: 0,
        height: _cardH,
        child: Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_cream, Colors.white],
              stops: [0, .33],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: ClipRect(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // الإحصائيات (تترك مكان للصورة الشخصية على اليمين)
                SizedBox(
                  height: 58,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 84),
                    child: Row(children: [
                      _stat('متابعون', _number('followers')),
                      _stat('إعجاب', _number('likesReceived')),
                      _stat('زائر', _number('visitors')),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                // الاسم + الجنس + العلم
                Row(children: [
                  Flexible(
                    child: Text(name.isEmpty ? 'مستخدم' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _brown, fontSize: 21, fontWeight: FontWeight.w900)),
                  ),
                  if (gender.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: gender == 'f' ? const Color(0xFFF3A6C8) : const Color(0xFF8FB8F5),
                      ),
                      child: Icon(gender == 'f' ? Icons.female_rounded : Icons.male_rounded,
                          color: Colors.white, size: 15),
                    ),
                  ],
                  if (flag.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(flag, style: const TextStyle(fontSize: 20)),
                  ],
                ]),
                const SizedBox(height: 10),
                // المعرف + نسخ
                Row(children: [
                  Text(code.isEmpty ? 'ID: —' : 'ID:$code',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                          color: _muted, fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () {
                      if (code.isEmpty) return;
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم نسخ المعرف')),
                      );
                    },
                    child: const Icon(Icons.copy_rounded, color: _muted, size: 16),
                  ),
                ]),
                // الشارات (من بيانات الحساب الحقيقية)
                if (badge.isNotEmpty || level.isNotEmpty || vip.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(spacing: 5, runSpacing: 5, children: [
                    if (level.isNotEmpty) _pill(level, const Color(0xFF22345A)),
                    if (badge.isNotEmpty) _pill(badge, const Color(0xFF7A3B1F)),
                    if (vip.isNotEmpty) _pill(vip, const Color(0xFF8A1010)),
                  ]),
                ],
              ]),
            ),
          ),
        ),
      ),
      // الصورة الشخصية تتداخل مع حافة البطاقة
      PositionedDirectional(
        top: cardTop + 11,
        start: 19,
        child: _avatar(58, avatar),
      ),
      // نقاط الغلاف (تظهر فقط لو فيه أكثر من غلاف)
      if (covers.length > 1)
        Positioned(
          left: 14,
          top: cardTop - 24,
          child: Row(
            children: List.generate(covers.length, (i) {
              final on = i == _coverIndex;
              return Container(
                margin: const EdgeInsets.only(right: 4),
                width: on ? 24 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: on ? Colors.white : Colors.white54,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ),
    ]);
  }

  Widget _coverFallback() => Image.asset(
        'web/assets/images/profile_cover/profile_cover.jpg.JPG',
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFB3353F), Color(0xFF6E1D25), Color(0xFF3A2A22)],
            ),
          ),
        ),
      );

  Widget _stat(String label, int value) => Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('$value',
                style: const TextStyle(color: _brown, fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: _muted, fontSize: 13)),
          ],
        ),
      );

  Widget _pill(String label, Color bg) => Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
      );

  Widget _avatar(double size, String photo) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _cream,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.12), blurRadius: 6)],
        ),
        child: ClipOval(
          child: photo.isEmpty
              ? const Icon(Icons.person, color: _brownLight, size: 30)
              : Image.network(photo,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.person, color: _brownLight, size: 30)),
        ),
      );

  // ====================== التابات + المحتوى ======================

  // التابات الثابتة تحت الشريط العلوي (bottom للـ SliverAppBar)
  PreferredSizeWidget _tabsBar() {
    Widget tab(String title, int index) {
      final active = _tab == index;
      return Expanded(
        child: InkWell(
          onTap: () => _changeProfileTab(index),
          child: SizedBox(
            height: _tabsH - 1,
            child: Center(
              child: Text(
                title,
                maxLines: 1,
                style: TextStyle(
                  color: active ? _brown : _muted,
                  fontSize: active ? 16 : 15,
                  fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return PreferredSize(
      preferredSize: const Size.fromHeight(_tabsH),
      child: Container(
        height: _tabsH,
        color: Colors.white,
        child: Column(children: [
          SizedBox(
            height: _tabsH - 1,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tabWidth = constraints.maxWidth / 3;
                return Stack(
                  children: [
                    // LTR physical layout: Posts left, Agencies center, Profile right.
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(children: [
                        tab('المنشورات', 0),
                        tab('الوكالات', 1),
                        tab('الصفحة الشخصية', 2),
                      ]),
                    ),
                    AnimatedBuilder(
                      animation: _pageController,
                      builder: (context, child) {
                        final page = _pageController.hasClients
                            ? (_pageController.page ?? _tab.toDouble())
                                .clamp(0.0, 2.0)
                            : _tab.toDouble();
                        final dx = page * tabWidth;
                        return Positioned(
                          left: 0,
                          bottom: 6,
                          child: Transform.translate(
                            offset: Offset(dx, 0),
                            child: SizedBox(
                              width: tabWidth,
                              child: Center(
                                child: Container(
                                  width: 20,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: _gold,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          Container(height: 1, color: const Color(0xFFF0ECE4)),
        ]),
      ),
    );
  }

  Widget _profileContent() {
    Widget page(int index) => ColoredBox(
          color: index == 0 ? Colors.transparent : Colors.white,
          child: _tabContent(index),
        );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: PageView(
        controller: _pageController,
        physics: const PageScrollPhysics(),
        onPageChanged: (i) {
          if (mounted && _tab != i) {
            setState(() => _tab = i);
          }
        },
        children: [
          page(0),
          page(1),
          page(2),
        ],
      ),
    );
  }

  Widget _tabContent(int index) {
    if (index == 0) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: ListView.builder(
          primary: true,
          // Let the outer NestedScrollView receive a pull-down at the
          // top edge so CupertinoSliverRefreshControl can refresh the profile.
          // The posts list still scrolls normally when it has content.
          physics: const ClampingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(17, 17, 17, 28),
          itemCount: 3,
          itemBuilder: (context, itemIndex) {
            if (itemIndex == 0) {
              return const Align(
                alignment: Alignment.centerRight,
                child: Text('المنشورات',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: _brown, fontSize: 14, fontWeight: FontWeight.w900)),
              );
            }
            if (itemIndex == 1) return const SizedBox(height: 9);
            return _postsContent();
          },
        ),
      );
    }
    if (index == 1) {
      // تبويب الوكالات الفارغ يبقى ثابتاً ولا ينشئ مساحة تمرير داخلية.
      return _emptySection(
        key: const ValueKey('agency-empty-section'),
        icon: Icons.apartment_rounded,
        title: 'لا توجد وكالة مرتبطة',
        subtitle: 'لا توجد بيانات وكالة مسجلة لهذا الحساب حالياً.',
      );
    }

    // مثل تبويب الوكالات: محتوى ثابت داخل الصفحة دون قائمة تمرير داخلية.
    // يترك السحب للتمرير الخارجي حتى يعمل مؤشر التحديث فوق الغلاف.
    return _personalDetails();
  }

  Widget _emptySection({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
  }) =>
      Container(
        key: key,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 45, 24, 55),
        child: Column(children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(color: _cream, shape: BoxShape.circle),
            child: Icon(icon, color: _brownLight, size: 36),
          ),
          const SizedBox(height: 15),
          Text(title,
              style: const TextStyle(color: _brown, fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 7),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.6)),
        ]),
      );

  Widget _personalDetails() {
    final bio = _firstText(['bio', 'about'], widget.bio);
    return Padding(
      key: const ValueKey('personal'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (bio.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: _chip, borderRadius: BorderRadius.circular(14)),
            child: Text(bio,
                style: const TextStyle(color: _brown, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        if (bio.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 141),
            child: Align(
              alignment: Alignment.topCenter,
              child: Text('لا توجد معلومات إضافية حالياً',
                  style: TextStyle(color: _muted, fontSize: 13)),
            ),
          ),
      ]),
    );
  }

  // ====================== المنشورات والتعليقات ======================

  Future<void> _toggleProfilePostLike(Map<String, dynamic> post) async {
    final id = (post['id'] ?? '').toString();
    if (id.isEmpty || post['_likeBusy'] == true) return;
    final wasLiked = post['liked'] == true;
    final oldCount = (post['likesCount'] as num?)?.toInt() ??
        (post['likes_count'] as num?)?.toInt() ??
        0;
    setState(() {
      post['_likeBusy'] = true;
      post['liked'] = !wasLiked;
      post['likesCount'] = (oldCount + (wasLiked ? -1 : 1)).clamp(0, 1 << 30);
    });
    try {
      final response = await http.post(
        Uri.parse('https://happy-live-api.taher616270.workers.dev/api/v1/posts/$id/like'),
        headers: {'Authorization': 'Bearer ${widget.accessToken}'},
      ).timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data is! Map || data['ok'] != true) {
        throw Exception();
      }
      if (!mounted) return;
      setState(() {
        post['liked'] = data['liked'] == true;
        post['likesCount'] = data['likesCount'] ?? oldCount;
        post['_likeBusy'] = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        post['liked'] = wasLiked;
        post['likesCount'] = oldCount;
        post['_likeBusy'] = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تسجيل الإعجاب')),
      );
    }
  }

  void _openCommenterProfile(Map<String, dynamic> comment) {
    final commenterId = (comment['userId'] ?? comment['user_id'] ?? '').toString().trim();
    if (commenterId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح ملف هذا المستخدم')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PublicProfilePage(
          name: (comment['name'] ?? 'مستخدم').toString(),
          userId: commenterId,
          accessToken: widget.accessToken,
          userCode: (comment['userCode'] ?? '').toString(),
          photoUrl: (comment['avatarUrl'] ?? comment['avatar_url'] ?? '').toString(),
        ),
      ),
    );
  }

  Future<void> _openProfilePostComments(Map<String, dynamic> post) async {
    final id = (post['id'] ?? '').toString();
    if (id.isEmpty) return;
    final input = TextEditingController();
    bool loading = true;
    bool sending = false;
    Map<String, dynamic>? replyingTo;
    String? error;
    List<Map<String, dynamic>> comments = [];
    final Set<String> expandedReplyThreads = {};

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> loadComments() async {
            try {
              final response = await http.get(
                Uri.parse('https://happy-live-api.taher616270.workers.dev/api/v1/posts/$id/comments'),
                headers: {'Authorization': 'Bearer ${widget.accessToken}'},
              ).timeout(const Duration(seconds: 12));
              final data = jsonDecode(response.body);
              if (response.statusCode != 200 || data is! Map || data['ok'] != true) {
                throw Exception();
              }
              comments = (data['comments'] as List? ?? const [])
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList();
              error = null;
            } catch (_) {
              error = 'تعذر تحميل التعليقات';
            }
            loading = false;
            setSheetState(() {});
          }

          Future<void> sendComment() async {
            final content = input.text.trim();
            if (content.isEmpty || sending) return;
            sending = true;
            setSheetState(() {});
            try {
              final isReply = replyingTo != null;
              final endpoint = isReply
                  ? 'https://happy-live-api.taher616270.workers.dev/api/v1/posts/$id/comments/${replyingTo!.containsKey('commentId') ? replyingTo!['commentId'] : replyingTo!['id']}/replies'
                  : 'https://happy-live-api.taher616270.workers.dev/api/v1/posts/$id/comments';
              final response = await http.post(
                Uri.parse(endpoint),
                headers: {
                  'Authorization': 'Bearer ${widget.accessToken}',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({'content': content, if (isReply && replyingTo!.containsKey('commentId')) 'parentReplyId': replyingTo!['id']}),
              ).timeout(const Duration(seconds: 12));
              final data = jsonDecode(response.body);
              if (response.statusCode != 201 || data is! Map || data['ok'] != true) {
                throw Exception();
              }
              if (isReply) {
                final reply = Map<String, dynamic>.from(data['reply'] as Map);
                final commentId = (replyingTo!.containsKey('commentId') ? replyingTo!['commentId'] : replyingTo!['id']).toString();
                reply['commentId'] = commentId;
                if (replyingTo!.containsKey('commentId')) reply['parentReplyId'] = replyingTo!['id'];
                final commentNode = comments.firstWhere((item) => item['id'].toString() == commentId);
                bool attach(List<dynamic> nodes) {
                  for (final node in nodes) {
                    if (node is Map && node['id'].toString() == replyingTo!['id'].toString()) {
                      final children = (node['replies'] as List? ?? const []).toList();
                      children.add(reply); node['replies'] = children; return true;
                    }
                    if (node is Map && attach((node['replies'] as List? ?? const []).toList())) return true;
                  }
                  return false;
                }
                if (replyingTo!.containsKey('commentId')) {
                  attach((commentNode['replies'] as List? ?? const []).toList());
                } else {
                  final children = (commentNode['replies'] as List? ?? const []).toList();
                  children.add(reply); commentNode['replies'] = children;
                }
                replyingTo = null;
              } else {
                final newComment = Map<String, dynamic>.from(data['comment'] as Map);
                newComment['replies'] = <Map<String, dynamic>>[];
                comments.add(newComment);
                post['commentsCount'] = ((post['commentsCount'] as num?)?.toInt() ?? 0) + 1;
              }
              input.clear();
              error = null;
            } catch (_) {
              error = replyingTo != null ? 'تعذر إرسال الرد' : 'تعذر إضافة التعليق';
            }
            sending = false;
            setSheetState(() {});
            if (mounted) setState(() {});
          }

          if (loading && comments.isEmpty) loadComments();
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              height: MediaQuery.of(context).size.height * .72,
              padding: EdgeInsets.fromLTRB(
                  18, 12, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
              decoration: const BoxDecoration(
                color: _paper,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: Column(children: [
                Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                        color: const Color(0xFFE5DFD0), borderRadius: BorderRadius.circular(5))),
                const SizedBox(height: 16),
                Row(children: [
                  const Expanded(
                      child: Text('التعليقات',
                          style: TextStyle(
                              color: _brown, fontSize: 18, fontWeight: FontWeight.w900))),
                  Text('${comments.length}',
                      style: const TextStyle(color: _muted, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 12),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator(color: _brownLight))
                      : error != null && comments.isEmpty
                          ? Center(child: Text(error!, style: const TextStyle(color: _muted)))
                          : comments.isEmpty
                              ? const Center(
                                  child: Text('كن أول من يعلّق على هذا المنشور',
                                      style: TextStyle(color: _muted)))
                              : ListView.separated(
                                  itemCount: comments.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 18, color: Color(0xFFF0EBDD)),
                                  itemBuilder: (_, index) {
                                    final comment = comments[index];
                                    final commenterName =
                                        (comment['name'] ?? 'مستخدم').toString();
                                    final commenterAvatar =
                                        (comment['avatarUrl'] ?? comment['avatar_url'] ?? '')
                                            .toString()
                                            .trim();
                                    List<Map<String, dynamic>> flattenReplies(List<dynamic> roots, [String? parentName]) {
                                      final result = <Map<String, dynamic>>[];
                                      for (final raw in roots) {
                                        if (raw is! Map) continue;
                                        final item = Map<String, dynamic>.from(raw);
                                        item['_replyToName'] = parentName;
                                        result.add(item);
                                        result.addAll(flattenReplies((item['replies'] as List? ?? const []).toList(), (item['name'] ?? 'مستخدم').toString()));
                                      }
                                      return result;
                                    }
                                    Widget buildReply(Map<String, dynamic> reply) {
                                      final replyName = (reply['name'] ?? 'مستخدم').toString();
                                      final avatar = (reply['avatarUrl'] ?? reply['avatar_url'] ?? '').toString().trim();
                                      final replyTo = (reply['_replyToName'] ?? '').toString().trim();
                                      return Padding(padding: const EdgeInsets.only(bottom: 7),
                                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          InkWell(onTap: () => _openCommenterProfile(reply), child: CircleAvatar(radius: 14, backgroundColor: _chip,
                                            backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                                            child: avatar.isEmpty ? const Icon(Icons.person_rounded, color: _muted, size: 14) : null)),
                                          const SizedBox(width: 8),
                                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            InkWell(onTap: () => _openCommenterProfile(reply), child: Text(replyName, style: const TextStyle(color: _brown, fontSize: 11, fontWeight: FontWeight.w900))),
                                            if (replyTo.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 1, bottom: 2), child: Text('رد على $replyTo', style: const TextStyle(color: _brownLight, fontSize: 9, fontWeight: FontWeight.w700))),
                                            Text((reply['content'] ?? '').toString(), style: const TextStyle(color: Colors.black, fontSize: 12, height: 1.45, fontWeight: FontWeight.w600)),
                                            Row(children: [
                                              Text(_timeAgo(reply['createdAt'] ?? reply['created_at']), style: const TextStyle(color: _muted, fontSize: 9)),
                                              TextButton(onPressed: () { replyingTo = {...reply, 'commentId': comment['id']}; setSheetState(() {}); },
                                                style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                                child: const Text('رد', style: TextStyle(color: _brownLight, fontSize: 10, fontWeight: FontWeight.w800))),
                                            ]),
                                          ])),
                                        ]),
                                      );
                                    }
                                    final allReplies = flattenReplies((comment['replies'] as List? ?? const []).toList());
                                    final threadId = comment['id'].toString();
                                    final expanded = expandedReplyThreads.contains(threadId);
                                    final visibleReplies = expanded || allReplies.length <= 1 ? allReplies : <Map<String, dynamic>>[allReplies.first];
                                    final hiddenReplyCount = allReplies.length - visibleReplies.length;
                                    Widget repliesSection() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                      ...visibleReplies.map(buildReply),
                                      if (allReplies.length > 1) Align(alignment: Alignment.centerRight, child: TextButton.icon(
                                        onPressed: () { if (expanded) { expandedReplyThreads.remove(threadId); } else { expandedReplyThreads.add(threadId); } setSheetState(() {}); },
                                        style: TextButton.styleFrom(foregroundColor: _brownLight, padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), visualDensity: VisualDensity.compact, minimumSize: Size.zero),
                                        icon: Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 17),
                                        label: Text(expanded ? 'إخفاء الردود' : 'عرض الردود ($hiddenReplyCount)', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                                      )),
                                    ]);
                                    return Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        InkWell(
                                          onTap: () => _openCommenterProfile(comment),
                                          customBorder: const CircleBorder(),
                                          child: CircleAvatar(
                                            radius: 17,
                                            backgroundColor: _chip,
                                            backgroundImage: commenterAvatar.isNotEmpty
                                                ? NetworkImage(commenterAvatar)
                                                : null,
                                            child: commenterAvatar.isEmpty
                                                ? const Icon(Icons.person_rounded,
                                                    color: _muted, size: 19)
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(width: 9),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Transform.translate(
                                                offset: const Offset(0, -2),
                                                child: Wrap(
                                                  crossAxisAlignment: WrapCrossAlignment.center,
                                                  spacing: 6,
                                                  children: [
                                                    InkWell(
                                                      onTap: () => _openCommenterProfile(comment),
                                                      child: Text(commenterName,
                                                          style: const TextStyle(
                                                              color: _brown,
                                                              fontWeight: FontWeight.w900,
                                                              fontSize: 12)),
                                                    ),
                                                    if ((comment['userId'] ?? comment['user_id'] ?? '').toString().isNotEmpty &&
                                                        (comment['userId'] ?? comment['user_id']).toString() == widget.userId)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFFFFE7A8),
                                                          border: Border.all(color: const Color(0xFFD6A642), width: 0.8),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: const Text('كاتب المنشور',
                                                            style: TextStyle(color: Color(0xFF79520B), fontSize: 9, fontWeight: FontWeight.w900)),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text((comment['content'] ?? '').toString(),
                                                  style: const TextStyle(
                                                      color: Color(0xFF000000),
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 13,
                                                      height: 1.5)),
                                              const SizedBox(height: 3),
                                              Transform.translate(
                                                offset: const Offset(4, 0),
                                                child: Text(
                                                  _commentTimeAgo(comment['createdAt'] ?? comment['created_at']),
                                                  style: const TextStyle(color: _muted, fontSize: 10),
                                                ),
                                              ),
                                              Align(
                                                alignment: Alignment.centerRight,
                                                child: TextButton(
                                                  onPressed: () {
                                                    replyingTo = comment;
                                                    input.clear();
                                                    setSheetState(() {});
                                                  },
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: _gold,
                                                    visualDensity: VisualDensity.compact,
                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                    minimumSize: Size.zero,
                                                  ),
                                                  child: const Text('رد', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                                                ),
                                              ),
                                              repliesSection(),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                ),
                if (error != null && comments.isNotEmpty)
                  Align(
                      alignment: Alignment.centerRight,
                      child: Text(error!,
                          style: const TextStyle(color: Colors.red, fontSize: 11))),
                if (replyingTo != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Expanded(child: Text('الرد على ${replyingTo!['name'] ?? 'مستخدم'}',
                          style: const TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.w800))),
                      IconButton(
                        onPressed: () { replyingTo = null; input.clear(); setSheetState(() {}); },
                        icon: const Icon(Icons.close_rounded, size: 17, color: _muted),
                        visualDensity: VisualDensity.compact,
                      ),
                    ]),
                  ),
                Row(children: [
                  Expanded(
                      child: TextField(
                    controller: input,
                    maxLength: 500,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(color: _brown, fontSize: 13),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: replyingTo == null ? 'اكتب تعليقاً...' : 'اكتب ردك...',
                      hintStyle: const TextStyle(color: _muted),
                      filled: true,
                      fillColor: _chip,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                    ),
                  )),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: sending ? null : sendComment,
                    style: IconButton.styleFrom(
                        backgroundColor: _gold, foregroundColor: _brownDark),
                    icon: sending
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _brownDark))
                        : const Icon(Icons.send_rounded),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
    input.dispose();
    if (mounted) setState(() {});
  }

  Widget _postsContent() {
    if (_profile['canViewPosts'] != true) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
            child: Text('منشورات هذا الحساب غير متاحة للعرض',
                style: TextStyle(color: _muted, fontSize: 12), textAlign: TextAlign.center)),
      );
    }
    if (_posts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
            child: Text('لا توجد منشورات عامة حتى الآن',
                style: TextStyle(color: _muted, fontSize: 12))),
      );
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: _posts.asMap().entries.map((entry) {
          final post = entry.value;
          final imageUrl = (post['imageUrl'] ?? post['image_url'] ?? '').toString();
          final liked = post['liked'] == true;
          final likes = (post['likesCount'] as num?)?.toInt() ??
              (post['likes_count'] as num?)?.toInt() ??
              0;
          final comments = (post['commentsCount'] as num?)?.toInt() ??
              (post['comments_count'] as num?)?.toInt() ??
              0;
          final authorName = (post['authorName'] ??
                  post['author_name'] ??
                  post['displayName'] ??
                  post['display_name'] ??
                  post['name'] ??
                  _firstText(['name', 'displayName', 'display_name'], widget.name))
              .toString()
              .trim();
          final authorPhoto = (post['authorAvatarUrl'] ??
                  post['author_avatar_url'] ??
                  post['avatarUrl'] ??
                  post['avatar_url'] ??
                  post['photo_url'] ??
                  post['userAvatar'] ??
                  post['user_avatar'] ??
                  _firstText(['avatarUrl', 'avatar', 'photo_url'], widget.photoUrl ?? ''))
              .toString()
              .trim();
          final createdAt = (post['createdAt'] ?? post['created_at'] ?? post['date'] ?? '')
              .toString()
              .trim();

          return Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    _avatar(42, authorPhoto),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            authorName.isEmpty ? widget.name : authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: _brown,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (createdAt.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              createdAt,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: const TextStyle(color: _muted, fontSize: 10),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if ((post['content'] ?? '').toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      (post['content'] ?? '').toString(),
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: _brown, fontSize: 13, height: 1.7),
                    ),
                  ),
                ],
                if (imageUrl.isNotEmpty) ...[
                  const SizedBox(height: 11),
                  Center(child: _ProfilePostImage(url: imageUrl)),
                ],
                const SizedBox(height: 9),
                const SizedBox(height: 4),
                Row(
                  children: [
                    InkWell(
                      onTap: () => _openProfilePostComments(post),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.mode_comment_outlined, color: _brownLight, size: 23),
                          const SizedBox(width: 5),
                          Text(
                            '$comments',
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ]),
                      ),
                    ),
                    InkWell(
                      onTap: post['_likeBusy'] == true ? null : () => _toggleProfilePostLike(post),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                            liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: liked ? const Color(0xFFE34D65) : _brownLight,
                            size: 24,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '$likes',
                            style: TextStyle(
                              color: liked ? const Color(0xFFE34D65) : _muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ]),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ],
              ),
            ),
            if (entry.key != _posts.length - 1)
              const Divider(height: 1, thickness: 1, color: _cream),
          ]);
        }).toList(),
      ),
    );
  }

  // ====================== الأزرار السفلية ======================

  Widget _actionBar() {
    Widget circle(IconData icon, VoidCallback onTap) => SizedBox(
          width: 56,
          height: 56,
          child: Material(
            color: _gold,
            elevation: 2,
            shadowColor: Colors.black26,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Icon(icon, color: Colors.white, size: 25),
            ),
          ),
        );

    Widget pill({
      required int flex,
      required Color bg,
      required Color fg,
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) =>
        Expanded(
          flex: flex,
          child: SizedBox(
            height: 56,
            child: Material(
              color: bg,
              elevation: 2,
              shadowColor: Colors.black26,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onTap,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, color: fg, size: 21),
                  const SizedBox(width: 8),
                  Text(label,
                      style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ),
        );

    return Row(children: [
      pill(
        flex: 135,
        bg: _cream,
        fg: _brownDark,
        icon: _isFollowing ? Icons.check_rounded : Icons.person_add_alt_1_rounded,
        label: _isMine ? 'حسابك' : _isFollowing ? 'متابع' : 'متابعة',
        onTap: _isMine ? () {} : (widget.onFollow ?? _toggleFollow),
      ),
      const SizedBox(width: 9),
      pill(
        flex: 130,
        bg: _gold,
        fg: Colors.white,
        icon: Icons.chat_bubble_rounded,
        label: 'الرسائل',
        onTap: widget.onChat ??
            () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('المحادثات الخاصة قيد التجهيز')),
                ),
      ),
      const SizedBox(width: 9),
      circle(Icons.home_rounded, () => Navigator.of(context).popUntil((r) => r.isFirst)),
      const SizedBox(width: 9),
      circle(
        Icons.person_rounded,
        () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('قريباً')),
        ),
      ),
    ]);
  }
}

class _FiveLineRefreshIndicator extends StatefulWidget {
  const _FiveLineRefreshIndicator();

  @override
  State<_FiveLineRefreshIndicator> createState() =>
      _FiveLineRefreshIndicatorState();
}

class _FiveLineRefreshIndicatorState extends State<_FiveLineRefreshIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Container(
          width: 48,
          height: 48,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.98),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFFEFCB77), width: 1),
            boxShadow: const [
              BoxShadow(color: Color(0x18000000), blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(5, (index) {
              final phase = (_controller.value * 2 * 3.141592653589793) -
                  (index * .72);
              final height = 7 + (10 * ((1 + math.sin(phase)) / 2));
              return Container(
                width: 3,
                height: height,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9A93E),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ),
      );
}

class _ProfilePostImage extends StatefulWidget {
  const _ProfilePostImage({required this.url});
  final String url;

  @override
  State<_ProfilePostImage> createState() => _ProfilePostImageState();
}

class _ProfilePostImageState extends State<_ProfilePostImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _width;
  double? _height;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _ProfilePostImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _width = null;
      _height = null;
      _failed = false;
      _resolve();
    }
  }

  void _resolve() {
    final next = NetworkImage(widget.url).resolve(createLocalImageConfiguration(context));
    if (_stream?.key == next.key) return;
    if (_stream != null && _listener != null) _stream!.removeListener(_listener!);
    _stream = next;
    _listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        if (!mounted) return;
        setState(() {
          _width = info.image.width.toDouble();
          _height = info.image.height.toDouble();
          _failed = false;
        });
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (mounted) setState(() => _failed = true);
      },
    );
    _stream!.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) _stream!.removeListener(_listener!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const SizedBox(
          width: 190,
          height: 120,
          child: Center(child: Icon(Icons.broken_image_outlined, color: Colors.black26)));
    }
    var boxWidth = 190.0;
    var boxHeight = 230.0;
    if (_width != null && _height != null && _width! > 0) {
      final ratio = _height! / _width!;
      if (ratio > 1.6) {
        boxWidth = 175;
        boxHeight = (175 * ratio).clamp(380.0, 420.0).toDouble();
      } else if (ratio >= .9 && ratio <= 1.05) {
        boxWidth = 210;
        boxHeight = 210;
      } else if (ratio > 1.05) {
        boxWidth = 190;
        boxHeight = 230;
      } else {
        boxWidth = 210;
        boxHeight = (210 * ratio).clamp(100.0, 230.0).toDouble();
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: boxWidth.clamp(0.0, 210.0).toDouble(),
        height: boxHeight.clamp(0.0, 420.0).toDouble(),
        child: Image.network(widget.url,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_outlined, color: Colors.black26))),
      ),
    );
  }
}
