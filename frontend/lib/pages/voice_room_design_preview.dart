import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:happy_live/models/seat_state.dart';

class VoiceRoomDesignPreview extends StatelessWidget {

  const VoiceRoomDesignPreview({
    super.key,
    required this.room,
    required this.seats,
    this.speakerLevels = const <int, double>{},
    required this.onTapSeat,
    required this.isChangingSeat,
    this.pendingSeatNumbers = const <int>{},
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
    required this.chatController,
    required this.chatFocusNode,
    required this.onSendChat,
  });
  final Map<String, dynamic> room;
  final List<Map<String, dynamic>> seats;
  final Map<int, double> speakerLevels;
  final ValueChanged<int> onTapSeat;
  final bool isChangingSeat;
  final Set<int> pendingSeatNumbers;
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
  final TextEditingController chatController;
  final FocusNode chatFocusNode;
  final Future<void> Function() onSendChat;

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
      backgroundColor: const Color(0xFF0E1A3A),
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0E1A3A),
                  Color(0xFF1B1840),
                  Color(0xFF4A2346),
                  Color(0xFF7A3A4A),
                ],
                stops: [0, .35, .75, 1],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _header(context),
                _subHeader(context),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Keep the original vertical layout and visual offsets.
                    // The audience strip is painted first so the microphone
                    // seats remain the top hit-test layer where they overlap.
                    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
                    final tileWidth = (constraints.maxWidth - 36) / 4;
                    final seatsHeight = (tileWidth / .88) * 2 + 7;
                    return SizedBox(
                      height: seatsHeight + 43,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            top: seatsHeight + 3,
                            left: 0,
                            right: 0,
                            child: _listeners(context),
                          ),
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: Transform.translate(
                              offset: isAndroid ? const Offset(0, -5) : Offset.zero,
                              child: _seats(context),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (chatMessagesPanel != null)
                        Positioned(
                          left: 98,
                          width: MediaQuery.sizeOf(context).width * 0.75,
                          top: Theme.of(context).platform == TargetPlatform.android
                              ? -92
                              : 50,
                          bottom: Theme.of(context).platform == TargetPlatform.android
                              ? 8
                              : -42,
                          child: Transform.translate(
                            // Keep the chat exactly where it was painted, but
                            // move its hit-test bounds below the lower mic row.
                            offset: Theme.of(context).platform == TargetPlatform.android
                                ? Offset.zero
                                : const Offset(0, -100),
                            transformHitTests: false,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              transform: Matrix4.translationValues(
                                0,
                                -MediaQuery.viewInsetsOf(context).bottom,
                                0,
                              ),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.transparent,
                                ),
                                child: chatMessagesPanel!,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 12,
                        bottom: Theme.of(context).platform == TargetPlatform.android
                            ? 36
                            : 68,
                        child: Column(
                          children: const [
                            _RoomGameTile(
                              color1: Color(0xFF3FA7D6),
                              color2: Color(0xFFE8A04A),
                              badge: 'BET',
                              timer: '19s',
                            ),
                            SizedBox(height: 8),
                            _RoomGameTile(
                              color1: Color(0xFF7A1F2B),
                              color2: Color(0xFFC9972C),
                              badge: 'VIP EXP ×1.8',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _bottomBar(context),
                SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 8),
              ],
            ),
          ),
          _roomActionsPanel(context),
        ],
      ),
    ),
  );

  Widget _pill(Widget child, {EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6)}) =>
    Container(padding: padding, decoration: BoxDecoration(color: Colors.black.withOpacity(.28), borderRadius: BorderRadius.circular(18)), child: child);

  Widget _header(BuildContext context) {
    final avatar = (room['ownerAvatar'] ?? room['ownerAvatarUrl'] ?? _cover ?? '').toString();
    final trophies = (room['trophies'] ?? room['trophyCount'] ?? 0).toString();
    return Transform.translate(
      offset: Theme.of(context).platform == TargetPlatform.android
          ? const Offset(0, -17)
          : Offset.zero,
      child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          SizedBox(
            width: (MediaQuery.sizeOf(context).width * .60).clamp(175.0, 235.0),
            child: Container(
              padding: const EdgeInsetsDirectional.only(start: 0, end: 6, top: 4, bottom: 4),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Transform.translate(
                      offset: const Offset(2, 0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(.20),
                          borderRadius: const BorderRadiusDirectional.only(
                            topStart: Radius.circular(8),
                            bottomStart: Radius.circular(8),
                            topEnd: Radius.circular(22),
                            bottomEnd: Radius.circular(22),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 38,
                      height: 37,
                      child: avatar.startsWith('http')
                          ? Image.network(avatar, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const ColoredBox(
                                color: Colors.white12,
                                child: Icon(Icons.person, color: Colors.white70),
                              ))
                          : const ColoredBox(
                              color: Colors.white12,
                              child: Icon(Icons.person, color: Colors.white70),
                            ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Transform.translate(
                                    offset: const Offset(0, -2),
                                    child: Text(
                                      'ID: $_id',
                                      style: const TextStyle(color: Colors.white60, fontSize: 9),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            Transform.translate(
                              offset: const Offset(0, 3),
                              child: Container(
                                width: 44,
                                height: 30,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFD4AF37),
                                      Color(0xFFF5E9C6),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: const Color(0xFFB8962E),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 20,
                                  weight: 800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
                ],
              ),
            ),
          ),
          const Spacer(),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(.3),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(trophies, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                const Text('🏆', style: TextStyle(fontSize: 16)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _headerAction(Icons.close_rounded, () => _showSaveLeaveDialog(context), 28),
        ],
      ),
      ),
    );
  }

  Widget _headerAction(IconData icon, VoidCallback? onTap, double size) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: 28,
          height: 42,
          child: Icon(icon, color: Colors.white, size: size),
        ),
      );

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
                      crossAxisSpacing: 9,
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

  Widget _subHeader(BuildContext context) => Transform.translate(
    offset: Theme.of(context).platform == TargetPlatform.android
        ? const Offset(0, -10)
        : Offset.zero,
    child: Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(12, 9, 12, 0),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Transform.translate(
        offset: Theme.of(context).platform == TargetPlatform.android
            ? const Offset(0, -10)
            : Offset.zero,
        child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.30),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔥', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(
              (room['hotRankText'] ?? 'الساعة رقم 100+').toString(),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
        ),
      ),
    ),
    ),
  );

  Widget _seats(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 8,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 7,
        crossAxisSpacing: 4,
        childAspectRatio: .88,
      ),
      itemBuilder: (context, index) {
        final number = index + 1;
        return Selector<SeatStateStore, SeatState>(
          selector: (context, store) => store.seats[number]!,
          builder: (context, seatState, child) {
        final seat = seatState.occupied ? seatState.toMap() : null;
        final occupied = seat != null;
        final mine = seat?['isMe'] == true;
        final name = (seat?['name'] ?? '').toString();
        final avatar = (seat?['avatar'] ?? seat?['avatarUrl'] ?? seat?['photoUrl'] ?? '').toString();
        final muted = seat?['isMuted'] == true;
        final locked = seat?['isLocked'] == true || seat?['locked'] == true;
        final speakerUid = seat?['uid'] is num
            ? (seat!['uid'] as num).toInt()
            : int.tryParse((seat?['userCode'] ?? '').toString());
        final voiceLevel = speakerUid == null ? 0.0 : (speakerLevels[speakerUid] ?? 0.0);
        final isSpeaking = occupied && !muted && voiceLevel >=
            (Theme.of(context).platform == TargetPlatform.android ? 0.02 : 0.6);
        final isAndroid = Theme.of(context).platform == TargetPlatform.android;
        final seatOffset = isAndroid
            ? (number <= 4 ? 2.0 : -12.0)
            : (number <= 4 ? -5.0 : -21.0);
        return Transform.translate(
          offset: Offset(0, seatOffset + (isAndroid ? 0 : 5)),
          child: Transform.translate(
            offset: Offset(0, seatOffset),
            child: Align(
              alignment: Alignment.topCenter,
              child: Transform.translate(
                offset: number == 5 ? const Offset(5, 0) : Offset.zero,
                child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: occupied
                    ? (avatar.startsWith('http') ? () => _showUserProfile(context, seat!) : null)
                    : (!isChangingSeat &&
                            !seatState.isPending &&
                            (canModerateUsers || !locked)
                        ? () {
                            if (canModerateUsers) {
                              _showEmptySeatActions(context, number);
                            } else {
                              onTapSeat(number);
                            }
                          }
                        : null),
                child: SizedBox(
                  width: 72,
                  height: number == 5 ? 82 : 72,
                  child: Transform.translate(
                    offset: Offset(number == 5 ? -5 : 0, number > 4 ? 5 : 0),
                    transformHitTests: false,
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _GoldenVoiceWave(
                    isSpeaking: isSpeaking,
                    avatarSize: 54,
                    rippleStartSize: 60,
                    rippleEndSize: 76,
                    avatar: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 460),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final curved = CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                          reverseCurve: Curves.easeInCubic,
                        );
                        return FadeTransition(
                          opacity: curved,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, .55),
                              end: Offset.zero,
                            ).animate(curved),
                            child: ScaleTransition(
                              scale: Tween<double>(begin: .88, end: 1).animate(curved),
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: Container(
                      key: ValueKey<String>(seat?['userId']?.toString().isNotEmpty == true
                          ? seat!['userId'].toString()
                          : 'empty-$number'),
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(.10),
                        border: Border.all(
                          color: mine ? Colors.transparent : Colors.white.withOpacity(occupied ? .60 : .18),
                          width: mine ? 0 : occupied ? 2 : 1,
                        ),
                        image: avatar.startsWith('http')
                            ? DecorationImage(image: NetworkImage(avatar), fit: BoxFit.cover)
                            : null,
                      ),
                      child: avatar.startsWith('http')
                          ? null
                          : Icon(
                              occupied ? Icons.mic_rounded : locked ? Icons.lock_outline : Icons.weekend_outlined,
                              color: Colors.white.withOpacity(.78),
                              size: 21,
                            ),
                      ),
                    ),
                  ),

                  if (muted)
                    Positioned(
                      bottom: -2,
                      left: -2,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: Icon(
                            muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                            size: 11,
                            color: muted ? const Color(0xFFE91E63) : const Color(0xFF319B70),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (occupied)
                Container(
                  constraints: const BoxConstraints(maxWidth: 78),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    name.isEmpty ? 'مستخدم' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                )
              else
                Transform.translate(
                  offset: const Offset(0, 2),
                  child: Text(
                    locked ? 'مقفل' : '$number',
                    style: TextStyle(color: Colors.white.withOpacity(.65), fontSize: 13),
                  ),
                ),
                    ],
                    ),
                  ),
                ),
                ),
              ),
            ),
          ),
        );
          },
        );
      },
    ),
  );

  void _showEmptySeatActions(BuildContext context, int seatNumber) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(.58),
      isScrollControlled: true,
      enableDrag: true,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            10,
            10,
            10,
            MediaQuery.of(sheetContext).padding.bottom + 8,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF211936),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            border: Border(top: BorderSide(color: Color(0xFF493866), width: 1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _EmptySeatAction(
                    icon: Icons.lock_outline_rounded,
                    label: 'إغلاق المايك',
                    onTap: () {},
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _EmptySeatAction(
                    icon: Icons.mic_off_rounded,
                    label: 'ميوت',
                    onTap: () {},
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _EmptySeatAction(
                    icon: Icons.business_center_outlined,
                    label: 'دعوة',
                    onTap: () {},
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _EmptySeatAction(
                    icon: Icons.weekend_outlined,
                    label: 'اطلع المايك',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onTapSeat(seatNumber);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
    ExitMenuOverlay.show(
      context,
      onLeave: () => onCloseRoom?.call(),
      onMinimize: () => onMinimizeRoom?.call(),
    );
  }

  Widget _listeners(BuildContext context) => Transform.translate(
    offset: Theme.of(context).platform == TargetPlatform.android
        ? const Offset(0, -112)
        : const Offset(0, -65),
    child: Container(
    height: 40,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withOpacity(.10)),
    ),
    child: Row(
      children: [
        Expanded(
          child: audienceUsers.isEmpty
              ? const SizedBox.shrink()
              : Directionality(
                  textDirection: TextDirection.rtl,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: false,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    child: Row(
                    children: audienceUsers.map((user) {
                      final avatar = (user['avatarUrl'] ??
                              user['avatar'] ??
                              user['photoUrl'] ??
                              '')
                          .toString();
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(end: 7),
                        child: CircleAvatar(
                          radius: 15,
                          backgroundColor: Colors.white24,
                          backgroundImage: avatar.startsWith('http')
                              ? NetworkImage(avatar)
                              : null,
                          child: !avatar.startsWith('http')
                              ? const Icon(Icons.person,
                                  color: Colors.white70, size: 18)
                              : null,
                        ),
                      );
                    }).toList(),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Container(width: 1, height: 26, color: Colors.white12),
        const SizedBox(width: 10),
        Text('$audienceCount',
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        const SizedBox(width: 5),
        const Icon(Icons.person_outline, color: Colors.white, size: 19),
      ],
    ),
  ));

  void _openChatComposer(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'إغلاق الدردشة',
      barrierColor: Colors.black.withOpacity(.48),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (dialogContext.mounted) chatFocusNode.requestFocus();
        });
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                // تبقى رسائل الغرفة الحقيقية ظاهرة خلف طبقة التعتيم.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: Material(
                      color: const Color(0xFF1B1A22),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          10,
                          9,
                          10,
                          MediaQuery.of(dialogContext).viewInsets.bottom + 9,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'الصور',
                              onPressed: () {},
                              icon: const Icon(Icons.image_outlined,
                                  color: Colors.white70, size: 27),
                            ),
                            Expanded(
                              child: Container(
                                constraints: const BoxConstraints(minHeight: 52),
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(.08),
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      tooltip: 'تنسيق النص',
                                      onPressed: () {},
                                      icon: const Icon(Icons.text_fields,
                                          color: Colors.white70, size: 25),
                                    ),
                                    Expanded(
                                      child: TextField(
                                        controller: chatController,
                                        focusNode: chatFocusNode,
                                        minLines: 1,
                                        maxLines: 4,
                                        maxLength: 100,
                                        inputFormatters: [
                                          LengthLimitingTextInputFormatter(100),
                                        ],
                                        textDirection: TextDirection.rtl,
                                        textInputAction: TextInputAction.send,
                                        onSubmitted: (_) => onSendChat(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                        decoration: const InputDecoration(
                                          counterText: '',
                                          hintText: 'قل شيئًا',
                                          hintStyle: TextStyle(
                                            color: Colors.white38,
                                            fontSize: 16,
                                          ),
                                          border: InputBorder.none,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'الملصقات',
                                      onPressed: () {},
                                      icon: const Icon(
                                        Icons.face_retouching_natural,
                                        color: Colors.white70,
                                        size: 25,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            AnimatedBuilder(
                              animation: chatController,
                              builder: (context, child) {
                                final enabled =
                                    chatController.text.trim().isNotEmpty;
                                return GestureDetector(
                                  onTap: enabled ? onSendChat : null,
                                  child: Container(
                                    width: 54,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: enabled
                                          ? const Color(0xFF8E2DE2)
                                          : Colors.white.withOpacity(.08),
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    child: Icon(
                                      Icons.send_rounded,
                                      color: enabled
                                          ? Colors.white
                                          : Colors.white30,
                                      size: 24,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(opacity: curved, child: child);
      },
    ).whenComplete(() => chatFocusNode.unfocus());
  }

  Widget _bottomBar(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 5, 16, 0),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            InkWell(
              onTap: () => _openChatComposer(context),
              borderRadius: BorderRadius.circular(30),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white38),
                  color: Colors.black.withOpacity(.20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chat_bubble_outline, color: Colors.white, size: 23),
                    SizedBox(width: 7),
                    Text('مرحبا', style: TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.mail_outline, color: Colors.white, size: 30),
                Positioned(
                  top: -9,
                  left: -8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4D8D),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('90', style: TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.sports_esports_outlined, color: Colors.white, size: 30),
            const SizedBox(width: 13),
            const Icon(Icons.card_giftcard, color: Color(0xFFFFA726), size: 32),
            const SizedBox(width: 13),
            const Icon(Icons.apps, color: Colors.white, size: 30),
          ],
        ),
      ),
    );
  }

}


class _RoomGameTile extends StatelessWidget {
  const _RoomGameTile({
    required this.color1,
    required this.color2,
    required this.badge,
    this.timer,
  });

  final Color color1;
  final Color color2;
  final String badge;
  final String? timer;

  @override
  Widget build(BuildContext context) => Container(
    width: 72,
    height: 72,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color1, color2],
      ),
    ),
    child: Stack(
      children: [
        if (timer != null)
          Positioned(
            top: 3,
            right: 6,
            child: Text(timer!, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        Positioned(
          bottom: 4,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: timer != null ? const Color(0xFF3B8DEB) : Colors.black26,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    ),
  );
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
                    const SizedBox(height: 8),
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

class _EmptySeatAction extends StatelessWidget {
  const _EmptySeatAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFF34294D),
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: const Color(0xFFE5DFF0), size: 26),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFB9AACF),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
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

class _NightSky extends StatefulWidget {
  const _NightSky();

  @override
  State<_NightSky> createState() => _NightSkyState();
}

class _NightSkyState extends State<_NightSky> with SingleTickerProviderStateMixin {
  late final AnimationController _twinkle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void dispose() {
    _twinkle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _twinkle,
    builder: (context, child) => CustomPaint(
      painter: _SkyPainter(_twinkle.value),
      child: child,
    ),
  );

}

class _SkyPainter extends CustomPainter {
  const _SkyPainter(this.phase);
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0F5560), Color(0xFF0A3440), Color(0xFF08202B), Color(0xFF060F16)], stops: [0, .35, .7, 1]).createShader(rect));
    final rnd = math.Random(7);
    final stars = List.generate(140, (index) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height * .7;
      final radius = rnd.nextDouble() * 1.2 + .3;
      return (dx, dy, radius, rnd.nextDouble() * math.pi * 2);
    });
    final star = Paint();
    for (var i = 0; i < stars.length; i++) {
      final (dx, dy, radius, offset) = stars[i];
      final shimmer = (math.sin(phase * math.pi * 2 + offset) + 1) / 2;
      star.color = Colors.white.withOpacity(.18 + shimmer * .62);
      canvas.drawCircle(Offset(dx, dy), radius * (.8 + shimmer * .35), star);
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
  bool shouldRepaint(covariant _SkyPainter oldDelegate) => oldDelegate.phase != phase;
}

/// نافذة خيارات زر X: مغادرة الغرفة أو تصغيرها.
class ExitMenuOverlay extends StatelessWidget {
  final VoidCallback onLeave;
  final VoidCallback onMinimize;

  const ExitMenuOverlay({
    super.key,
    required this.onLeave,
    required this.onMinimize,
  });

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onLeave,
    required VoidCallback onMinimize,
  }) {
    return Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (_, __, ___) =>
          ExitMenuOverlay(onLeave: onLeave, onMinimize: onMinimize),
      transitionsBuilder: (_, animation, __, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: child,
        );
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xF2121217),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: SafeArea(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ExitHalfPanel(
                    fromRight: true,
                    icon: Icons.close_fullscreen,
                    label: 'تصغير',
                    onTap: () {
                      Navigator.of(context).pop();
                      onMinimize();
                    },
                  ),
                  _ExitHalfPanel(
                    fromRight: false,
                    icon: Icons.power_settings_new,
                    label: 'اغلاق',
                    onTap: () {
                      Navigator.of(context).pop();
                      onLeave();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExitHalfPanel extends StatefulWidget {
  final bool fromRight;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ExitHalfPanel({
    required this.fromRight,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_ExitHalfPanel> createState() => _ExitHalfPanelState();
}

class _ExitHalfPanelState extends State<_ExitHalfPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: Offset(widget.fromRight ? 1 : -1, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  ));

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SlideTransition(
        position: _slide,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: 150,
            decoration: const BoxDecoration(
              color: Colors.transparent,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(.10),
                  ),
                  child: Icon(
                    widget.icon,
                    color: Colors.white.withOpacity(.88),
                    size: 38,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(.72),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
class _SeatVoiceBars extends StatelessWidget {
  const _SeatVoiceBars(this.level);
  final double level;

  @override
  Widget build(BuildContext context) {
    final strength = level.clamp(0.0, 1.0).toDouble();
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xEE17121F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9A93C), width: .8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, (i) {
        final h = (5 + ((i * 7) % 9) * strength).clamp(3.0, 14.0).toDouble();
        return Container(
          width: 2.5,
          height: h,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: i.isEven ? const Color(0xFFFFD98B) : const Color(0xFFB98AF0),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      })),
    );
  }
}

class _SeatVoiceGlowPainter extends CustomPainter {
  const _SeatVoiceGlowPainter(this.level);
  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    final strength = level.clamp(0.0, 1.0).toDouble();
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * .49 + 2 + strength * 5;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 + strength
      ..color = const Color(0xFFE8C477).withOpacity(.35 + strength * .45)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + strength * 3);
    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(center, radius + 4, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFB98AF0).withOpacity(.35));
  }

  @override
  bool shouldRepaint(covariant _SeatVoiceGlowPainter oldDelegate) =>
      (oldDelegate.level - level).abs() > .03;
}


/// موجات ذهبية متتابعة حول صورة صاحب المايك عند اكتشاف صوته من Agora.
class _GoldenVoiceWave extends StatefulWidget {
  const _GoldenVoiceWave({
    required this.isSpeaking,
    required this.avatar,
    this.avatarSize = 48,
    this.rippleStartSize = 60,
    this.rippleEndSize = 120,
  });

  final bool isSpeaking;
  final Widget avatar;
  final double avatarSize;
  final double rippleStartSize;
  final double rippleEndSize;

  @override
  State<_GoldenVoiceWave> createState() => _GoldenVoiceWaveState();
}

class _GoldenVoiceWaveState extends State<_GoldenVoiceWave>
    with SingleTickerProviderStateMixin {
  static const int _cycleMs = 2100;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _cycleMs),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isSpeaking) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _GoldenVoiceWave oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSpeaking && !oldWidget.isSpeaking) {
      _controller
        ..reset()
        ..repeat();
    } else if (!widget.isSpeaking && oldWidget.isSpeaking) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inset = (widget.rippleEndSize - widget.avatarSize) / 2;

    return SizedBox(
      width: widget.avatarSize,
      height: widget.avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned(
            left: -inset,
            top: -inset,
            width: widget.rippleEndSize,
            height: widget.rippleEndSize,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: widget.isSpeaking ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) => CustomPaint(
                    painter: _GoldenVoiceRipplePainter(
                      progress: _controller.value,
                      startSize: widget.rippleStartSize,
                      endSize: widget.rippleEndSize,
                    ),
                  ),
                ),
              ),
            ),
          ),
          widget.avatar,
        ],
      ),
    );
  }
}

class _GoldenVoiceRipplePainter extends CustomPainter {
  const _GoldenVoiceRipplePainter({
    required this.progress,
    required this.startSize,
    required this.endSize,
  });

  final double progress;
  final double startSize;
  final double endSize;

  static const Color _gold = Color(0xFFD4AF37);
  static const Color _brightGold = Color(0xFFFFD700);
  static const int _cycleMs = 2100;
  static const int _rippleMs = 1500;
  static const int _staggerMs = 300;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    for (var i = 0; i < 3; i++) {
      final elapsed = progress * _cycleMs - i * _staggerMs;
      if (elapsed < 0 || elapsed > _rippleMs) continue;

      final t = (elapsed / _rippleMs).clamp(0.0, 1.0);
      final eased = Curves.easeOut.transform(t);
      final diameter = startSize + (endSize - startSize) * eased;
      final radius = diameter / 2;
      final opacity = .7 * (1 - eased);
      if (opacity <= 0) continue;

      final bounds = Rect.fromCircle(center: center, radius: radius);
      final shader = const LinearGradient(
        colors: [_gold, _brightGold, _gold],
      ).createShader(bounds);

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..shader = shader
          ..color = Colors.white.withOpacity(opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..shader = shader
          ..color = Colors.white.withOpacity(opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GoldenVoiceRipplePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.startSize != startSize ||
      oldDelegate.endSize != endSize;
}
