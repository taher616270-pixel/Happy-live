import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _sheetBg = Color(0xFF14161F);
const _cardBg = Color(0xFF1E202B);
const _cardBorder = Color(0xFF303440);
const _green = Color(0xFF86E26B);
const _greenDeep = Color(0xFF3E7D45);
const _tealAccent = Color(0xFF2DD4C4);
const _blueAccent = Color(0xFF3FB8F5);
const _muted = Color(0xFF8E919B);
const _track = Color(0xFF3A3D47);

/// الخبرة المطلوبة للوصول إلى المستوى المحدد.
/// كل خمسة مستويات تزيد الخبرة المطلوبة بمقدار 3.3 مليون، بلا حد أقصى.
List<Color> roomLevelBadgeColors(int level) {
  if (level >= 120) return const [Color(0xFF1E6B3A), Color(0xFF3CB35F), Color(0xFF8FD176)];
  if (level >= 105) return const [Color(0xFF8E2A52), Color(0xFF5F1F3F), Color(0xFFD6567F)];
  if (level >= 90) return const [Color(0xFF9A4A9E), Color(0xFF6A2F72), Color(0xFFD27BD6)];
  if (level >= 70) return const [Color(0xFF7B3FA8), Color(0xFF4F2A78), Color(0xFFA56BDB)];
  if (level >= 40) return const [Color(0xFF2F5E9E), Color(0xFF1D3E6E), Color(0xFF69B9F0)];
  if (level >= 10) return const [Color(0xFF2DD4C4), Color(0xFF167F83), Color(0xFF86E26B)];
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
    this.dailyExpCurrent = '0', this.dailyExpMax = '14m',
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
  ExpTask(title: 'اخذ المقعد', desc: '+600 نقاط خبرة الغرفة/5 دقائق المستخدمين الجدد: +1200 نقاط خبرة الغرفة/5 دقائق', current: '0', max: '1m', icon: Icons.mic),
  ExpTask(title: 'ارسل الهدايا في الغرفة', desc: '+1 نقاط خبرة الغرفة / 1 عملة ذهبية (خلال المبارزة: +2 نقاط خبرة الغرفة / 1 عملة ذهبية)', current: '0', max: '13m', icon: Icons.card_giftcard),
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
  const RoomLevelChip({super.key, required this.data, this.onTap});
  final RoomLevelData data;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final colors = roomLevelBadgeColors(data.level);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap ?? () => showRoomLevelSheet(context, data),
      child: Container(
        width: 88,
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: const Color(0xE9161922),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: colors.last.withOpacity(.85), width: 1),
          boxShadow: [
            BoxShadow(color: colors[1].withOpacity(.24), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Center(
                child: ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: colors,
                  ).createShader(bounds),
                  child: Text(
                    'Lv. ${data.level}',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .15,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [colors.last, colors.first]),
                    border: Border.all(color: colors.last.withOpacity(.9), width: 1),
                    boxShadow: [BoxShadow(color: colors.last.withOpacity(.45), blurRadius: 4)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
  bool get _isBurgundyTheme => widget.data.level >= 105 && widget.data.level <= 119;
  bool get _isRoseTheme => widget.data.level >= 90 && widget.data.level <= 104;
  bool get _isPurpleTheme => widget.data.level >= 70 && widget.data.level <= 89;
  bool get _isBlueTheme => widget.data.level >= 40 && widget.data.level <= 69;
  bool get _isTealTheme => widget.data.level >= 10 && widget.data.level <= 39;
  Color get _accentColor => _isBurgundyTheme || _isRoseTheme || _isPurpleTheme ? const Color(0xFF3FC8F0) : _isBlueTheme ? _blueAccent : _isTealTheme ? _tealAccent : _green;
  Timer? _timer;
  Duration? _left;
  Duration _secondsUntilSaudiMidnight() {
    const saudiOffset = Duration(hours: 3);
    final saudiNow = DateTime.now().toUtc().add(saudiOffset);
    final nextSaudiMidnight = DateTime.utc(
      saudiNow.year, saudiNow.month, saudiNow.day + 1,
    );
    final remaining = nextSaudiMidnight.difference(saudiNow);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  void initState() {
    super.initState();
    final serverValue = widget.data.dailyResetIn;
    _left = serverValue != null && serverValue > Duration.zero
        ? serverValue
        : _secondsUntilSaudiMidnight();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        final n = _left! - const Duration(seconds: 1);
        _left = n <= Duration.zero
            ? _secondsUntilSaudiMidnight()
            : n;
      });
    });
  }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
  String _fmt(Duration d) => '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return SizedBox(height: MediaQuery.of(context).size.height * .68 + 44, child: Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(top: 44, child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          border: _isBurgundyTheme ? const Border(top: BorderSide(color: Color(0xFFD6567F), width: 1.2)) : _isRoseTheme ? const Border(top: BorderSide(color: Color(0xFFD27BD6), width: 1.2)) : _isPurpleTheme ? const Border(top: BorderSide(color: Color(0xFFA56BDB), width: 1.2)) : null,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _isBurgundyTheme
                        ? const [Color(0xFF8E2A52), Color(0xFF5F1F3F), Color(0xFF2B1A2E), Color(0xFF14161F)]
                        : _isRoseTheme
                            ? const [Color(0xFF9A4A9E), Color(0xFF6A2F72), Color(0xFF2E1F3F), Color(0xFF14161F)]
                            : _isPurpleTheme
                        ? const [Color(0xFF7B3FA8), Color(0xFF4F2A78), Color(0xFF2A2144), Color(0xFF14161F)]
                        : _isBlueTheme
                        ? const [Color(0xFF2F5E9E), Color(0xFF1D3E6E), Color(0xFF172439), Color(0xFF14161F)]
                        : _isTealTheme
                            ? const [Color(0xFF1F9C94), Color(0xFF17605F), Color(0xFF1B2A38), Color(0xFF14161F)]
                            : const [Color(0xFF3E7D45), Color(0xFF24502F), Color(0xFF1B2230), Color(0xFF14161F)],
                    stops: const [0.0, 0.25, 0.5, 1.0],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(0, -1),
                            radius: 0.8,
                            colors: [Colors.white.withOpacity(0.07), Colors.white.withOpacity(0)],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(child: CustomPaint(painter: _RoomHeaderArcsPainter())),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 1.2,
                      child: ColoredBox(color: _isBurgundyTheme ? const Color(0xFFD6567F) : _isRoseTheme ? const Color(0xFFD27BD6) : _isPurpleTheme ? const Color(0xFFA56BDB) : _isBlueTheme ? const Color(0xFF4F8BD6) : _isTealTheme ? const Color(0xFF3FC1B5) : const Color(0xFF6BAF6A)),
                    ),
                  ],
                ),
              ),
            ),
            Column(children: [
              _header(d), _progress(d), _tabs(),
              Expanded(child: _tab == 0 ? _levelUpTab(d) : _perksTab(d)),
            ]),
          ],
        ),
      )),
      PositionedDirectional(end: 35, top: 0, child: _LevelRing(level: d.level, size: 112, colors: roomLevelBadgeColors(d.level))),
    ]));
  }
  Widget _header(RoomLevelData d) => Container(
    height: 74, padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: const BoxDecoration(borderRadius: BorderRadius.vertical(top: Radius.circular(40)), color: Colors.transparent),
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
      Container(
        decoration: BoxDecoration(boxShadow: [BoxShadow(color: _accentColor.withOpacity(.22), blurRadius: 5, spreadRadius: .3)]),
        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Directionality(textDirection: TextDirection.rtl, child: LinearProgressIndicator(value: ratio, minHeight: 6, color: _accentColor, backgroundColor: _track))),
      ),
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
  Widget _dailyCard(RoomLevelData d) => Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), decoration: BoxDecoration(color: _isBurgundyTheme ? const Color(0xFF2A1824) : _isRoseTheme ? const Color(0xFF2A1F3A) : _isPurpleTheme ? const Color(0xFF231D3A) : _isBlueTheme ? const Color(0xFF18253A) : _isTealTheme ? const Color(0xFF15333A) : const Color(0xFF1F3A2B), borderRadius: BorderRadius.circular(22), border: Border.all(color: _isBurgundyTheme ? const Color(0xFF4A2538) : _isRoseTheme ? const Color(0xFF46325A) : _isPurpleTheme ? const Color(0xFF3A2F5C) : _isBlueTheme ? const Color(0xFF243B5A) : _isTealTheme ? const Color(0xFF1F4B50) : const Color(0xFF2F4A38))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      const Text('نقاط خبرة الغرفة اليوم:', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
      const Spacer(),
      Text(_fmt(_left ?? _secondsUntilSaudiMidnight()), style: const TextStyle(color: _muted, fontSize: 12)), const SizedBox(width: 4), const Icon(Icons.schedule, color: _muted, size: 12),
    ]),
    const SizedBox(height: 10), _bar(d.dailyRatio), const SizedBox(height: 6),
    Text('${d.dailyExpCurrent}/${d.dailyExpMax}', style: const TextStyle(color: _muted, fontSize: 11)),
  ]));
  Widget _taskCard(ExpTask t) => Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1.5), decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(22), border: Border.all(color: _cardBorder)), child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
    if (t.title == 'اخذ المقعد')
      SizedBox(
        width: 42,
        height: 48,
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(Color(0xFFC4CAD4), BlendMode.srcIn),
          child: Image.asset('assets/images/microphone.PNG', fit: BoxFit.contain),
        ),
      )
    else if (t.title == 'ارسل الهدايا في الغرفة')
      SizedBox(
        width: 42,
        height: 48,
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(Color(0xFFC4CAD4), BlendMode.srcIn),
          child: Image.asset('assets/images/gift.PNG', fit: BoxFit.contain),
        ),
      )
    else
      Icon(t.icon, color: Colors.white70, size: 34),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6), Text(t.desc, style: const TextStyle(color: _muted, fontSize: 11, height: 1.5)),
      const SizedBox(height: 6), _bar(t.ratio), const SizedBox(height: 6),
      Text('${t.current}/${t.max}', style: const TextStyle(color: _muted, fontSize: 11)),
    ])),
  ]));
  Widget _bar(double ratio) => Container(decoration: BoxDecoration(boxShadow: [BoxShadow(color: _accentColor.withOpacity(.18), blurRadius: 5, spreadRadius: .2)]), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: ratio.clamp(0.0, 1.0).toDouble(), minHeight: 6, color: _accentColor, backgroundColor: _track)));
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
  Widget _perkCard(LevelPerk p) => Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14), decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(22)), child: Row(children: [
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
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: Image.asset(
            level >= 105 && level <= 119
                ? 'assets/images/room_level_105_119.png'
                : level >= 90 && level <= 104
                    ? 'assets/images/room_level_90_104.png'
                    : level >= 70 && level <= 89
                        ? 'assets/images/room_level_70_89.png'
                        : level >= 40 && level <= 69
                            ? 'assets/images/room_level_40_69.png'
                            : level >= 10 && level <= 39
                                ? 'assets/images/room_level_10_40.PNG'
                                : 'assets/images/user_level_frame.PNG',
            fit: BoxFit.contain,
          ),
        ),
        Transform.translate(
          offset: const Offset(-2, -4),
          child: level >= 1 && level <= 9
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.translate(
                      offset: const Offset(2.5, 3),
                      child: Text(
                        '$level',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.montserrat(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          color: const Color(0xFF2F6F63),
                        ),
                      ),
                    ),
                    ShaderMask(
                      shaderCallback: (r) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFE6FBF1), Color(0xFF8FD3B8)],
                      ).createShader(r),
                      child: Text(
                        '$level',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.montserrat(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                )
              : Text(
                  '$level',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors[2],
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                    shadows: [
                      Shadow(color: colors[2].withOpacity(0.55), blurRadius: 8),
                      const Shadow(color: Colors.black87, blurRadius: 3, offset: Offset(0, 1)),
                    ],
                  ),
                ),
        ),
      ],
    ),
  );
}

class _RoomHeaderArcsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withOpacity(0.08);
    final center = Offset(size.width / 2, -size.width * 0.12);
    for (var i = 0; i < 5; i++) {
      final inset = i * 18.0;
      final rect = Rect.fromCircle(
        center: center,
        radius: size.width * 0.48 - inset,
      );
      canvas.drawArc(rect, 0.18, math.pi - 0.36, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
