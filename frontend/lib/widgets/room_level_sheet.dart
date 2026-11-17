import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

const _sheetBg = Color(0xFF15131B);
const _cardBg = Color(0xFF1C1A23);
const _cardBorder = Color(0xFF2A2733);
const _green = Color(0xFF6BE675);
const _greenDeep = Color(0xFF1E6B3C);
const _muted = Color(0xFF8A8794);
const _track = Color(0xFF3A3842);

/// الخبرة المطلوبة للوصول إلى المستوى المحدد.
/// كل خمسة مستويات تزيد الخبرة المطلوبة بمقدار 3.3 مليون، بلا حد أقصى.
List<Color> roomLevelBadgeColors(int level) {
  if (level >= 120) return const [Color(0xFF167FA8), Color(0xFF49D7F2), Color(0xFFD4FAFF)];
  if (level >= 105) return const [Color(0xFF171717), Color(0xFF514633), Color(0xFFE0C987)];
  if (level >= 90) return const [Color(0xFF7D1830), Color(0xFFD63F65), Color(0xFFFFA0B2)];
  if (level >= 70) return const [Color(0xFF80520B), Color(0xFFD9A62B), Color(0xFFFFE08A)];
  if (level >= 40) return const [Color(0xFF493080), Color(0xFF8E7CFF), Color(0xFFC9BFFF)];
  if (level >= 10) return const [Color(0xFF145E83), Color(0xFF29C5D6), Color(0xFFA6F1FF)];
  return const [Color(0xFF1E6B3A), Color(0xFF3CB35F), Color(0xFF8FD176)];
}

int roomLevelRequiredExpForLevel(int targetLevel) {
  final safeLevel = targetLevel < 1 ? 1 : targetLevel;
  final group = ((safeLevel - 1) ~/ 5) + 1;
  return group * 3300000;
}

class ExpTask {
  const ExpTask({required this.title, required this.desc, required this.current, required this.max, required this.icon, this.ratio = 0});
  final String title, desc, current, max;
  final IconData icon;
  final double ratio;
}
class LevelPerk {
  const LevelPerk(this.title, this.icon, {this.subtitle, this.iconColor});
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? iconColor;
}
class LevelPerksGroup {
  const LevelPerksGroup(this.level, this.perks);
  final int level;
  final List<LevelPerk> perks;
}
class RoomLevelData {
  const RoomLevelData({
    required this.level, required this.roomName, required this.roomId,
    this.roomAvatar, required this.exp, required this.nextLevelExp,
    this.dailyExpCurrent = '0', this.dailyExpMax = '9.9m',
    this.dailyRatio = 0, this.dailyResetIn, this.tasks = const [],
    this.perkGroups = const [],
    this.note = 'يمكن لكل مستخدم المساهمة بما يصل إلى 3،000،000 من نقاط الخبرة يوميا في جميع الغرف.',
  });
  final int level, exp, nextLevelExp;
  final String roomName, roomId, dailyExpCurrent, dailyExpMax, note;
  final ImageProvider? roomAvatar;
  final double dailyRatio;
  final Duration? dailyResetIn;
  final List<ExpTask> tasks;
  final List<LevelPerksGroup> perkGroups;
}

const kSampleTasks = <ExpTask>[
  ExpTask(title: 'اخذ المقعد', desc: '+600 نقاط خبرة الغرفة/5 دقائق المستخدمين الجدد: +1200 نقاط خبرة الغرفة/5 دقائق', current: 'تُحتسب تلقائيًا', max: '600 / 1200 كل 5 دقائق', icon: Icons.mic),
  ExpTask(title: 'ارسل الهدايا في الغرفة', desc: 'سيتم احتساب خبرة الهدايا بعد ربط خدمة إرسال الهدايا بالخادم', current: 'قريبًا', max: 'غير مفعّل', icon: Icons.card_giftcard),
];
const kSamplePerks = <LevelPerksGroup>[
  LevelPerksGroup(1, [
    LevelPerk('شارة خضراء ابتدائية المستوى', Icons.military_tech, iconColor: Color(0xFF3DBE6B)),
    LevelPerk('إظهار شارة مستوى الغرفة داخل الغرفة', Icons.home_filled, iconColor: Color(0xFFFFB84D)),
  ]),
  LevelPerksGroup(5, [
    LevelPerk('غلاف غرفة متحرك', Icons.image, subtitle: 'القدرة على تعيين غلاف غرفة متحرك', iconColor: Color(0xFF5CC8FF)),
    LevelPerk('خصص خليفة الغرفة', Icons.palette, subtitle: 'يمكن تحميل خلفية الغرفة', iconColor: Color(0xFFFFB84D)),
  ]),
  LevelPerksGroup(10, [
    LevelPerk('شارة زرقاء متوسطة المستوى', Icons.diamond, iconColor: Color(0xFF29C5D6)),
    LevelPerk('تظهر شارة مستوى الغرفة في قائمة الغرف', Icons.badge, iconColor: Color(0xFFFFB84D)),
    LevelPerk('خلفية غرفة متحركة حصرية', Icons.wallpaper, iconColor: Color(0xFF3DBE6B)),
    LevelPerk('قادرة على إنشاء قبيلة', Icons.shield, iconColor: Color(0xFF5CC8FF)),
    LevelPerk('فتح امتياز لاستضافة أحداث الغرفة', Icons.celebration, iconColor: Color(0xFFB07CFF)),
  ]),
  LevelPerksGroup(15, [LevelPerk('قادرة على فتح مزاد العلاقة في غرفتك', Icons.gavel, iconColor: Color(0xFFFFB84D))]),
  LevelPerksGroup(30, [LevelPerk('خلفية غرفة متحركة حصرية', Icons.wallpaper, iconColor: Color(0xFF7A6CFF))]),
  LevelPerksGroup(40, [LevelPerk('شارة أرجوانية مميزة', Icons.workspace_premium, iconColor: Color(0xFF8E7CFF))]),
  LevelPerksGroup(50, [
    LevelPerk('خلفية غرفة متحركة حصرية', Icons.wallpaper, iconColor: Color(0xFF9B6CFF)),
    LevelPerk('غرفة متعددة الميكروفونات', Icons.apps, subtitle: 'تفعيل وضع خانات ميكروفون إضافية', iconColor: Color(0xFF9B6CFF)),
    LevelPerk('الدردشة بالفيديو', Icons.videocam, subtitle: 'فتح الكاميرا للمستخدم على المايك', iconColor: Color(0xFF8A2B4A)),
  ]),
  LevelPerksGroup(70, [
    LevelPerk('شارة ذهبية ملحمية', Icons.workspace_premium, iconColor: Color(0xFFD9A62B)),
    LevelPerk('خلفية غرفة متحركة حصرية', Icons.wallpaper, iconColor: Color(0xFF3DBE6B)),
  ]),
  LevelPerksGroup(90, [
    LevelPerk('شارة حمراء أسطورية', Icons.hexagon, iconColor: Color(0xFFD63FA8)),
  ]),
  LevelPerksGroup(100, [
    LevelPerk('خلفية غرفة شرفية مخصصة', Icons.edit, iconColor: Color(0xFFE01F5A)),
  ]),
  LevelPerksGroup(105, [
    LevelPerk('خلفية غرفة شرفية مخصصة', Icons.edit, iconColor: Color(0xFFE01F5A)),
    LevelPerk('شارة ذهبية سوداء شرفية', Icons.local_florist, iconColor: Color(0xFFC72A55)),
    LevelPerk('سمة غرفة مخصصة', Icons.apps, iconColor: Color(0xFFE5701A)),
  ]),
  LevelPerksGroup(110, [
    LevelPerk('خلفية غرفة متحركة حصرية', Icons.wallpaper, iconColor: Color(0xFFB9A66A)),
  ]),
  LevelPerksGroup(115, [
    LevelPerk('الشعار الحصري للمنصة', Icons.notifications_active, iconColor: Color(0xFFD9A62B)),
    LevelPerk('سمة غرفة مخصصة', Icons.apps, iconColor: Color(0xFFE5701A)),
  ]),
  LevelPerksGroup(120, [
    LevelPerk('استبدال شارة الماس المتقدمة', Icons.auto_awesome, subtitle: 'يُفتح عند المستوى 120', iconColor: Color(0xFFC8661E)),
    LevelPerk('تخصيص خاص', Icons.edit, subtitle: 'دعم عملاء مخصص', iconColor: Color(0xFFE01F5A)),
    LevelPerk('شاشة تشغيل مخصصة', Icons.slideshow, subtitle: 'يُفتح عند المستوى 120', iconColor: Color(0xFFD9A62B)),
  ]),
];

/// شارة المستوى في الغرفة؛ تحافظ على شكل الشارة الحالية وتفتح نافذة المستوى.
class RoomLevelChip extends StatelessWidget {
  const RoomLevelChip({super.key, required this.data});
  final RoomLevelData data;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => showRoomLevelSheet(context, data),
    child: Container(
      height: 20,
      padding: const EdgeInsets.only(left: 4, right: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: roomLevelBadgeColors(data.level)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.15), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('Lv. ${data.level}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: .2)),
        const SizedBox(width: 5),
        Container(width: 12, height: 12, decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [Colors.white.withOpacity(.95), ...roomLevelBadgeColors(data.level).reversed]),
          border: Border.all(color: Colors.white.withOpacity(.6)),
          boxShadow: [BoxShadow(color: Colors.white.withOpacity(.5), blurRadius: 3)],
        )),
      ]),
    ),
  );
}

Future<void> showRoomLevelSheet(BuildContext context, RoomLevelData data) {
  return showModalBottomSheet<void>(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => Directionality(textDirection: TextDirection.rtl, child: _RoomLevelSheet(data: data)),
  );
}

class _RoomLevelSheet extends StatefulWidget {
  const _RoomLevelSheet({required this.data});
  final RoomLevelData data;
  @override
  State<_RoomLevelSheet> createState() => _RoomLevelSheetState();
}
class _RoomLevelSheetState extends State<_RoomLevelSheet> {
  int _tab = 0;
  Timer? _timer;
  Duration? _left;
  @override
  void initState() {
    super.initState();
    _left = widget.data.dailyResetIn;
    if (_left != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() { final n = _left! - const Duration(seconds: 1); _left = n.isNegative ? Duration.zero : n; });
      });
    }
  }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
  String _fmt(Duration d) => '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return SizedBox(height: MediaQuery.of(context).size.height * .68 + 44, child: Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(top: 44, child: Container(
        decoration: const BoxDecoration(color: _sheetBg, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          _header(d), _progress(d), _tabs(),
          Expanded(child: _tab == 0 ? _levelUpTab(d) : _perksTab(d)),
        ]),
      )),
      PositionedDirectional(end: 10, top: 0, child: _LevelRing(level: d.level, size: 88, colors: roomLevelBadgeColors(d.level))),
    ]));
  }
  Widget _header(RoomLevelData d) => Container(
    height: 74, padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: const BoxDecoration(borderRadius: BorderRadius.vertical(top: Radius.circular(24)), gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_greenDeep, _sheetBg])),
    child: Row(children: [
      CircleAvatar(radius: 24, backgroundColor: Colors.white12, backgroundImage: d.roomAvatar),
      const SizedBox(width: 10),
      Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(d.roomName, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text('ID:${d.roomId}', style: const TextStyle(color: _muted, fontSize: 12)),
      ]),
    ]),
  );
  Widget _progress(RoomLevelData d) {
    final ratio = d.nextLevelExp == 0 ? 0.0 : (d.exp / d.nextLevelExp).clamp(0.0, 1.0).toDouble();
    String short(int n) => n >= 1000000 ? '${(n / 1000000).toStringAsFixed(1)}m' : n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
    return Padding(padding: const EdgeInsets.fromLTRB(14, 4, 14, 6), child: Column(children: [
      ClipRRect(borderRadius: BorderRadius.circular(3), child: Directionality(textDirection: TextDirection.rtl, child: LinearProgressIndicator(value: ratio, minHeight: 5, color: _green, backgroundColor: _track))),
      const SizedBox(height: 6),
      Row(children: [
        Text('نقاط خبرة الغرفة: ${short(d.exp)}/${short(d.nextLevelExp)}', style: const TextStyle(color: _muted, fontSize: 11)),
        const Spacer(),
        Text('Lv.${d.level + 1}', style: const TextStyle(color: _muted, fontSize: 11)),
      ]),
    ]));
  }
  Widget _tabs() => Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 10), child: Row(children: [
    _tabItem('رفع المستوى', 0), const SizedBox(width: 18), _tabItem('الامتيازات', 1),
  ]));
  Widget _tabItem(String title, int index) => GestureDetector(onTap: () => setState(() => _tab = index), child: Text(title, style: TextStyle(fontSize: index == _tab ? 17 : 15, fontWeight: index == _tab ? FontWeight.w800 : FontWeight.w500, color: index == _tab ? Colors.white : _muted)));
  Widget _levelUpTab(RoomLevelData d) => ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 24), children: [
    _dailyCard(d), const SizedBox(height: 10),
    for (final task in d.tasks) ...[_taskCard(task), const SizedBox(height: 10)],
    const SizedBox(height: 6),
    const Text('ملحوظة:', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
    const SizedBox(height: 8),
    Text(d.note, style: const TextStyle(color: _muted, fontSize: 12, height: 1.5)),
  ]);
  Widget _dailyCard(RoomLevelData d) => Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), decoration: BoxDecoration(color: const Color(0xFF16201C), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF22362C))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      const Text('نقاط خبرة الغرفة اليوم:', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
      const Spacer(),
      if (_left != null) ...[Text(_fmt(_left!), style: const TextStyle(color: _muted, fontSize: 12)), const SizedBox(width: 4), const Icon(Icons.schedule, color: _muted, size: 14)],
    ]),
    const SizedBox(height: 10), _bar(d.dailyRatio), const SizedBox(height: 6),
    Text('${d.dailyExpCurrent}/${d.dailyExpMax}', style: const TextStyle(color: _muted, fontSize: 11)),
  ]));
  Widget _taskCard(ExpTask t) => Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3.5), decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: _cardBorder)), child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
    Icon(t.icon, color: Colors.white70, size: 34),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6), Text(t.desc, style: const TextStyle(color: _muted, fontSize: 11, height: 1.5)),
      const SizedBox(height: 10), _bar(t.ratio), const SizedBox(height: 6),
      Text('${t.current}/${t.max}', style: const TextStyle(color: _muted, fontSize: 11)),
    ])),
  ]));
  Widget _bar(double ratio) => ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: ratio.clamp(0.0, 1.0).toDouble(), minHeight: 4, color: _green, backgroundColor: _track));
  Widget _perksTab(RoomLevelData d) => ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 24), children: [
    for (final group in d.perkGroups) ...[
      Padding(padding: const EdgeInsets.fromLTRB(2, 14, 2, 10), child: Row(children: [
        Text('Lv.${group.level}', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(width: 6),
        if (group.level > d.level) const Icon(Icons.lock, color: _muted, size: 14) else const Icon(Icons.check_box, color: Colors.white, size: 16),
      ])),
      for (final perk in group.perks) ...[_perkCard(perk), const SizedBox(height: 8)],
    ],
  ]);
  Widget _perkCard(LevelPerk p) => Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14), decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(14)), child: Row(children: [
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(p.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      if (p.subtitle != null) ...[const SizedBox(height: 4), Text(p.subtitle!, style: const TextStyle(color: _muted, fontSize: 11))],
    ])),
    const SizedBox(width: 12),
    Container(width: 44, height: 44, decoration: BoxDecoration(color: (p.iconColor ?? _green).withOpacity(.15), borderRadius: BorderRadius.circular(12)), child: Icon(p.icon, color: p.iconColor ?? _green, size: 26)),
  ]));
}

class _LevelRing extends StatelessWidget {
  const _LevelRing({required this.level, required this.size, required this.colors});
  final int level;
  final double size;
  final List<Color> colors;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _RingPainter(colors), child: Center(child: Container(
    width: size * .5, height: size * .5, alignment: Alignment.center,
    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0xFF5BD18A), Color(0xFF1E6B3C)])),
    child: Text('$level', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic)),
  ))));
}
class _RingPainter extends CustomPainter {
  const _RingPainter(this.colors);
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 5;
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 7..shader = SweepGradient(colors: colors).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, 2 * math.pi, false, paint);
    canvas.drawCircle(center, radius - 6, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = Colors.white24);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
