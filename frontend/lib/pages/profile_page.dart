import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
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
            top: false,
            bottom: false,
            child: SingleChildScrollView(
              // The page background starts at the very top edge.
              // Keep only the bottom inset here; the header handles the
              // device-specific status-bar safe area for its contents.
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
      ),
    );
  }

  Widget _header(BuildContext context) {
    final avatar = data.photoUrl ?? '';
    final displayName = data.displayName.trim().isEmpty
        ? 'مستخدم Happy Live'
        : data.displayName;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        14,
        MediaQuery.of(context).padding.top + 18,
        18,
        0,
      ),
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
