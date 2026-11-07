import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    required this.audienceCount,
    this.audienceUsers = const [],
    this.chatMessagesPanel,
    this.ownerName = 'صاحب الغرفة',
    this.canModerateUsers = false,
    this.selfMicMuted = false,
    this.onToggleSelfMic,
    this.onModerateUser,
    this.showRoomActions = false,
    this.onRoomActions,
    this.onMinimizeRoom,
    this.onCloseRoom,
  });
  final Map<String, dynamic> room;
  final String announcement;
  final bool canEditAnnouncement;
  final VoidCallback onEditAnnouncement;
  final List<Map<String, dynamic>> seats;
  final ValueChanged<int> onTapSeat;
  final bool isChangingSeat;
  final int audienceCount;
  final List<Map<String, dynamic>> audienceUsers;
  final Widget? chatMessagesPanel;
  final String ownerName;
  final bool canModerateUsers;
  final bool selfMicMuted;
  final Future<bool> Function()? onToggleSelfMic;
  final Future<bool> Function(String targetUserId, String action)? onModerateUser;
  final bool showRoomActions;
  final VoidCallback? onRoomActions;
  final VoidCallback? onMinimizeRoom;
  final VoidCallback? onCloseRoom;

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
        if (chatMessagesPanel != null)
          Positioned(
            left: 58,
            right: 12,
            top: 92,
            bottom: 56,
            child: chatMessagesPanel!,
          ),
        SafeArea(bottom: false, child: Column(children: [
          _header(context),
          _subHeader(),
          _seats(context),
          _listeners(),
          Expanded(child: Stack(children: [
            Positioned.fill(child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
              children: [
                if (announcement.trim().isNotEmpty &&
                    !announcement.contains('مالك الغرفة') &&
                    !announcement.contains('دخل غرفة'))
                  _Notice(
                    text: announcement,
                    icon: Icons.notifications_rounded,
                    onTap: canEditAnnouncement ? onEditAnnouncement : null,
                  ),

              ],
            )),
            Positioned(left: 12, bottom: 4, child: Column(children: const [
              _SideTile(icon: Icons.campaign_rounded, label: '0%', color: Color(0xFFFFC857)),
              _SideTile(icon: Icons.sports_esports_rounded, label: '', color: Color(0xFFB57BFF)),
              _SideTile(icon: Icons.diamond_rounded, label: '0/2500', color: Color(0xFFFF8A65)),
            ])),
          ])),
          _bottomBar(MediaQuery.viewPaddingOf(context).bottom),
        ])),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !showRoomActions,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRoomActions,
              child: const SizedBox.expand(),
            ),
          ),
        ),
        _roomActionsPanel(context),
      ]),
    ),
  );

  Widget _pill(Widget child, {EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6)}) =>
    Container(padding: padding, decoration: BoxDecoration(color: Colors.black.withOpacity(.28), borderRadius: BorderRadius.circular(18)), child: child);

  Widget _header(BuildContext context) => Directionality(textDirection: TextDirection.ltr, child: Padding(
    padding: const EdgeInsets.fromLTRB(10, 8, 6, 0),
    child: Row(children: [
      InkWell(
        onTap: () => _showRoomMenu(context),
        borderRadius: BorderRadius.circular(20),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: const SizedBox(
          width: 42,
          height: 42,
          child: Icon(Icons.more_horiz_rounded, color: Colors.white, size: 28),
        ),
      ),
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
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showSaveLeaveDialog(context),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          child: const SizedBox(
            width: 38,
            height: 42,
            child: Icon(Icons.chevron_right_rounded, color: Colors.white, size: 30),
          ),
        ),
      ),
    ]),
  ));


  void _showRoomMenu(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'إغلاق قائمة الغرفة',
      barrierColor: Colors.black.withOpacity(.35),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final items = <Map<String, dynamic>>[
          {'icon': Icons.settings_outlined, 'label': 'الإعدادات', 'highlight': false},
          {'icon': Icons.palette_outlined, 'label': 'الخلفية', 'highlight': false},
          {'icon': Icons.lock_outline, 'label': 'قفل الغرفة', 'highlight': false},
          {'icon': Icons.share_outlined, 'label': 'مشاركة', 'highlight': false},
          {'icon': Icons.cleaning_services_outlined, 'label': 'مسح الدردشة', 'highlight': false},
          {'icon': Icons.rocket_launch_outlined, 'label': 'رفع مستوى', 'highlight': true},
          {'icon': Icons.checkroom_outlined, 'label': 'السمة', 'highlight': false},
        ];
        return SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.white,
              elevation: 12,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 16, 10, 20),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisExtent: 100,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 8,
                    ),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final highlighted = item['highlight'] == true;
                      final iconColor = highlighted
                          ? const Color(0xFFFF6A00)
                          : const Color(0xFF555555);
                      final circleColor = highlighted
                          ? const Color(0xFFFFF0E6)
                          : const Color(0xFFF0F0F0);
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('سيتم تفعيل ${item['label']} لاحقاً'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: circleColor,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                item['icon'] as IconData,
                                color: iconColor,
                                size: 28,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item['label'] as String,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF444444),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final slide = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(slide),
          child: child,
        );
      },
    );
  }

    Widget _roomActionsPanel(BuildContext context) => AnimatedPositioned(
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeOutCubic,
    top: showRoomActions ? 0 : -320,
    left: 0,
    right: 0,
    child: IgnorePointer(
      ignoring: !showRoomActions,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 240),
        opacity: showRoomActions ? 1 : 0,
        child: Material(
          color: Colors.transparent,
          child: Container(
            height: 300,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xCC000000),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              border: Border.all(color: const Color(0x88E8C477)),
              boxShadow: const [
                BoxShadow(color: Color(0x99000000), blurRadius: 26, offset: Offset(0, 12)),
              ],
            ),
            child: Row(children: [
              Expanded(child: _roomActionButton(
                icon: Icons.picture_in_picture_alt_rounded,
                label: 'تصغير الغرفة',
                color: const Color(0xFFD9A93C),
                onTap: onMinimizeRoom,
              )),
              const SizedBox(width: 10),
              Expanded(child: _roomActionButton(
                icon: Icons.logout_rounded,
                label: 'إغلاق الغرفة',
                color: const Color(0xFFBD5361),
                onTap: onCloseRoom,
              )),
            ]),
          ),
        ),
      ),
    ),
  );

Widget _roomActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(15),
    child: SizedBox(
      height: 72,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: color, size: 25),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Color(0xFF28232D), fontSize: 11, fontWeight: FontWeight.w800)),
      ]),
    ),
  );

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

  Widget _seats(BuildContext context) => Padding(
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
            onTap: occupied
                ? (avatar.startsWith('http')
                    ? () => _showUserProfile(context, seat!)
                    : null)
                : (canTap ? () => onTapSeat(n) : null),
            child: Container(
              width: 54, height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: occupied ? const Color(0xFF17434C) : Colors.white.withOpacity(.16),
                border: Border.all(color: mine ? const Color(0xFFFFD98B) : Colors.white.withOpacity(.35), width: mine ? 2.5 : 1),
                boxShadow: mine ? const [BoxShadow(color: Color(0x66FFD98B), blurRadius: 12)] : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: occupied && avatar.startsWith('http')
                  ? ClipOval(
                      child: SizedBox.expand(
                        child: Image.network(
                          avatar,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(
                              name.isEmpty ? '؟' : name.characters.first,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    )
                  : Icon(occupied ? Icons.mic_rounded : Icons.add_rounded, color: mine ? const Color(0xFFFFD98B) : Colors.white70, size: 32),
            ),
          ),
          const SizedBox(height: 6),
          Text(occupied ? (name.isNotEmpty ? name : 'مستخدم') : '$n',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ]));
      })),
    ))),
  );

  void _showUserProfile(BuildContext context, Map<String, dynamic> user) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(.55),
      isScrollControlled: true,
      enableDrag: true,
      builder: (sheetContext) => UserInfoBottomSheet(
        user: user,
        isMe: user['isMe'] == true,
        canModerate: canModerateUsers && user['isMe'] != true && user['isRoomOwner'] != true && user['isRoomModerator'] != true,
        selfMicMuted: user['isMe'] == true ? selfMicMuted : user['isMuted'] == true,
        onToggleSelfMic: onToggleSelfMic,
        onModerateUser: onModerateUser,
      ),
    );
  }

  void _showSaveLeaveDialog(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'إغلاق نافذة الغرفة',
      barrierColor: Colors.black.withOpacity(0.35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: double.infinity,
                height: 250,
                color: Colors.black.withOpacity(0.85),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _saveLeaveAction(
                        icon: Icons.close_fullscreen_rounded,
                        label: 'حفظ',
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          onMinimizeRoom?.call();
                        },
                      ),
                      _saveLeaveAction(
                        icon: Icons.power_settings_new_rounded,
                        label: 'مغادرة',
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          onCloseRoom?.call();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final slide = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -0.35), end: Offset.zero).animate(slide),
          child: child,
        );
      },
    );
  }

  Widget _saveLeaveAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(icon, size: 38, color: Colors.black87),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    ),
  );

  Widget _listeners() => Directionality(textDirection: TextDirection.ltr, child: Padding(
    padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
    child: Row(children: [
      _pill(Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$audienceCount', style: const TextStyle(color: Colors.white, fontSize: 12)),
        const SizedBox(width: 3),
        const Icon(Icons.person_outline_rounded, color: Colors.white, size: 16),
      ]), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
      const SizedBox(width: 8),
      Expanded(
        child: SizedBox(
          height: 34,
          child: ClipRect(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              reverse: false,
              primary: false,
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              itemCount: audienceUsers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, index) => SizedBox(
                width: 32,
                height: 32,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF29434A),
                    image: (audienceUsers[index]['avatarUrl'] ?? '').toString().startsWith('https://')
                        ? DecorationImage(
                            image: NetworkImage(audienceUsers[index]['avatarUrl'].toString()),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      _pill(Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 18),
        Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: Colors.white.withOpacity(.8), borderRadius: BorderRadius.circular(3)), child: const Text('ALL', style: TextStyle(color: Color(0xFF123240), fontSize: 8, fontWeight: FontWeight.w900))),
        const SizedBox(width: 10),
        InkWell(
          onTap: onRoomActions,
          borderRadius: BorderRadius.circular(16),
          child: const Padding(
            padding: EdgeInsets.all(2),
            child: Icon(Icons.open_in_full_rounded, color: Colors.white70, size: 16),
          ),
        ),
      ]), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5)),
    ]),
  ));

  Widget _bottomBar(double safeBottomInset) => Directionality(textDirection: TextDirection.ltr, child: Padding(
    padding: EdgeInsets.fromLTRB(10, 6, 10, safeBottomInset + 10),
    child: Row(children: const [
      Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 28),
      SizedBox(width: 14), Icon(Icons.card_giftcard_rounded, color: Color(0xFFFF6FA5), size: 28),
      SizedBox(width: 14), Icon(Icons.menu_rounded, color: Colors.white, size: 28),
      Expanded(child: Padding(padding: EdgeInsets.only(right: 14), child: Text('قل شيئاً...', textAlign: TextAlign.right, style: TextStyle(color: Colors.white54, fontSize: 14)))),
      Icon(Icons.volume_up_rounded, color: Colors.white, size: 28),
    ]),
  ));
}


class UserInfoBottomSheet extends StatelessWidget {
  const UserInfoBottomSheet({
    super.key,
    required this.user,
    required this.isMe,
    required this.canModerate,
    required this.selfMicMuted,
    this.onToggleSelfMic,
    this.onModerateUser,
  });

  final Map<String, dynamic> user;
  final bool isMe;
  final bool canModerate;
  final bool selfMicMuted;
  final Future<bool> Function()? onToggleSelfMic;
  final Future<bool> Function(String targetUserId, String action)? onModerateUser;

  String _value(List<String> keys, [String fallback = '']) {
    for (final key in keys) {
      final value = user[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return fallback;
  }

  int _number(List<String> keys) {
    for (final key in keys) {
      final value = user[key];
      if (value is num) return value.toInt();
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final name = _value(['name', 'displayName', 'username'], 'مستخدم');
    final id = _value(['userCode', 'gaboId', 'publicId', 'gabo_id'], '—');
    final avatar = _value(['avatarUrl', 'avatar', 'photoUrl']);
    final country = _value(['country', 'countryCode'], 'SA').toUpperCase();
    final gender = _value(['gender'], 'male').toLowerCase();
    final badges = user['badges'] is List ? user['badges'] as List : const [0, 0];
    final titleCount = _number(['titleCount']);
    final trophyCount = _number(['trophyCount']);

    return SafeArea(
      top: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 55),
                padding: const EdgeInsets.fromLTRB(18, 62, 18, 18),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF20202A),
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Icon(
                          gender == 'male' ? Icons.male_rounded : Icons.female_rounded,
                          color: gender == 'male' ? const Color(0xFF258BE8) : const Color(0xFFE66A9B),
                          size: 22,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          country == 'SA' ? '🇸🇦' : country,
                          style: const TextStyle(fontSize: 19),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('ID: $id', style: const TextStyle(color: Color(0xFF777782), fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 7),
                        InkWell(
                          onTap: id == '—' ? null : () {
                            Clipboard.setData(ClipboardData(text: id));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم نسخ ID')),
                            );
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.copy_rounded, size: 15, color: Color(0xFF777782)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 17),
                    Row(
                      children: [
                        Expanded(child: _ProfileCountBar(
                          value: badges.isNotEmpty ? badges[0].toString() : '0',
                          color: const Color(0xFF9B704B),
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: _ProfileCountBar(
                          value: badges.length > 1 ? badges[1].toString() : '0',
                          color: const Color(0xFF3988D4),
                        )),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _ProfileInfoCard(
                          title: 'لقب',
                          count: titleCount,
                          color: const Color(0xFFF0E9FC),
                          iconColor: const Color(0xFF9B75D0),
                          icon: Icons.workspace_premium_rounded,
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: _ProfileInfoCard(
                          title: 'كأس التكريم',
                          count: trophyCount,
                          color: const Color(0xFFF8F0E3),
                          iconColor: const Color(0xFFB58B55),
                          icon: Icons.emoji_events_rounded,
                        )),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (isMe)
                      _ProfileActionButton(
                        icon: selfMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        label: selfMicMuted ? 'فتح المايك' : 'كتم المايك',
                        color: selfMicMuted ? const Color(0xFFB64A55) : const Color(0xFF2866B8),
                        onTap: onToggleSelfMic == null ? null : () async {
                          final ok = await onToggleSelfMic!();
                          if (ok && context.mounted) Navigator.of(context).pop();
                        },
                      )
                    else if (canModerate)
                      Row(
                        children: [
                          Expanded(child: _ProfileActionButton(
                            icon: selfMicMuted ? Icons.mic_rounded : Icons.mic_off_rounded,
                            label: selfMicMuted ? 'إلغاء الكتم' : 'كتم',
                            color: const Color(0xFF347FC1),
                            onTap: onModerateUser == null ? null : () async {
                              final ok = await onModerateUser!(user['userId'].toString(), 'toggle_mute');
                              if (ok && context.mounted) Navigator.of(context).pop();
                            },
                          )),
                          const SizedBox(width: 7),
                          Expanded(child: _ProfileActionButton(
                            icon: Icons.logout_rounded,
                            label: 'طرد',
                            color: const Color(0xFFD18A32),
                            onTap: onModerateUser == null ? null : () async {
                              final ok = await onModerateUser!(user['userId'].toString(), 'kick');
                              if (ok && context.mounted) Navigator.of(context).pop();
                            },
                          )),
                          const SizedBox(width: 7),
                          Expanded(child: _ProfileActionButton(
                            icon: Icons.block_rounded,
                            label: 'حظر',
                            color: const Color(0xFFB84250),
                            onTap: onModerateUser == null ? null : () async {
                              final ok = await onModerateUser!(user['userId'].toString(), 'ban');
                              if (ok && context.mounted) Navigator.of(context).pop();
                            },
                          )),
                          const SizedBox(width: 7),
                          Expanded(child: _ProfileActionButton(
                            icon: Icons.vertical_align_bottom_rounded,
                            label: 'إنزال',
                            color: const Color(0xFF7953B5),
                            onTap: onModerateUser == null ? null : () async {
                              final ok = await onModerateUser!(user['userId'].toString(), 'lower');
                              if (ok && context.mounted) Navigator.of(context).pop();
                            },
                          )),
                        ],
                      ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 5),
                    boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 4))],
                    image: avatar.startsWith('http')
                        ? DecorationImage(image: NetworkImage(avatar), fit: BoxFit.cover)
                        : null,
                    color: const Color(0xFFE8E4EC),
                  ),
                  child: avatar.startsWith('http')
                      ? null
                      : const Icon(Icons.person_rounded, size: 58, color: Color(0xFF9A93A1)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileCountBar extends StatelessWidget {
  const _ProfileCountBar({required this.value, required this.color});
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
    child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
  );
}

class _ProfileInfoCard extends StatelessWidget {
  const _ProfileInfoCard({
    required this.title,
    required this.count,
    required this.color,
    required this.iconColor,
    required this.icon,
  });
  final String title;
  final int count;
  final Color color;
  final Color iconColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    height: 68,
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(13)),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 6),
        Flexible(
          child: Text('$title $count', maxLines: 2, textAlign: TextAlign.center,
            style: TextStyle(color: iconColor, fontSize: 12, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
}

class _ProfileActionButton extends StatelessWidget {
  const _ProfileActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(13),
            boxShadow: [BoxShadow(color: color.withOpacity(.22), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(height: 5),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF45404B), fontSize: 10, fontWeight: FontWeight.w800)),
      ],
    ),
  );
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
