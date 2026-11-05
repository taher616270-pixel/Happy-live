import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _ink = Color(0xFF1E2233);
const _grey = Color(0xFF9A98AD);
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
        backgroundColor: const Color(0xFFF6F7FB),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF7EBCB), Color(0xFFFAF6EA), Color(0xFFF6F7FB)],
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
                          foregroundColor: const Color(0xFFD9A93C),
                          side: const BorderSide(color: Color(0xFFE9C26A)),
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
                    const [Color(0xFFF3BC5E), Color(0xFFE39A2E)],
                    Icons.account_balance_wallet_rounded,
                    'المحفظة',
                    onWallet,
                    trailingCoin: true,
                  ),
                  _tile(
                    const [Color(0xFFF59A80), Color(0xFFE8604A)],
                    Icons.event_note_rounded,
                    'مركز المهام',
                    onTasks,
                  ),
                  _tile(
                    const [Color(0xFF9DB4DC), Color(0xFF5E86C8)],
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
        color: const Color(0xFFE4E4EC),
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
              const [Color(0xFF5A4630), Color(0xFF2A1F14)],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _banner(
              'SVIP',
              'assets/profile/svip.png',
              onSvip,
              const [Color(0xFF3A4150), Color(0xFF14171F)],
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
            border: Border.all(color: const Color(0xFFD9A93C), width: 2),
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
                Icon(fallback, size: 40, color: const Color(0xFFD9A93C)),
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
                    colors: [Color(0xFFF6D27A), Color(0xFFD9A93C)],
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      );
}


class PublicProfilePage extends StatefulWidget {
  const PublicProfilePage({
    super.key,
    required this.name,
    required this.userId,
    this.userCode = '',
    this.photoUrl,
    this.bio = '',
    this.posts = const [],
    this.onChat,
  });

  final String name;
  final String userId;
  final String userCode;
  final String? photoUrl;
  final String bio;
  final List<Map<String, dynamic>> posts;
  final VoidCallback? onChat;

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  static const _bg = Color(0xFF0F1419);
  static const _muted = Color(0xFF9AA4AE);
  static const _teal = Color(0xFF00D1C1);
  static const _purple = Color(0xFF8054E8);
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _cover(),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _identity(),
              _levels(),
              _badges(),
              _tabs(),
              if (_tab == 0) _aboutContent() else _postsContent(),
            ]),
          )),
          _chatBar(),
        ]),
      ),
    ),
  );

  Widget _cover() => SizedBox(
    height: 220,
    width: double.infinity,
    child: Stack(fit: StackFit.expand, children: [
      const CustomPaint(painter: _NightCampPainter()),
      Positioned(top: 10, right: 12, child: _roundButton(
        Icons.arrow_forward_rounded, () => Navigator.of(context).maybePop())),
      Positioned(top: 12, left: 14, child: Container(
        width: 43, height: 43,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [Color(0xFFD6B8FF), Color(0xFF7844D8), Color(0xFF39206E)]),
          border: Border.all(color: const Color(0xFFFFE6A5), width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 9)],
        ),
        child: const Center(child: Text('👾', style: TextStyle(fontSize: 24))),
      )),
    ]),
  );

  Widget _roundButton(IconData icon, VoidCallback onTap) => Material(
    color: Colors.black45,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(width: 38, height: 38, child: Icon(icon, color: Colors.white, size: 22)),
    ),
  );

  Widget _identity() {
    final name = widget.name.trim().isEmpty ? 'مستخدم Happy Live' : widget.name.trim();
    final code = widget.userCode.trim().isNotEmpty ? widget.userCode.trim() : widget.userId;
    final bio = widget.bio.trim().isNotEmpty ? widget.bio.trim() : 'ابن الجنوب ✌️✌️';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(children: [
        _avatar(70),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text('ID:$code', textDirection: TextDirection.ltr,
            style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text(bio, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 13)),
        ])),
      ]),
    );
  }

  Widget _avatar(double size) => Container(
    width: size, height: size, padding: const EdgeInsets.all(2),
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(colors: [Color(0xFFE6C36A), Color(0xFF8B65E8)]),
    ),
    child: ClipOval(child: (widget.photoUrl ?? '').trim().isEmpty
      ? Container(color: const Color(0xFF29313A), child: const Icon(Icons.person, color: Colors.white70, size: 38))
      : Image.network(widget.photoUrl!, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(color: const Color(0xFF29313A), child: const Icon(Icons.person, color: Colors.white70, size: 38)))),
  );

  Widget _levels() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
    child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      _levelChip('المستوى 45  Lv45', const Color(0xFF29313A)),
      _levelChip('1207  متابعين', const Color(0xFF29313A)),
      _levelChip('Lv.64', _purple),
      _levelChip('VIP 3', const Color(0xFF171B20), textColor: const Color(0xFFE7C56F), border: const Color(0xFFB68B3D)),
    ]),
  );

  Widget _levelChip(String label, Color color, {Color textColor = Colors.white, Color? border}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(100),
      border: border == null ? null : Border.all(color: border)),
    child: Text(label, style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w900)),
  );

  Widget _badges() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Row(children: [
      _honor(Icons.workspace_premium_rounded, const Color(0xFFFFD36C), 'تاج'),
      const SizedBox(width: 9),
      _honor(Icons.shield_rounded, const Color(0xFF9BB8D9), 'درع'),
      const SizedBox(width: 9),
      _honor(Icons.gavel_rounded, const Color(0xFFE6B85C), 'سيف'),
    ]),
  );

  Widget _honor(IconData icon, Color color, String label) => Container(
    width: 38, height: 34,
    decoration: BoxDecoration(color: const Color(0xFF202830), borderRadius: BorderRadius.circular(10)),
    child: Tooltip(message: label, child: Icon(icon, color: color, size: 21)),
  );

  Widget _tabs() => Container(
    decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF27313A), width: .7))),
    child: Row(children: [
      _tabButton('نبذة', 0),
      _tabButton('المنشورات (' + widget.posts.length.toString() + ')', 1),
    ]),
  );

  Widget _tabButton(String label, int index) {
    final selected = _tab == index;
    return Expanded(child: InkWell(
      onTap: () => setState(() => _tab = index),
      child: Column(children: [
        const SizedBox(height: 13),
        Text(label, style: TextStyle(color: selected ? Colors.white : _muted, fontSize: 14, fontWeight: selected ? FontWeight.w900 : FontWeight.w600)),
        const SizedBox(height: 10),
        Container(height: 2.5, width: 42, decoration: BoxDecoration(color: selected ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(5))),
      ]),
    ));
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 19, 16, 11),
    child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
  );

  Widget _aboutContent() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _sectionTitle('غرف الدردشة'),
    SizedBox(height: 58, child: ListView(
      scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16),
      children: List.generate(5, (i) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 11),
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF252D39),
            border: Border.all(color: const Color(0xFF8C69E8), width: 1.5)),
          child: Icon([Icons.mic_rounded, Icons.music_note_rounded, Icons.nightlight_round, Icons.groups_rounded, Icons.spatial_audio_rounded][i], color: Colors.white70, size: 20),
        ),
      )),
    )),
    _sectionTitle('الداعمون'),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
      _supporter('7.7k', const Color(0xFFE3B65D)),
      _supporter('13.5k', const Color(0xFF9D83E8)),
      _supporter('15.1k', const Color(0xFF63B8C8)),
    ])),
    _sectionTitle('معلومات'),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [
      _infoLine('القبيلة', 'ONE'),
      _infoLine('بيانات اللعبة', 'Lv28'),
    ])),
    _sectionTitle('الإطارات والأوسمة'),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        crossAxisCount: 4, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10, crossAxisSpacing: 10,
        children: List.generate(12, (i) => Container(
          decoration: BoxDecoration(color: const Color(0xFF1B232B), borderRadius: BorderRadius.circular(13),
            border: Border.all(color: i % 3 == 0 ? const Color(0xFFB88C43) : const Color(0xFF34414C))),
          child: Icon([Icons.workspace_premium_rounded, Icons.shield_rounded, Icons.bolt_rounded, Icons.diamond_rounded][i % 4],
            color: [const Color(0xFFE7C56F), const Color(0xFF8EB4E2), const Color(0xFFB28BEE), const Color(0xFF6FC9C0)][i % 4], size: 27),
        )),
      ),
    ),
    const SizedBox(height: 18),
  ]);

  Widget _supporter(String value, Color color) => Expanded(child: Container(
    margin: const EdgeInsetsDirectional.only(end: 8), padding: const EdgeInsets.symmetric(vertical: 13),
    decoration: BoxDecoration(color: const Color(0xFF1B232B), borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      Icon(Icons.diamond_rounded, color: color, size: 19),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
    ]),
  ));

  Widget _infoLine(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF27313A)))),
    child: Row(children: [
      Text(label, style: const TextStyle(color: _muted, fontSize: 13)),
      const Spacer(),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
    ]),
  );

  Widget _postsContent() {
    if (widget.posts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 55, 20, 70),
        child: Center(child: Column(children: [
          Icon(Icons.photo_library_outlined, color: _muted, size: 38),
          SizedBox(height: 10),
          Text('لا توجد منشورات حتى الآن', style: TextStyle(color: _muted, fontSize: 13)),
        ])),
      );
    }
    return Column(children: widget.posts.map((post) => Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF171F27), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFF29343E))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text((post['content'] ?? '').toString(), style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.6)),
        if ((post['imageUrl'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 9),
          Center(child: _ProfilePostImage(url: post['imageUrl'].toString())),
        ],
      ]),
    )).toList());
  }

  Widget _chatBar() => Container(
    width: double.infinity, padding: EdgeInsets.fromLTRB(18, 10, 18, 10 + MediaQuery.of(context).padding.bottom),
    color: Colors.black,
    child: SizedBox(
      height: 52, width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: widget.onChat ?? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المحادثات الخاصة قيد التجهيز'))),
        icon: const Icon(Icons.chat_bubble_rounded, size: 19),
        label: const Text('محادثة', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        style: ElevatedButton.styleFrom(
          backgroundColor: _teal, foregroundColor: const Color(0xFF062522), elevation: 0,
          shape: const StadiumBorder(),
        ),
      ),
    ),
  );
}

class _ProfilePostImage extends StatelessWidget {
  const _ProfilePostImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.network(url, width: 210, height: 230, fit: BoxFit.contain, alignment: Alignment.center,
      errorBuilder: (_, __, ___) => const SizedBox(width: 190, height: 120, child: Icon(Icons.broken_image_outlined, color: Colors.white54))),
  );
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
