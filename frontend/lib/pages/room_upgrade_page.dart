import 'package:flutter/material.dart';

const _gold = Color(0xFFF3D9A4);
const _goldDeep = Color(0xFFD9A86A);
const _copper = Color(0xFF8A4B2E);
const _textSoft = Color(0xFF9C8F82);
const _bgTop = Color(0xFF3B2617);
const _bgBottom = Color(0xFF0F0B09);

class RoomLevel {
  const RoomLevel({
    required this.name,
    required this.price,
    required this.perks,
    this.image,
  });
  final String name;
  final int price;
  final List<Perk> perks;
  final String? image;
}

class Perk {
  const Perk(this.icon, this.title, this.desc);
  final IconData icon;
  final String title;
  final String desc;
}

/// أسعار ومميزات الفيلا والقصر المعلّمة TODO تُترك كما وردت دون تخمين.
const kLevels = <RoomLevel>[
  RoomLevel(name: 'أساسي', price: 0, perks: [
    Perk(Icons.pie_chart, 'سعة الغرفة',
        'يُسمح لـ 30 من المستخدمين كحد أقصى في الغرفة في نفس الوقت (باستثناء مالك الغرفة)'),
    Perk(Icons.settings, 'مشرف الغرفة', '3 مشرف كحد أقصى'),
    Perk(Icons.person, 'أعضاء الغرفة', '50 عضو كحد أقصى'),
    Perk(Icons.bar_chart, 'ترتيب الغرفة',
        'زاد مؤشر شعبية الغرفة بمقدار 1.0 مرات ، كلما زادت شعبية الغرفة ، كلما ارتفع ترتيب الغرفة في لوحة الصدارة'),
  ]),
  RoomLevel(name: 'مخيم', price: 30000, image: 'assets/levels/camp.png', perks: [
    Perk(Icons.verified, 'شارة الغرفة', 'تظهر شارة الشرف على غرفتك في قائمة الغرف'),
    Perk(Icons.pie_chart, 'سعة الغرفة',
        'يُسمح لـ 80 من المستخدمين كحد أقصى في الغرفة في نفس الوقت (باستثناء مالك الغرفة)'),
    Perk(Icons.settings, 'مشرف الغرفة', '8 مشرف كحد أقصى'),
    Perk(Icons.person, 'أعضاء الغرفة', '200 عضو كحد أقصى'),
    Perk(Icons.bar_chart, 'ترتيب الغرفة',
        'زاد مؤشر شعبية الغرفة بمقدار 1.3 مرات ، كلما زادت شعبية الغرفة ، كلما ارتفع ترتيب الغرفة في لوحة الصدارة'),
  ]),
  RoomLevel(name: 'شقة', price: 60000, image: 'assets/levels/apartment.png', perks: [
    Perk(Icons.verified, 'شارة الغرفة', 'تظهر شارة الشرف على غرفتك في قائمة الغرف'),
    Perk(Icons.pie_chart, 'سعة الغرفة',
        'يُسمح لـ 300 من المستخدمين كحد أقصى في الغرفة في نفس الوقت (باستثناء مالك الغرفة)'),
    Perk(Icons.settings, 'مشرف الغرفة', '12 مشرف كحد أقصى'),
    Perk(Icons.person, 'أعضاء الغرفة', '500 عضو كحد أقصى'),
    Perk(Icons.bar_chart, 'ترتيب الغرفة',
        'زاد مؤشر شعبية الغرفة بمقدار 1.5 مرات ، كلما زادت شعبية الغرفة ، كلما ارتفع ترتيب الغرفة في لوحة الصدارة'),
    Perk(Icons.gif_box, 'خلفية الغرفة المتحركة',
        'تدعم الغرفة تحميل خلفيات مخصصة متحركة، ويدعم فقط صيغة GIF'),
  ]),
  RoomLevel(name: 'فيلا', price: 300000, image: 'assets/levels/villa.png', perks: [
    Perk(Icons.verified, 'شارة الغرفة', 'تظهر شارة الشرف على غرفتك في قائمة الغرف'),
    Perk(Icons.pie_chart, 'سعة الغرفة',
        'يُسمح لـ 300 من المستخدمين كحد أقصى في الغرفة في نفس الوقت (باستثناء مالك الغرفة)'),
    Perk(Icons.settings, 'مشرف الغرفة', '12 مشرف كحد أقصى'),
    Perk(Icons.person, 'أعضاء الغرفة', '500 عضو كحد أقصى'),
    Perk(Icons.bar_chart, 'ترتيب الغرفة',
        'زاد مؤشر شعبية الغرفة بمقدار 1.5 مرات ، كلما زادت شعبية الغرفة ، كلما ارتفع ترتيب الغرفة في لوحة الصدارة'),
    Perk(Icons.gif_box, 'خلفية الغرفة المتحركة',
        'تدعم الغرفة تحميل خلفيات مخصصة متحركة، ويدعم فقط صيغة GIF'),
  ]),
  RoomLevel(name: 'قصر', price: 0 /* TODO */, image: 'assets/levels/palace.png', perks: [
    Perk(Icons.verified, 'شارة الغرفة', 'تظهر شارة الشرف على غرفتك في قائمة الغرف'),
    Perk(Icons.pie_chart, 'سعة الغرفة',
        'يُسمح لـ 300 من المستخدمين كحد أقصى في الغرفة في نفس الوقت (باستثناء مالك الغرفة)'),
    Perk(Icons.settings, 'مشرف الغرفة', '12 مشرف كحد أقصى'),
    Perk(Icons.person, 'أعضاء الغرفة', '500 عضو كحد أقصى'),
    Perk(Icons.bar_chart, 'ترتيب الغرفة',
        'زاد مؤشر شعبية الغرفة بمقدار 1.5 مرات ، كلما زادت شعبية الغرفة ، كلما ارتفع ترتيب الغرفة في لوحة الصدارة'),
    Perk(Icons.gif_box, 'خلفية الغرفة المتحركة',
        'تدعم الغرفة تحميل خلفيات مخصصة متحركة، ويدعم فقط صيغة GIF'),
  ]),
];

class RoomUpgradePage extends StatefulWidget {
  const RoomUpgradePage({
    super.key,
    required this.ownerName,
    required this.ownerId,
    this.ownerAvatar,
    this.currentLevel = 0,
    this.onUpgrade,
  });

  final String ownerName;
  final String ownerId;
  final ImageProvider? ownerAvatar;
  final int currentLevel;
  final Future<void> Function(int levelIndex)? onUpgrade;

  @override
  State<RoomUpgradePage> createState() => _RoomUpgradePageState();
}

class _RoomUpgradePageState extends State<RoomUpgradePage> {
  late int _index = widget.currentLevel.clamp(0, kLevels.length - 1).toInt();
  late final PageController _pageController = PageController(initialPage: _index);
  bool _isUpgrading = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _go(int i) => _pageController.animateToPage(
        i.clamp(0, kLevels.length - 1).toInt(),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );

  Future<void> _submitUpgrade() async {
    if (_isUpgrading || widget.onUpgrade == null || kLevels[_index].price <= 0) return;
    setState(() => _isUpgrading = true);
    try {
      await widget.onUpgrade!(_index);
    } finally {
      if (mounted) setState(() => _isUpgrading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final level = kLevels[_index];
    final canUpgrade = _index > widget.currentLevel && level.price > 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_bgTop, _bgBottom],
              stops: [0, 0.55],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _appBar(context),
                _ownerChip(),
                SizedBox(height: 230, child: _showcase()),
                _levelTrack(),
                const SizedBox(height: 14),
                const _PerkRibbon('امتياز'),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(22)),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                      itemCount: level.perks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _PerkCard(level.perks[i]),
                    ),
                  ),
                ),
                if (canUpgrade) _upgradeBar(level),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _appBar(BuildContext context) => SizedBox(
        height: 52,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Text(
              'ترقية غرفة الآخرين',
              style: TextStyle(
                color: _gold,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            PositionedDirectional(
              start: 4,
              child: IconButton(
                icon: const Icon(Icons.chevron_right, color: _gold, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      );

  Widget _ownerChip() => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          margin: const EdgeInsetsDirectional.only(start: 14),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white12,
                backgroundImage: widget.ownerAvatar,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.ownerName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('ID:${widget.ownerId}',
                      style: const TextStyle(color: _textSoft, fontSize: 11)),
                ],
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      );

  Widget _showcase() => Stack(
        alignment: Alignment.center,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: kLevels.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  kLevels[i].image != null
                      ? Image.asset(
                          kLevels[i].image!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => _fallback(i),
                        )
                      : _fallback(i),
                  if (i > widget.currentLevel)
                    const Icon(Icons.lock, color: Colors.white70, size: 34),
                ],
              ),
            ),
          ),
          PositionedDirectional(
            start: 6,
            child: _arrow(Icons.chevron_left, () => _go(_index - 1)),
          ),
          PositionedDirectional(
            end: 6,
            child: _arrow(Icons.chevron_right, () => _go(_index + 1)),
          ),
        ],
      );

  Widget _fallback(int i) => Icon(
        i == 0 ? Icons.local_fire_department : Icons.home_work,
        size: 120,
        color: _goldDeep,
      );

  Widget _arrow(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Icon(icon, color: Colors.white, size: 34),
      );

  Widget _levelTrack() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            for (int i = 0; i < kLevels.length; i++)
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: 22,
                      child: i == _index
                          ? _tag(i == widget.currentLevel
                              ? 'المستوى الحالي'
                              : (i > widget.currentLevel ? 'مغلق' : ''))
                          : null,
                    ),
                    Icon(Icons.diamond,
                        size: i == _index ? 12 : 8,
                        color: i == _index ? _gold : _goldDeep),
                    const SizedBox(height: 2),
                    Text(
                      kLevels[i].name,
                      style: TextStyle(
                        fontSize: i == _index ? 12 : 10,
                        fontWeight:
                            i == _index ? FontWeight.w700 : FontWeight.w400,
                        color: i == _index ? Colors.white : _textSoft,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _tag(String t) => t.isEmpty
      ? const SizedBox.shrink()
      : Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(t,
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        );

  Widget _upgradeBar(RoomLevel level) => Container(
        color: const Color(0xFF14100D),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _isUpgrading ? null : _submitUpgrade,
              child: Container(
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(27),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFE6C4), Color(0xFFF4C98F)],
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.monetization_on,
                        color: Color(0xFFF5B400), size: 20),
                    const SizedBox(width: 6),
                    Text(
                      _isUpgrading ? 'جارٍ تنفيذ الترقية...' : 'رفع مستوى ${level.price}',
                      style: const TextStyle(
                        color: Color(0xFF3A2616),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text('صلاحية دائمة',
                style: TextStyle(color: _textSoft, fontSize: 12)),
          ],
        ),
      );
}

class _PerkRibbon extends StatelessWidget {
  const _PerkRibbon(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: 190,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _goldDeep, width: 1.4),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB86B45), _copper],
          ),
        ),
        child: Text(text,
            style: const TextStyle(
                color: _gold, fontSize: 15, fontWeight: FontWeight.w700)),
      );
}

class _PerkCard extends StatelessWidget {
  const _PerkCard(this.perk);
  final Perk perk;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _HexIcon(perk.icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(perk.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(perk.desc,
                      style: const TextStyle(
                          color: _textSoft, fontSize: 12, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _HexIcon extends StatelessWidget {
  const _HexIcon(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => ClipPath(
        clipper: _HexClipper(),
        child: Container(
          width: 52,
          height: 58,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF5A5148), Color(0xFF2C2622)],
            ),
          ),
          child: Icon(icon, color: _gold, size: 26),
        ),
      );
}

class _HexClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(s.width / 2, 0)
    ..lineTo(s.width, s.height * 0.25)
    ..lineTo(s.width, s.height * 0.75)
    ..lineTo(s.width / 2, s.height)
    ..lineTo(0, s.height * 0.75)
    ..lineTo(0, s.height * 0.25)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
}
