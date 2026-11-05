import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ================== الألوان ==================
class _C {
  static const bg = Colors.transparent;
  static const divider = Color(0xFF030A08);
  static const grey = Color(0xFF8A9A98);
  static const nav = Color(0xFF1A1F1F);
  static const teal = Color(0xFF1FD1B8);
  static const red = Color(0xFFFF3B5C);
}

// ================== الموديل ==================
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

// ================== تحميل البيانات الحقيقية ==================
class ProfileLoader extends StatefulWidget {
  final Future<ProfileData> Function() load;
  const ProfileLoader({super.key, required this.load});

  @override
  State<ProfileLoader> createState() => _ProfileLoaderState();
}

class _ProfileLoaderState extends State<ProfileLoader> {
  late Future<ProfileData> _future = widget.load();

  void _retry() => setState(() => _future = widget.load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProfileData>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: _C.bg,
            body: Center(child: CircularProgressIndicator(color: _C.teal)),
          );
        }
        if (snap.hasError || !snap.hasData) {
          return Scaffold(
            backgroundColor: _C.bg,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('تعذر تحميل البيانات', style: TextStyle(color: Colors.white)),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _retry, child: const Text('إعادة المحاولة')),
                ],
              ),
            ),
          );
        }
        return ProfilePage(data: snap.data!);
      },
    );
  }
}

// ================== الصفحة ==================
class ProfilePage extends StatelessWidget {
  final ProfileData data;

  const ProfilePage({
    super.key,
    this.data = const ProfileData(
      userId: '',
    ),
  });

  void _soon(BuildContext context, String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(name), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      // This page is hosted inside SessionHomePage's IndexedStack.
      // Do not create a nested Scaffold here: the parent Scaffold owns
      // the persistent bottom navigation bar.
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    _Header(data: data),
                    const _TribeBanner(),
                    const SizedBox(height: 4),
                    MenuTile(title: 'من الذي رآني', color: const Color(0xFF1E9BFF), icon: Icons.visibility, badge: data.viewersCount, onTap: () => _soon(context, 'من الذي رآني')),
                    MenuTile(title: 'منشوراتي', color: const Color(0xFFFF4D8D), icon: Icons.bolt, onTap: () => _soon(context, 'منشوراتي')),
                    const _Divider(),
                    MenuTile(title: 'محفظتي', color: const Color(0xFFFF8A2B), icon: Icons.account_balance_wallet, onTap: () => _soon(context, 'محفظتي')),
                    MenuTile(title: 'مركز العروض', color: const Color(0xFFFF4F9A), icon: Icons.local_activity, trailingText: 'تفعيل : ${data.offersCount}', showDot: true, onTap: () => _soon(context, 'مركز العروض')),
                    MenuTile(title: 'VIP', color: const Color(0xFFFFB300), icon: Icons.workspace_premium, trailingText: data.vipText, onTap: () => _soon(context, 'VIP')),
                    MenuTile(title: 'تشغيل المنجم', color: const Color(0xFFFF7A2F), icon: Icons.hardware, trailingText: data.mineText, onTap: () => _soon(context, 'تشغيل المنجم')),
                    MenuTile(title: 'ترتيب الرتبة', color: const Color(0xFFFFC02E), icon: Icons.emoji_events, onTap: () => _soon(context, 'ترتيب الرتبة')),
                    MenuTile(title: 'نوبل', color: const Color(0xFF7B5CFF), icon: Icons.shield, trailingText: data.nobleText, onTap: () => _soon(context, 'نوبل')),
                    MenuTile(title: 'المركز التجاري', color: const Color(0xFFFF5C93), icon: Icons.storefront, onTap: () => _soon(context, 'المركز التجاري')),
                    MenuTile(title: 'ادعو الأصدقاء', color: const Color(0xFF2DD4BF), icon: Icons.share, onTap: () => _soon(context, 'ادعو الأصدقاء')),
                    const _Divider(),
                    MenuTile(title: 'المساعدة', outlineIcon: Icons.help_outline, onTap: () => _soon(context, 'المساعدة')),
                    MenuTile(title: 'الاعدادات', outlineIcon: Icons.settings_outlined, onTap: () => _soon(context, 'الاعدادات')),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================== الرأس ==================
class _Header extends StatelessWidget {
  final ProfileData data;
  const _Header({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFD9D9D9),
              image: data.photoUrl != null ? DecorationImage(image: NetworkImage(data.photoUrl!), fit: BoxFit.cover) : null,
            ),
            child: data.photoUrl == null ? const Icon(Icons.person, color: Colors.white, size: 38) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(child: Text(data.displayName.isEmpty ? 'مستخدم Happy Live' : data.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800))),
                    const SizedBox(width: 6),
                    Icon(data.isMale ? Icons.male : Icons.female, color: data.isMale ? const Color(0xFF3AA0FF) : const Color(0xFFFF5C93), size: 16),
                    const SizedBox(width: 4),
                    Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                  ],
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: data.userId));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الـ ID'), duration: Duration(seconds: 1)));
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.copy, color: _C.grey, size: 14),
                      const SizedBox(width: 4),
                      Text('ID:${data.userId}', textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(children: const [Icon(Icons.help_outline, color: _C.grey, size: 14), SizedBox(width: 6), Icon(Icons.star, color: Color(0xFFFFC107), size: 14)]),
              ],
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => ProfileEditPage(data: data),
                  ));
                },
                icon: const Icon(Icons.edit_outlined, size: 14, color: _C.grey),
                label: const Text('تعديل', style: TextStyle(color: _C.grey, fontSize: 12)),
                style: OutlinedButton.styleFrom(side: BorderSide(color: _C.grey.withOpacity(0.5)), shape: const StadiumBorder(), minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 10)),
              ),
              Positioned(top: -2, right: -2, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: _C.red, shape: BoxShape.circle))),
            ],
          ),
        ],
      ),
    );
  }
}

// ================== بطاقة القبيلة ==================
class _TribeBanner extends StatelessWidget {
  const _TribeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
        gradient: const LinearGradient(colors: [Color(0xFF0F2A2A), Color(0xFF0B1B1B)], begin: Alignment.topRight, end: Alignment.bottomLeft),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield, color: Color(0xFF4C8DFF), size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('انضم إلى القبيلة', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                Text('اعثر على الأصدقاء لتحصل على مكافأة', style: TextStyle(color: _C.grey, fontSize: 11)),
              ],
            ),
          ),
          SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5B7CFA), foregroundColor: Colors.white, elevation: 0, shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 18)),
              child: const Text('اذهب إلى', style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

// ================== صف القائمة ==================
class MenuTile extends StatelessWidget {
  final String title;
  final Color? color;
  final IconData? icon;
  final IconData? outlineIcon;
  final String? trailingText;
  final int badge;
  final bool showDot;
  final VoidCallback? onTap;

  const MenuTile({
    super.key,
    required this.title,
    this.color,
    this.icon,
    this.outlineIcon,
    this.trailingText,
    this.badge = 0,
    this.showDot = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (color != null)
                Container(width: 36, height: 36, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: Colors.white, size: 20))
              else
                SizedBox(width: 36, height: 36, child: Icon(outlineIcon, color: _C.grey, size: 26)),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15))),
              if (trailingText != null) Text(trailingText!, style: const TextStyle(color: _C.grey, fontSize: 12)),
              if (showDot) Container(margin: const EdgeInsets.symmetric(horizontal: 6), width: 8, height: 8, decoration: const BoxDecoration(color: _C.red, shape: BoxShape.circle)),
              if (badge > 0)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: _C.red, shape: BoxShape.circle),
                  child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 11)),
                ),
              const Icon(Icons.chevron_left, color: _C.grey, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(height: 6, margin: const EdgeInsets.symmetric(vertical: 4), color: _C.divider);
}

// جسر مؤقت للتوافق مع استدعاء الصفحة الحالي في main.dart.
// سنربط بيانات الحساب الحقيقية ونزيل الشريط السفلي المكرر عند مرحلة التعديل.
class HappyProfilePage extends StatelessWidget {
  const HappyProfilePage({
    super.key,
    required this.name,
    required this.email,
    required this.userId,
    required this.initial,
    required this.onLogout,
    required this.onSoon,
  });

  final String name;
  final String email;
  final String userId;
  final String initial;
  final VoidCallback onLogout;
  final ValueChanged<String> onSoon;

  @override
  Widget build(BuildContext context) {
    return ProfilePage(
      data: ProfileData(displayName: name, userId: userId),
    );
  }
}


// صفحة مستقلة لتعديل بيانات الملف الشخصي.
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key, required this.data});
  final ProfileData data;

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  late final TextEditingController _nameController = TextEditingController(text: widget.data.displayName);
  late final TextEditingController _bioController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _C.bg,
        appBar: AppBar(
          backgroundColor: _C.bg,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          title: const Text('تعديل الملف الشخصي', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: const Color(0xFF263532),
                      backgroundImage: widget.data.photoUrl == null ? null : NetworkImage(widget.data.photoUrl!),
                      child: widget.data.photoUrl == null ? const Icon(Icons.person, size: 48, color: Colors.white70) : null,
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(color: _C.teal, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt, size: 17, color: Colors.black),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              _editLabel('الاسم'),
              _editField(_nameController, hint: 'اكتب اسمك'),
              const SizedBox(height: 18),
              _editLabel('النبذة الشخصية'),
              _editField(_bioController, hint: 'اكتب نبذة قصيرة عنك', maxLines: 4),
              const SizedBox(height: 18),
              _editLabel('معرّف الحساب'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
                decoration: BoxDecoration(color: _C.nav, borderRadius: BorderRadius.circular(13), border: Border.all(color: Colors.white12)),
                child: Text('ID: ${widget.data.userId}', textDirection: TextDirection.ltr, style: const TextStyle(color: _C.grey, fontSize: 14)),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('واجهة التعديل جاهزة، وسيتم ربط الحفظ بالخادم لاحقًا')),
                  ),
                  style: ElevatedButton.styleFrom(backgroundColor: _C.teal, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
                  child: const Text('حفظ التعديلات', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
  );

  Widget _editField(TextEditingController controller, {required String hint, int maxLines = 1}) => TextField(
    controller: controller,
    maxLines: maxLines,
    style: const TextStyle(color: Colors.white, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _C.grey),
      filled: true,
      fillColor: _C.nav,
      contentPadding: const EdgeInsets.all(15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: Colors.white12)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: _C.teal)),
    ),
  );
}
