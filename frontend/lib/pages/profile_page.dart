import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

const _ink = Color(0xFFFFFFFF);
const _grey = Color(0xFFAAA2B5);
const _red = Color(0xFFE53E4D);

// يحتفظ هذا الموديل بالتوافق مع تحميل بيانات الحساب الحالي.
class ProfileData {
  final String displayName;
  final String userId;
  final String? photoUrl;
  final bool isMale;
  final int viewersCount;
  final int offersCount;
  final String vipText;
  final String mineText;
  final String nobleText;
  final int unreadMessages;

  const ProfileData({
    this.displayName = '',
    required this.userId,
    this.photoUrl,
    this.isMale = true,
    this.viewersCount = 0,
    this.offersCount = 0,
    this.vipText = 'ليس VIP بعد',
    this.mineText = 'غير مشغل',
    this.nobleText = 'لست نوبل بعد',
    this.unreadMessages = 0,
  });

  factory ProfileData.fromJson(Map<String, dynamic> j) {
    int toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return ProfileData(
      displayName: '${j['name'] ?? j['display_name'] ?? ''}',
      userId: '${j['gabo_id'] ?? j['id'] ?? j['user_id'] ?? ''}',
      photoUrl: (j['avatar'] ?? j['photo_url']) as String?,
      isMale: (j['gender'] ?? 'male') != 'female',
      viewersCount: toInt(j['viewers_count']),
      offersCount: toInt(j['offers_count']),
      vipText: (j['vip_text'] as String?) ?? 'ليس VIP بعد',
      mineText: (j['mine_text'] as String?) ?? 'غير مشغل',
      nobleText: (j['noble_text'] as String?) ?? 'لست نوبل بعد',
      unreadMessages: toInt(j['unread_messages']),
    );
  }
}

// واجهة التوافق مع الصفحة المستدعاة من main.dart.
class HappyProfilePage extends StatelessWidget {
  const HappyProfilePage({
    super.key,
    required this.name,
    required this.email,
    required this.userId,
    required this.initial,
    required this.onLogout,
    required this.onSoon,
    required this.onEdit,
    this.photoUrl,
    this.bio = '',
  });

  final String name;
  final String email;
  final String userId;
  final String initial;
  final VoidCallback onLogout;
  final ValueChanged<String> onSoon;
  final VoidCallback onEdit;
  final String? photoUrl;
  final String bio;

  @override
  Widget build(BuildContext context) {
    return ProfilePage(
      data: ProfileData(displayName: name, userId: userId, photoUrl: photoUrl),
      onEdit: onEdit,
      onPrestige: () => onSoon('برستيج'),
      onSvip: () => onSoon('SVIP'),
      onAgency: () => onSoon('الوكالة'),
      onMedals: () => onSoon('الأوسمة'),
      onLevel: () => onSoon('المستوى'),
      onStore: () => onSoon('المتجر'),
      onWallet: () => onSoon('المحفظة'),
      onTasks: () => onSoon('مركز المهام'),
      onSettings: () => onSoon('الإعدادات'),
    );
  }
}

class ProfilePage extends StatelessWidget {
  final ProfileData data;
  final int followers, likes, visitors;
  final int followersBadge, visitorsBadge;
  final int balance;
  final VoidCallback? onBack, onSvip, onPrestige, onAgency, onMedals,
      onLevel, onStore, onWallet, onTasks, onSettings, onEdit;

  const ProfilePage({
    super.key,
    this.data = const ProfileData(userId: ''),
    this.followers = 0,
    this.likes = 0,
    this.visitors = 0,
    this.followersBadge = 0,
    this.visitorsBadge = 0,
    this.balance = 0,
    this.onBack,
    this.onEdit,
    this.onSvip,
    this.onPrestige,
    this.onAgency,
    this.onMedals,
    this.onLevel,
    this.onStore,
    this.onWallet,
    this.onTasks,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF09080D),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF211A2B), Color(0xFF17131F), Color(0xFF09080D)],
              stops: [0.0, 0.3, 0.55],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                children: [
                  _header(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_rounded, size: 17),
                        label: const Text('تعديل الملف الشخصي'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE8C477),
                          side: const BorderSide(color: Color(0xFFE8C477)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  _stats(),
                  const SizedBox(height: 22),
                  _banners(),
                  const SizedBox(height: 14),
                  _iconsCard(),
                  _tile(
                    const [Color(0xFFE8C477), Color(0xFF9B70D6)],
                    Icons.account_balance_wallet_rounded,
                    'المحفظة',
                    onWallet,
                    trailingCoin: true,
                  ),
                  _tile(
                    const [Color(0xFF9B70D6), Color(0xFF49345F)],
                    Icons.event_note_rounded,
                    'مركز المهام',
                    onTasks,
                  ),
                  _tile(
                    const [Color(0xFF49345F), Color(0xFF211A2B)],
                    Icons.settings_rounded,
                    'الإعدادات',
                    onSettings,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final avatar = data.photoUrl ?? '';
    final displayName = data.displayName.trim().isEmpty
        ? 'مستخدم Happy Live'
        : data.displayName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 18, 0),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 60,
              height: 60,
              child: avatar.isEmpty
                  ? _avatarFallback()
                  : Image.network(
                      avatar,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _avatarFallback(),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: data.userId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم النسخ')),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          'ID:${data.userId}',
                          style: const TextStyle(
                            color: _grey,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.copy_rounded, size: 16, color: _grey),
                    ],
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onBack ?? () {},
            child: const Icon(Icons.chevron_left, size: 34, color: _grey),
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback() => Container(
        color: const Color(0xFF211A2B),
        child: const Icon(Icons.person, color: Colors.white, size: 30),
      );

  Widget _stats() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _stat('متابعون', followers, badge: followersBadge),
        _stat('إعجاب', likes),
        _stat('زائر', visitors, badge: visitorsBadge),
      ],
    );
  }

  Widget _stat(String label, int value, {int badge = 0}) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Text(
              '$value',
              style: const TextStyle(
                color: _ink,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (badge > 0)
              Positioned(left: -22, top: -6, child: _badge(badge)),
          ],
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: _grey, fontSize: 13)),
      ],
    );
  }

  Widget _badge(int n) => Container(
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _red,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$n',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  Widget _banners() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: _banner(
              'برستيج',
              'assets/profile/prestige.png',
              onPrestige,
              const [Color(0xFF382747), Color(0xFF17131F)],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _banner(
              'SVIP',
              'assets/profile/svip.png',
              onSvip,
              const [Color(0xFF49345F), Color(0xFF17131F)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(
    String text,
    String asset,
    VoidCallback? onTap,
    List<Color> colors,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 2.17,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE8C477), width: 2),
            gradient: LinearGradient(colors: colors),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              asset,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFFE9C26A),
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconsCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: _cardDeco(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _gridItem('الوكالة', 'assets/profile/agency.png',
              Icons.shield_rounded, onAgency),
          _gridItem('وسام', 'assets/profile/medal.png',
              Icons.workspace_premium_rounded, onMedals),
          _gridItem('المستوى', 'assets/profile/level.png',
              Icons.military_tech_rounded, onLevel),
          _gridItem('المتجر', 'assets/profile/store.png',
              Icons.storefront_rounded, onStore),
        ],
      ),
    );
  }

  Widget _gridItem(
    String label,
    String asset,
    IconData fallback,
    VoidCallback? onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Image.asset(
            asset,
            width: 40,
            height: 40,
            errorBuilder: (_, __, ___) =>
                Icon(fallback, size: 40, color: const Color(0xFFE8C477)),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    List<Color> colors,
    IconData icon,
    String title,
    VoidCallback? onTap, {
    bool trailingCoin = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: _cardDeco(),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: colors,
                ),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Text(
              title,
              style: const TextStyle(
                color: _ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            if (trailingCoin) ...[
              Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFE8C477), Color(0xFF9B70D6)],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$balance',
                style: const TextStyle(
                  color: _grey,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
            ],
            const Icon(Icons.chevron_left, color: _grey, size: 26),
          ],
        ),
      ),
    );
  }

  BoxDecoration _cardDeco() => BoxDecoration(
        color: const Color(0xFF17131F),
        borderRadius: BorderRadius.circular(24),
      );
}


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
  });

  final String name;
  final String userId;
  final String accessToken;
  final String userCode;
  final String? photoUrl;
  final String bio;
  final List<Map<String, dynamic>> posts;
  final VoidCallback? onChat;

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  // ألوان صفحة البروفايل العام مطابقة لهوية Happy Live.
  static const _bg = Color(0xFF09080D);
  static const _surface = Color(0xFF17131F);
  static const _surfaceRaised = Color(0xFF211A2B);
  static const _muted = Color(0xFFAAA2B5);
  static const _gold = Color(0xFFE8C477);
  static const _purple = Color(0xFF9B70D6);
  int _tab = 0;
  bool _loading = true;
  String? _loadError;
  Map<String, dynamic> _profile = {};
  List<Map<String, dynamic>> _posts = [];

  Map<String, dynamic> get _stats =>
      Map<String, dynamic>.from((_profile['stats'] as Map?) ?? const {});
  int _number(String key) => (_stats[key] as num?)?.toInt() ?? 0;
  String _text(String key, [String fallback = '']) {
    final value = (_profile[key] ?? fallback).toString().trim();
    return value;
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
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
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'تعذر تحميل البيانات الحقيقية. تحقق من اتصال الخادم.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _cover(),
          if (_loading) const LinearProgressIndicator(
            minHeight: 2, color: _gold, backgroundColor: _surfaceRaised),
          Expanded(child: _loadError != null
            ? Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off_rounded, color: _muted, size: 38),
                  const SizedBox(height: 12),
                  Text(_loadError!, textAlign: TextAlign.center,
                    style: const TextStyle(color: _muted, fontSize: 14)),
                  const SizedBox(height: 14),
                  OutlinedButton(onPressed: () {
                    setState(() { _loading = true; _loadError = null; });
                    _loadProfile();
                  }, child: const Text('إعادة المحاولة')),
                ]),
              ))
            : SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _identity(),
                  _statsRow(),
                  _tabs(),
                  if (_tab == 0) _aboutContent() else _postsContent(),
                ]),
              )),
          _chatBar(),
        ]),
      ),
    ),
  );

  Widget _cover() {
    final cover = _text('coverUrl');
    return SizedBox(
      height: 190,
      width: double.infinity,
      child: Stack(fit: StackFit.expand, children: [
        if (cover.isNotEmpty)
          Image.network(cover, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _coverFallback())
        else
          _coverFallback(),
        Positioned(top: 10, right: 12, child: _roundButton(
          Icons.arrow_forward_rounded, () => Navigator.of(context).maybePop())),
      ]),
    );
  }

  Widget _coverFallback() => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF382747), Color(0xFF17131F), Color(0xFF09080D)],
      ),
    ),
  );

  Widget _roundButton(IconData icon, VoidCallback onTap) => Material(
    color: const Color(0x9909080D),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(width: 38, height: 38, child: Icon(icon, color: Colors.white, size: 22)),
    ),
  );

  Widget _identity() {
    final name = _text('name', widget.name).isEmpty ? 'مستخدم' : _text('name', widget.name);
    final code = _text('userCode', widget.userCode).isEmpty ? '—' : _text('userCode', widget.userCode);
    final bio = _text('bio', widget.bio);
    final photo = _text('avatarUrl', widget.photoUrl ?? '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(children: [
        _avatar(70, photo),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text('ID:$code', textDirection: TextDirection.ltr,
            style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(bio, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 13)),
          ],
        ])),
      ]),
    );
  }

  Widget _avatar(double size, String photo) => Container(
    width: size, height: size, padding: const EdgeInsets.all(2),
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(colors: [_gold, _purple, _gold]),
    ),
    child: ClipOval(child: photo.isEmpty
      ? Container(color: _surfaceRaised, child: const Icon(Icons.person, color: _muted, size: 38))
      : Image.network(photo, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(color: const Color(0xFF29313A), child: const Icon(Icons.person, color: Colors.white70, size: 38)))),
  );

  Widget _statsRow() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
    child: Row(children: [
      _stat('متابعون', _number('followers')),
      _stat('يتابع', _number('following')),
      _stat('المنشورات', _number('posts')),
      _stat('الإعجابات', _number('likesReceived')),
    ]),
  );

  Widget _stat(String label, int value) => Expanded(child: Column(children: [
    Text('$value', style: const TextStyle(color: _gold, fontSize: 18, fontWeight: FontWeight.w900)),
    const SizedBox(height: 3),
    Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
  ]));

  Widget _tabs() => Container(
    decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF493957), width: .8))),
    child: Row(children: [
      _tabButton('نبذة', 0),
      _tabButton('المنشورات (${_number('posts')})', 1),
    ]),
  );

  Widget _tabButton(String label, int index) {
    final selected = _tab == index;
    return Expanded(child: InkWell(
      onTap: () => setState(() => _tab = index),
      child: Column(children: [
        const SizedBox(height: 13),
        Text(label, style: TextStyle(color: selected ? _gold : _muted, fontSize: 14, fontWeight: selected ? FontWeight.w900 : FontWeight.w600)),
        const SizedBox(height: 10),
        Container(height: 2.5, width: 42, decoration: BoxDecoration(color: selected ? _gold : Colors.transparent, borderRadius: BorderRadius.circular(5))),
      ]),
    ));
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 19, 16, 11),
    child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
  );

  Widget _aboutContent() {
    final country = _text('country');
    final gender = _text('gender');
    final age = _profile['age'];
    final joined = _text('joinedAt');
    final rooms = _number('activeRooms');
    final isPrivate = _profile['isPrivate'] == true;
    String joinedLabel = 'غير متاح';
    final date = DateTime.tryParse(joined);
    if (date != null) joinedLabel = '${date.year}-${date.month.toString().padLeft(2, '0')}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sectionTitle('معلومات الحساب'),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [
        if (country.isNotEmpty) _infoLine('الدولة', country),
        if (gender.isNotEmpty) _infoLine('الجنس', gender == 'male' ? 'ذكر' : gender == 'female' ? 'أنثى' : gender),
        if (age is num && age >= 0) _infoLine('العمر', age.toString()),
        _infoLine('تاريخ الانضمام', joinedLabel),
        _infoLine('حالة الحساب', isPrivate ? 'خاص' : 'عام'),
      ])),
      _sectionTitle('النشاط'),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [
        _infoLine('الغرف التي أنشأها والنشطة', '$rooms'),
        _infoLine('إجمالي الإعجابات المستلمة', '${_number('likesReceived')}'),
      ])),
      if (isPrivate && _profile['canViewPosts'] != true)
        const Padding(padding: EdgeInsets.all(24), child: Center(
          child: Text('هذا الحساب خاص. تابع الحساب لرؤية منشوراته.',
            style: TextStyle(color: _muted), textAlign: TextAlign.center))),
    ]);
  }

  Widget _infoLine(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF382B45)))),
    child: Row(children: [
      Text(label, style: const TextStyle(color: _muted, fontSize: 13)),
      const Spacer(),
      Flexible(child: Text(value, textAlign: TextAlign.end,
        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800))),
    ]),
  );

  Widget _postsContent() {
    if (_profile['canViewPosts'] != true) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 55, 20, 70),
        child: Center(child: Text('منشورات هذا الحساب غير متاحة للعرض',
          style: TextStyle(color: _muted, fontSize: 13))),
      );
    }
    if (_posts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 55, 20, 70),
        child: Center(child: Column(children: [
          Icon(Icons.photo_library_outlined, color: _muted, size: 38),
          SizedBox(height: 10),
          Text('لا توجد منشورات عامة حتى الآن', style: TextStyle(color: _muted, fontSize: 13)),
        ])),
      );
    }
    return Column(children: _posts.map((post) => Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFF493957))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text((post['content'] ?? '').toString(), style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.6)),
        if ((post['imageUrl'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 9),
          Center(child: _ProfilePostImage(url: post['imageUrl'].toString())),
        ],
        const SizedBox(height: 8),
        Text('♥ ${post['likesCount'] ?? 0}    تعليق ${post['commentsCount'] ?? 0}',
          style: const TextStyle(color: _muted, fontSize: 11)),
      ]),
    )).toList());
  }

  Widget _chatBar() => Container(
    width: double.infinity, padding: EdgeInsets.fromLTRB(18, 10, 18, 10 + MediaQuery.of(context).padding.bottom),
    color: _bg,
    child: SizedBox(
      height: 52, width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: widget.onChat ?? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المحادثات الخاصة قيد التجهيز'))),
        icon: const Icon(Icons.chat_bubble_rounded, size: 19),
        label: const Text('محادثة', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        style: ElevatedButton.styleFrom(
          backgroundColor: _gold, foregroundColor: const Color(0xFF21162B), elevation: 0,
          shape: const StadiumBorder(),
        ),
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
      return const SizedBox(width: 190, height: 120,
        child: Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54)));
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
        child: Image.network(widget.url, fit: BoxFit.contain, alignment: Alignment.center,
          errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54))),
      ),
    );
  }
}

class _NightCampPainter extends CustomPainter {
  const _NightCampPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFF10172B), Color(0xFF283044), Color(0xFF171B20)],
      stops: [0, .58, 1],
    ).createShader(rect));
    final stars = Paint()..color = const Color(0xFFE5E7F4).withOpacity(.75);
    for (var i = 0; i < 34; i++) {
      canvas.drawCircle(Offset((i * 67.0 + 19) % size.width, (i * 29.0 + 13) % 95), i % 5 == 0 ? 1.5 : .8, stars);
    }
    canvas.drawCircle(Offset(size.width * .78, 47), 17, Paint()..color = const Color(0xFFD7D9E2).withOpacity(.8));
    final ridge = Path()
      ..moveTo(0, size.height * .68)
      ..quadraticBezierTo(size.width * .22, size.height * .48, size.width * .42, size.height * .7)
      ..quadraticBezierTo(size.width * .73, size.height * .48, size.width, size.height * .7)
      ..lineTo(size.width, size.height)..lineTo(0, size.height)..close();
    canvas.drawPath(ridge, Paint()..color = const Color(0xFF171D25));
    final tent = Path()
      ..moveTo(size.width * .08, size.height * .83)
      ..lineTo(size.width * .24, size.height * .39)
      ..lineTo(size.width * .43, size.height * .83)..close();
    canvas.drawPath(tent, Paint()..color = const Color(0xFF5A493D));
    canvas.drawPath(tent, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFFB59A70));
    final door = Path()
      ..moveTo(size.width * .22, size.height * .82)
      ..lineTo(size.width * .245, size.height * .57)
      ..lineTo(size.width * .34, size.height * .82)..close();
    canvas.drawPath(door, Paint()..color = const Color(0xFF171B20));
    final ground = size.height * .86;
    canvas.drawOval(Rect.fromCenter(center: Offset(size.width * .68, ground + 10), width: 125, height: 19), Paint()..color = Colors.black45);
    canvas.drawCircle(Offset(size.width * .67, ground - 13), 25, Paint()..color = const Color(0x66FF7B28)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
    final fire = Path()
      ..moveTo(size.width * .63, ground + 3)
      ..quadraticBezierTo(size.width * .56, ground - 20, size.width * .67, ground - 46)
      ..quadraticBezierTo(size.width * .69, ground - 22, size.width * .73, ground - 4)..close();
    canvas.drawPath(fire, Paint()..color = const Color(0xFFFF8A32));
    final inner = Path()
      ..moveTo(size.width * .66, ground + 1)
      ..quadraticBezierTo(size.width * .63, ground - 15, size.width * .68, ground - 29)
      ..quadraticBezierTo(size.width * .71, ground - 11, size.width * .70, ground + 1)..close();
    canvas.drawPath(inner, Paint()..color = const Color(0xFFFFD36A));
    final person = Paint()..color = const Color(0xFF101318);
    for (final x in [size.width * .48, size.width * .84]) {
      canvas.drawCircle(Offset(x, ground - 26), 8, person);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 13, ground - 18, 26, 25), const Radius.circular(9)), person);
      canvas.drawLine(Offset(x - 7, ground + 3), Offset(x - 13, ground + 12), Paint()..color = const Color(0xFF101318)..strokeWidth = 4);
      canvas.drawLine(Offset(x + 7, ground + 3), Offset(x + 13, ground + 12), Paint()..color = const Color(0xFF101318)..strokeWidth = 4);
    }
  }

  @override
  bool shouldRepaint(covariant _NightCampPainter oldDelegate) => false;
}
