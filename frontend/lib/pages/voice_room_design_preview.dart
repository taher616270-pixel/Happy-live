import 'dart:math' as math;
import 'package:flutter/material.dart';

class VoiceRoomDesignPreview extends StatelessWidget {
  const VoiceRoomDesignPreview({
    super.key,
    required this.room,
    required this.announcement,
    required this.canEditAnnouncement,
    required this.onEditAnnouncement,
    required this.seats,
    required this.onTapSeat,
    required this.isChangingSeat,
  });
  final Map<String, dynamic> room;
  final String announcement;
  final bool canEditAnnouncement;
  final VoidCallback onEditAnnouncement;
  final List<Map<String, dynamic>> seats;
  final ValueChanged<int> onTapSeat;
  final bool isChangingSeat;

  Map<String, dynamic>? _seatAt(int number) {
    for (final seat in seats) {
      if (seat['seatNumber'] == number) return seat;
    }
    return null;
  }

  String get _name => (room['name'] ?? 'غرفة صوتية').toString();
  String get _id => (room['roomCode'] ?? room['id'] ?? '').toString();
  String? get _cover {
    final value = room['imageUrl']?.toString();
    return value != null && value.startsWith('https://') ? value : null;
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: const Color(0xFF08141C),
      body: Stack(fit: StackFit.expand, children: [
        const _NightSky(),
        SafeArea(child: Column(children: [
          _header(),
          _subHeader(),
          _seats(),
          _listeners(),
          Expanded(child: Stack(children: [
            Positioned.fill(child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
              children: [
                _Notice(
                  text: announcement.isEmpty ? 'مرحباً بكم في الغرفة. نتمنى لكم وقتاً ممتعاً.' : announcement,
                  icon: Icons.notifications_rounded,
                  onTap: canEditAnnouncement ? onEditAnnouncement : null,
                ),
                SizedBox(height: 9),
                _Notice(text: 'مالك الغرفة  @ صاحب الغرفة دخل الغرفة', icon: Icons.waving_hand_rounded),
              ],
            )),
            Positioned(left: 12, bottom: 4, child: Column(children: const [
              _SideTile(icon: Icons.campaign_rounded, label: '0%', color: Color(0xFFFFC857)),
              _SideTile(icon: Icons.sports_esports_rounded, label: '', color: Color(0xFFB57BFF)),
              _SideTile(icon: Icons.diamond_rounded, label: '0/2500', color: Color(0xFFFF8A65)),
            ])),
          ])),
          _bottomBar(),
        ])),
      ]),
    ),
  );

  Widget _pill(Widget child, {EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6)}) =>
    Container(padding: padding, decoration: BoxDecoration(color: Colors.black.withOpacity(.28), borderRadius: BorderRadius.circular(18)), child: child);

  Widget _header() => Directionality(textDirection: TextDirection.ltr, child: Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 6, 0),
    child: Row(children: [
      const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 28),
      const SizedBox(width: 8),
      Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 46, height: 46, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFFFD27A), Color(0xFFB8672A)])), child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 26)),
        const Padding(padding: EdgeInsets.only(top: 2), child: Text('2026.11.07', style: TextStyle(color: Colors.white54, fontSize: 8))),
      ]),
      const Spacer(),
      _pill(Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 28, height: 28, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE8892B)), child: const Icon(Icons.military_tech_rounded, color: Colors.white, size: 18)),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 120), child: Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.rtl, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800))),
          Text('ID:$_id', style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ]),
        const SizedBox(width: 8),
        ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 38, height: 38, child: _cover == null ? Container(color: Colors.white24, child: const Icon(Icons.mic_rounded, color: Colors.white70)) : Image.network(_cover!, fit: BoxFit.cover))),
      ]), padding: const EdgeInsets.fromLTRB(6, 5, 6, 5)),
      const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 30),
    ]),
  ));

  Widget _subHeader() => Directionality(textDirection: TextDirection.ltr, child: Padding(
    padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
    child: Row(children: [
      _pill(const Text('هدايا الغرفة 🌻', textDirection: TextDirection.rtl, style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
      const Spacer(),
      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF1E8E5A), borderRadius: BorderRadius.circular(14)), child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Text('Lv.1', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
        SizedBox(width: 4), Icon(Icons.eco_rounded, color: Colors.white, size: 15),
      ])),
    ]),
  ));

  Widget _seats() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
    child: Column(children: List.generate(2, (r) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: List.generate(4, (c) {
        final n = r * 4 + c + 1;
        final seat = _seatAt(n);
        final occupied = seat != null;
        final mine = seat?['isMe'] == true;
        final name = (seat?['name'] ?? '').toString();
        final avatar = (seat?['avatar'] ?? seat?['avatarUrl'] ?? seat?['photoUrl'] ?? '').toString();
        final canTap = (!occupied || mine) && !isChangingSeat;
        return Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canTap ? () => onTapSeat(n) : null,
            child: Container(
              width: 62, height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: occupied ? const Color(0xFF17434C) : Colors.white.withOpacity(.16),
                border: Border.all(color: mine ? const Color(0xFFFFD98B) : Colors.white.withOpacity(.35), width: mine ? 2.5 : 1),
                boxShadow: mine ? const [BoxShadow(color: Color(0x66FFD98B), blurRadius: 12)] : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: occupied && avatar.startsWith('http')
                  ? Image.network(avatar, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: Text(name.isEmpty ? '؟' : name.characters.first, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))
                  : Icon(occupied ? Icons.mic_rounded : Icons.add_rounded, color: mine ? const Color(0xFFFFD98B) : Colors.white70, size: 32),
            ),
          ),
          const SizedBox(height: 6),
          Text(occupied ? (mine ? 'أنت' : name) : '$n',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ]));
      })),
    ))),
  );

  Widget _listeners() => Directionality(textDirection: TextDirection.ltr, child: Padding(
    padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
    child: Row(children: [
      _pill(Row(mainAxisSize: MainAxisSize.min, children: const [
        Text('1', style: TextStyle(color: Colors.white, fontSize: 12)),
        SizedBox(width: 3), Icon(Icons.person_outline_rounded, color: Colors.white, size: 16),
        SizedBox(width: 4), CircleAvatar(radius: 12, backgroundColor: Colors.white24, child: Icon(Icons.person, size: 13, color: Colors.white70)),
      ]), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
      const Spacer(),
      _pill(Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 18),
        Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: Colors.white.withOpacity(.8), borderRadius: BorderRadius.circular(3)), child: const Text('ALL', style: TextStyle(color: Color(0xFF123240), fontSize: 8, fontWeight: FontWeight.w900))),
        const SizedBox(width: 10), const Icon(Icons.open_in_full_rounded, color: Colors.white70, size: 16),
      ]), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5)),
    ]),
  ));

  Widget _bottomBar() => Directionality(textDirection: TextDirection.ltr, child: Padding(
    padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
    child: Row(children: const [
      Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 28),
      SizedBox(width: 14), Icon(Icons.card_giftcard_rounded, color: Color(0xFFFF6FA5), size: 28),
      SizedBox(width: 14), Icon(Icons.menu_rounded, color: Colors.white, size: 28),
      Expanded(child: Padding(padding: EdgeInsets.only(right: 14), child: Text('قل شيئاً...', textAlign: TextAlign.right, style: TextStyle(color: Colors.white54, fontSize: 14)))),
      Icon(Icons.volume_up_rounded, color: Colors.white, size: 28),
    ]),
  ));
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.icon, this.onTap});
  final String text;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(alignment: AlignmentDirectional.centerStart, child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 32, height: 32, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withOpacity(.35)), child: Icon(icon, color: Colors.white70, size: 17)),
        const SizedBox(width: 8),
        Flexible(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), decoration: BoxDecoration(color: Colors.black.withOpacity(.35), borderRadius: BorderRadius.circular(14)), child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5)))),
        if (onTap != null) ...[
          const SizedBox(width: 5),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: Colors.black.withOpacity(.35), shape: BoxShape.circle),
            child: const Icon(Icons.edit_rounded, color: Colors.white70, size: 14),
          ),
        ],
      ])),
    ),
  );
}

class _SideTile extends StatelessWidget {
  const _SideTile({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 46, height: 46, decoration: BoxDecoration(color: Colors.black.withOpacity(.3), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color, size: 26)),
    if (label.isNotEmpty) Text(label, style: const TextStyle(color: Colors.white, fontSize: 9)),
  ]));
}

class _NightSky extends StatelessWidget {
  const _NightSky();
  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _SkyPainter());
}

class _SkyPainter extends CustomPainter {
  const _SkyPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0F5560), Color(0xFF0A3440), Color(0xFF08202B), Color(0xFF060F16)], stops: [0, .35, .7, 1]).createShader(rect));
    final rnd = math.Random(7);
    final star = Paint();
    for (var i = 0; i < 140; i++) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height * .7;
      star.color = Colors.white.withOpacity(.25 + rnd.nextDouble() * .6);
      canvas.drawCircle(Offset(dx, dy), rnd.nextDouble() * 1.2 + .3, star);
    }
    final w = size.width, h = size.height;
    final mountain = Path()
      ..moveTo(0, h * .84)
      ..quadraticBezierTo(w * .12, h * .80, w * .25, h * .76)
      ..quadraticBezierTo(w * .38, h * .68, w * .46, h * .71)
      ..quadraticBezierTo(w * .56, h * .72, w * .66, h * .76)
      ..quadraticBezierTo(w * .84, h * .79, w, h * .78)
      ..lineTo(w, h)..lineTo(0, h)..close();
    canvas.drawPath(mountain, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF16313B), Color(0xFF07131A)]).createShader(Rect.fromLTWH(0, h * .66, w, h * .34)));
  }
  @override
  bool shouldRepaint(covariant _SkyPainter oldDelegate) => false;
}
