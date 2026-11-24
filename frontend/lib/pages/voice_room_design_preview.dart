import '../widgets/voice_seat_chair_icon.dart';
import '../widgets/centered_notification.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../pk/pk_score_bar.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svga/flutter_svga.dart';

import 'package:happy_live/widgets/happy_network_image.dart';
import '../widgets/square_country_flag.dart';
import 'package:happy_live/widgets/room_info_sheet.dart';
import 'package:happy_live/widgets/room_level_sheet.dart';
import 'package:happy_live/room_settings/my_workers_api.dart';
import 'package:happy_live/room_settings/room_settings_controller.dart';
import 'package:happy_live/room_settings/pages/room_settings_page.dart';
import 'room_upgrade_page.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:happy_live/models/seat_state.dart';
import 'package:happy_live/models/mic_layout.dart';
import 'edit_profile_page.dart';
import '../contrib/contrib_api.dart';
import '../cannon/cannon_sheet.dart';
import '../cannon/cannon_api.dart';
import '../cannon/cannon_box_drop_overlay.dart';
import '../cannon/cannon_art.dart';
import '../cannon/cannon_config.dart';
import '../cannon/cannon_service.dart';
import '../cannon/cannon_top_banner.dart'; // Global cannon banner overlay for room view.

Color _micColorFromHex(String value, Color fallback) {
  final hex = value.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return fallback;
  return Color(0xFF000000 | int.parse(hex, radix: 16));
}

class VoiceRoomDesignPreview extends StatelessWidget {
  static final Set<String> _openingRoomInfo = <String>{};

  const VoiceRoomDesignPreview({
    super.key,
    required this.room,
    required this.seats,
    this.speakerLevels = const <int, double>{},
    required this.onTapSeat,
    this.onJoinSeat,
    required this.isChangingSeat,
    this.pendingSeatNumbers = const <int>{},
    required this.audienceCount,
    this.audienceUsers = const [],
    this.chatMessagesPanel,
    this.ownerName = 'صاحب الغرفة',
    this.ownerAvatarUrl = '',
    this.ownerCountryName = '',
    this.isCurrentUserRoomOwner = false,
    this.canModerateUsers = false,
    this.selfMicMuted = false,
    this.onToggleSelfMic,
    this.onModerateUser,
    this.onModerateSeat,
    this.showRoomActions = false,
    this.onRoomActions,
    this.onRoomTools,
    this.onMinimizeRoom,
    this.onCloseRoom,
    this.onPkReset,
    this.onPkStart,
    this.onPkOpen,
    this.onUpgradeRoom,
    this.onOpenGifts,
    this.onRoomSettingsChanged,
    this.onRoomCoverChanged,
    required this.chatController,
    required this.chatFocusNode,
    required this.onSendChat,
    required this.accessToken,
    this.onOpenCannonRoom,
    this.isRoomDataReady = true,
    this.currentUserCode = '',
    this.roomGiftScores = const <String, int>{},
    this.isRoomGiftCounterActive = false,
    this.pkTeamMode = false,
    this.pkActive = false,
    this.pkVisualMode = false,
    this.pkStarted = false,
    this.pkBlueScore = 0,
    this.pkRedScore = 0,
    this.pkUserScores = const <String, int>{},
    this.pkTimerLabel = '05:00',
    this.pkStartingCountdown = false,
    this.pkStartHiding = false,
    this.pkStartHideDurationSeconds = 0.5,
    this.pkStartAnimation,
    this.pkChallengeTitle = 'تحدي PK',
    this.pkShowChallengeTitle = true,
    this.pkShowStartText = true,
    this.pkShowTimer = true,
    this.pkEnabled = true,
    this.pkSquareRadius = 26,
    this.pkSquareWidthPercent = 100,
    this.pkSquareHeight = 284,
    this.pkMediaOpacity = 0.85,
    this.normalMicBorderColor = '#FFFFFF',
    this.normalMicBorderWidth = 1.5,
    this.normalMicFillColor = '#FFFFFF',
    this.normalMicFillOpacity = 0.14,
    this.pkMicBorderColor = '#FFFFFF',
    this.pkMicBorderWidth = 2.4,
    this.pkMicFillColor = '#FFFFFF',
    this.pkMicFillOpacity = 0.12,
    this.pkBlueMicBorderColor = '#258BFF',
    this.pkRedMicBorderColor = '#FF4B5C',
    this.micStyleUrl = '',
    this.micChairStyleUrl = '',
    this.micLockStyleUrl = '',
    this.micCircleScale = 100,
    this.micChairScale = 100,
    this.micLockScale = 100,
    this.micCircleClarity = 100,
    this.micChairClarity = 100,
    this.micLockClarity = 100,
    this.micCircleOpacity = 100,
    this.micChairOpacity = 100,
    this.micLockOpacity = 100,
    this.pkSquareAnimation,
  });
  final Map<String, dynamic> room;
  final List<Map<String, dynamic>> seats;
  final Map<int, double> speakerLevels;
  final ValueChanged<int> onTapSeat;
  final ValueChanged<int>? onJoinSeat;
  final bool isChangingSeat;
  final Set<int> pendingSeatNumbers;
  final int audienceCount;
  final List<Map<String, dynamic>> audienceUsers;
  final Widget? chatMessagesPanel;
  final String ownerName;
  final String ownerAvatarUrl;
  final String ownerCountryName;
  final bool isCurrentUserRoomOwner;
  final bool canModerateUsers;
  final bool selfMicMuted;
  final Future<bool> Function()? onToggleSelfMic;
  final Future<bool> Function(String targetUserId, String action)? onModerateUser;
  final Future<bool> Function(int seatNumber, String action)? onModerateSeat;
  final bool showRoomActions;
  final VoidCallback? onRoomActions;
  final VoidCallback? onRoomTools;
  final VoidCallback? onMinimizeRoom;
  final VoidCallback? onCloseRoom;
  final VoidCallback? onPkReset;
  final VoidCallback? onPkStart;
  final VoidCallback? onPkOpen;
  final Future<void> Function(String roomId, int level)? onUpgradeRoom;
  final VoidCallback? onOpenGifts;
  final VoidCallback? onRoomSettingsChanged;
  final ValueChanged<String>? onRoomCoverChanged;
  final TextEditingController chatController;
  final FocusNode chatFocusNode;
  final Future<void> Function() onSendChat;
  final String accessToken;
  final Future<void> Function(String roomId)? onOpenCannonRoom;
  /// True only after the authenticated room snapshot has loaded from the API.
  final bool isRoomDataReady;
  final String currentUserCode;
  final Map<String, int> roomGiftScores;
  final bool isRoomGiftCounterActive;
  final bool pkTeamMode;
  final bool pkActive;
  final bool pkVisualMode;
  final bool pkStarted;
  final int pkBlueScore;
  final int pkRedScore;
  final Map<String, int> pkUserScores;
  final String pkTimerLabel;
  final bool pkStartingCountdown;
  final bool pkStartHiding;
  final double pkStartHideDurationSeconds;
  final Widget? pkStartAnimation;
  final String pkChallengeTitle;
  final bool pkShowChallengeTitle;
  final bool pkShowStartText;
  final bool pkShowTimer;
  final bool pkEnabled;
  final double pkSquareRadius;
  final double pkSquareWidthPercent;
  final double pkSquareHeight;
  final double pkMediaOpacity;
  final String normalMicBorderColor;
  final double normalMicBorderWidth;
  final String normalMicFillColor;
  final double normalMicFillOpacity;
  final String pkMicBorderColor;
  final double pkMicBorderWidth;
  final String pkMicFillColor;
  final double pkMicFillOpacity;
  final String pkBlueMicBorderColor;
  final String pkRedMicBorderColor;
  final String micStyleUrl;
  final String micChairStyleUrl;
  final String micLockStyleUrl;
  final double micCircleScale;
  final double micChairScale;
  final double micLockScale;
  final double micCircleClarity;
  final double micChairClarity;
  final double micLockClarity;
  final double micCircleOpacity;
  final double micChairOpacity;
  final double micLockOpacity;
  final Widget? pkSquareAnimation;

  Map<String, dynamic>? _seatAt(int number) {
    for (final seat in seats) {
      if (seat['seatNumber'] == number) return seat;
    }
    return null;
  }

  String get _name => (room['name'] ?? 'غرفة صوتية').toString();
  String get _id => (room['roomCode'] ?? room['id'] ?? '').toString();
  // Resolve the active layout exactly like _seats(): older room snapshots
  // may omit micLayoutId and provide only micCount.
  String get _micLayoutId {
    final configuredId =
        _roomInfoString(['micLayoutId', 'mic_layout_id']).trim().toLowerCase();
    if (configuredId.isNotEmpty) return configuredId;
    final micCount =
        int.tryParse(_roomInfoString(['micCount', 'mic_count'], '0')) ?? 0;
    return micCount > 0 ? 'm$micCount' : 'm8';
  }
  bool get _is2MicLayout => _micLayoutId == 'm2';
  bool get _is8MicLayout => _micLayoutId == 'm8';
  bool get _is24MicLayout => _micLayoutId == 'm24';
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
          Positioned.fill(
            child: Image.asset(
              'assets/images/room_background/happy_live_room_bg.png.PNG',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          SafeArea(
            bottom: false,
            child: isRoomDataReady ? Column(
              children: [
                _header(context),
                _subHeader(context),
                const SizedBox(height: 10),
                // Keep the microphone grid, listener strip and everything
                // below it in normal vertical flow. The listener strip now
                // follows the actual measured grid height for every layout.
                if (pkVisualMode) ...[
                  _buildPkRoomView(context),
                  // Lift the PK people strip by 3px without moving the team panels.
                  Transform.translate(
                    offset: const Offset(0, -3),
                    child: _listeners(context, isPk: true),
                  ),
                ] else ...[
                  _seats(context),
                  const SizedBox(height: 1),
                  Transform.translate(
                    // Move the listener strip down 4px only in the 2-mic layout.
                    offset: Offset(0, _is2MicLayout ? -14 : (_is8MicLayout ? -23 : (_micLayoutId == 'm14' ? -33 : -28))),
                    child: _listeners(context),
                  ),
                ],
                SizedBox(height: pkVisualMode ? 5 : 2),
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (chatMessagesPanel != null)
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 98),
                            child: SizedBox(
                              width: MediaQuery.sizeOf(context).width * 0.75,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                transform: Matrix4.translationValues(
                                  0,
                                  (_is2MicLayout ? -11 : (_is8MicLayout ? -20 : (_micLayoutId == 'm14' ? -29 : -25))) +
                                      (pkVisualMode ? 22 : 0) -
                                      MediaQuery.viewInsetsOf(context).bottom,
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
                        ),
                      Positioned.fill(
                        child: _CannonRoomTile(
                          roomId: (room['id'] ?? '').toString().trim(),
                          accessToken: accessToken,
                          enableTestButton: currentUserCode.trim() == '93013793' &&
                              (room['roomCode'] ?? room['id'] ?? room['room_id'] ?? '').toString().trim() == '72187771',
                          bottomOffset: Theme.of(context).platform == TargetPlatform.android
                              ? -4
                              : 28,
                          onTap: () {
                            final cannonRoomId = (room['id'] ?? '').toString().trim();
                            if (cannonRoomId.isEmpty || accessToken.trim().isEmpty) return;
                            CannonService.instance.enterRoom(cannonRoomId, accessToken);
                            showCannonSheet(context, roomId: cannonRoomId, onSendGift: onOpenGifts);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                _bottomBar(context),
                SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 8),
              ],
            ) : _loadingRoomContent(context),
          ),
          if (isRoomDataReady) _roomActionsPanel(context),
          if (isRoomDataReady) CannonGlobalBannerHost(
            child: const SizedBox.expand(),
            accessToken: accessToken,
            onOpenRoom: (roomId) async {
              await onOpenCannonRoom?.call(roomId);
            },
          ),
        ],
      ),
    ),
  );

  /// During entry, expose only the room identity tile and the close control.
  /// Mic seats, chat, gifts and every other action wait for the DB snapshot.
  Widget _buildPkRoomView(BuildContext context) {
    final calculatedBlueScore = pkBlueScore;
    final calculatedRedScore = pkRedScore;

    final roomLayout = micLayoutById(_micLayoutId);
    final seatStore = context.watch<SeatStateStore>();
    final roomSeatNumbers = <int>{
      for (final row in roomLayout.rows)
        for (final slot in row.whereType<MicSeat>())
          roomLayout.seatNumber(slot),
    }.toList()..sort();
    int? firstJoinSeat;
    if (seatStore.mySeat == null) {
      for (final number in roomSeatNumbers) {
        if (number == 3 || number == 8) continue;
        final state = seatStore.seats[number] ?? SeatState.empty(number);
        if (state.occupied ||
            state.isPending ||
            seatStore.isPending(number) ||
            pendingSeatNumbers.contains(number) ||
            state.isLocked) {
          continue;
        }
        firstJoinSeat = number;
        break;
      }
    }
    final overflowSlots = <MicSeat>[];
    for (final row in roomLayout.rows) {
      for (final slot in row.whereType<MicSeat>()) {
        if (roomLayout.seatNumber(slot) > 12) overflowSlots.add(slot);
      }
    }
    overflowSlots.sort(
      (a, b) => roomLayout.seatNumber(a).compareTo(roomLayout.seatNumber(b)),
    );

    final squareHeight = pkSquareHeight.clamp(240.0, 500.0).toDouble();
    final squareWidth = MediaQuery.sizeOf(context).width *
        (pkSquareWidthPercent.clamp(50.0, 100.0).toDouble() / 100);
    return SizedBox(
      height: squareHeight + (overflowSlots.isNotEmpty ? 92 : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: squareHeight,
            child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Team panels touch the score strip with no vertical gap.
          Positioned(
            top: 6,
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: squareWidth,
                height: squareHeight,
                child: Container(
                  margin: const EdgeInsets.only(top: 6),
                  child: Stack(
                children: [
                  if (pkSquareAnimation != null)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(pkSquareRadius),
                          bottomRight: Radius.circular(pkSquareRadius),
                        ),
                        child: IgnorePointer(
                          child: Opacity(
                            // The uploaded PK square replaces the fallback panel.
                            // Full opacity prevents the old blue/red panel ghosting through it.
                            opacity: 1.0,
                            child: pkSquareAnimation!,
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Transform.translate(
                          offset: const Offset(0, 13),
                          child: Row(
                            textDirection: TextDirection.ltr,
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildPkSeatCell(context, 4, joinSeatNumber: firstJoinSeat, currentUserAvatarUrl: seatStore.currentAvatarUrl),
                              _buildPkSeatCell(context, 3, joinSeatNumber: firstJoinSeat, currentUserAvatarUrl: seatStore.currentAvatarUrl),
                              _buildPkSeatCell(context, 2, joinSeatNumber: firstJoinSeat, currentUserAvatarUrl: seatStore.currentAvatarUrl),
                              _buildPkSeatCell(context, 1, joinSeatNumber: firstJoinSeat, currentUserAvatarUrl: seatStore.currentAvatarUrl),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          textDirection: TextDirection.ltr,
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildPkSeatCell(context, 8, joinSeatNumber: firstJoinSeat, currentUserAvatarUrl: seatStore.currentAvatarUrl),
                            _buildPkSeatCell(context, 7, joinSeatNumber: firstJoinSeat, currentUserAvatarUrl: seatStore.currentAvatarUrl),
                            _buildPkSeatCell(context, 6, joinSeatNumber: firstJoinSeat, currentUserAvatarUrl: seatStore.currentAvatarUrl),
                            _buildPkSeatCell(context, 5, joinSeatNumber: firstJoinSeat, currentUserAvatarUrl: seatStore.currentAvatarUrl),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Transform.translate(
                          offset: const Offset(0, -3),
                          child: Row(
                            textDirection: TextDirection.ltr,
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildPkSeatCell(context, 12, joinSeatNumber: firstJoinSeat, currentUserAvatarUrl: seatStore.currentAvatarUrl),
                              _buildPkSeatCell(context, 11, joinSeatNumber: firstJoinSeat, currentUserAvatarUrl: seatStore.currentAvatarUrl),
                              _buildPkSeatCell(context, 10, joinSeatNumber: firstJoinSeat, currentUserAvatarUrl: seatStore.currentAvatarUrl),
                              _buildPkSeatCell(context, 9, joinSeatNumber: firstJoinSeat, currentUserAvatarUrl: seatStore.currentAvatarUrl),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ],
                  ),
                ),
              ),
            ),
          ),
          // PK score strip: dynamic score calculation, scrolling arrows, moving center glowing capsule
          Positioned(
            top: -4,
            left: 0,
            right: 0,
            child: PkScoreBar(
              blue: calculatedBlueScore,
              red: calculatedRedScore,
              tab: pkStarted
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onPkOpen,
                      child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '<',
                          style: TextStyle(
                            color: Color(0x99B8B8C2),
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (pkShowTimer) Text(
                          pkTimerLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Transform.translate(
                          offset: const Offset(-3, 0),
                          child: Transform.rotate(
                            angle: -0.12,
                            child: const Text(
                              'P',
                              style: TextStyle(
                                color: Color(0xFF4D91FF),
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                shadows: [
                                  Shadow(color: Color(0xFFB6D2FF), offset: Offset(-1, -1), blurRadius: 1),
                                  Shadow(color: Color(0xFF173E9A), offset: Offset(1, 2), blurRadius: 2),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 1),
                        Transform.rotate(
                          angle: -0.12,
                          child: const Text(
                            'K',
                            style: TextStyle(
                              color: Color(0xFFFF4B9A),
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              shadows: [
                                Shadow(color: Color(0xFFFFB1D1), offset: Offset(-1, -1), blurRadius: 1),
                                Shadow(color: Color(0xFF8A174F), offset: Offset(1, 2), blurRadius: 2),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    )
                  : null,
            ),
          ),
          if (pkStartingCountdown && pkShowStartText)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: AnimatedOpacity(
                    opacity: pkStartHiding ? 0 : 1,
                    duration: Duration(milliseconds: (pkStartHideDurationSeconds * 1000).round()),
                    curve: Curves.easeOut,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.65, end: 1),
                      duration: const Duration(milliseconds: 550),
                      curve: Curves.elasticOut,
                      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                      child: pkStartAnimation ?? DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xCC101018),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.75), width: 1.5),
                          boxShadow: const [
                            BoxShadow(color: Color(0xAA4F78FF), blurRadius: 24, spreadRadius: 2),
                            BoxShadow(color: Color(0x66FF4B9A), blurRadius: 14),
                          ],
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                          child: Text('START', style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: 3)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (!pkStarted && !pkStartingCountdown && pkEnabled)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onPkStart,
                  child: const StartPkButton(),
                ),
              ),
            ),
        ],
            ),
          ),
          if (overflowSlots.isNotEmpty)
            Transform.translate(
              offset: const Offset(0, 20),
              child: SizedBox(
                height: 72,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: overflowSlots.map((slot) {
                      final number = roomLayout.seatNumber(slot);
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(end: 5),
                        child: _pkOverflowSeat(
                          context,
                          slot,
                          number,
                          joinSeatNumber: firstJoinSeat,
                          currentUserAvatarUrl: seatStore.currentAvatarUrl,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
            ),
        ],
      ),
    );
  }

  Widget _buildPkSeatCell(
    BuildContext context,
    int seatNumber, {
    required int? joinSeatNumber,
    required String currentUserAvatarUrl,
  }) {
    return Selector<SeatStateStore, SeatState>(
      selector: (context, store) => store.seats[seatNumber] ?? SeatState.empty(seatNumber),
      builder: (context, seatState, _) {
        final seat = seatState.occupied ? seatState.toMap() : _seatAt(seatNumber);
        final occupied = seat != null && (seat['userId'] ?? '').toString().isNotEmpty;
        final avatar = (seat?['avatar'] ?? seat?['avatarUrl'] ?? seat?['photoUrl'] ?? '').toString();
        final visibleAvatar = occupied ? avatar : (seatNumber == joinSeatNumber ? currentUserAvatarUrl : '');
        final locked = seatState.isLocked || seat?['isLocked'] == true ||
            seat?['locked'] == true;
        final isMuted = seatState.isMuted || seat?['isMuted'] == true;
        final userId = (seat?['userId'] ?? '').toString();
        final pkPoints = pkUserScores[userId] ?? 0;
        final isBlueTeamSeat = const [3, 4, 7, 8, 11, 12].contains(seatNumber);
        final speakerUid = seat?['uid'] is num
            ? (seat!['uid'] as num).toInt()
            : int.tryParse((seat?['userCode'] ?? '').toString());
        final voiceLevel = speakerUid == null ? 0.0 : (speakerLevels[speakerUid] ?? 0.0);
        final isSpeaking = occupied && !isMuted && voiceLevel >=
            (Theme.of(context).platform == TargetPlatform.android ? 0.02 : 0.6);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canModerateUsers
              ? () => _showEmptySeatActions(context, seatNumber)
              : occupied
                  ? () => _showUserProfile(context, seat!)
                  : () => onTapSeat(seatNumber),
          child: SizedBox(
            width: 58,
            height: 78,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _GoldenVoiceWave(
                      isSpeaking: isSpeaking,
                      isLocked: locked,
                      isOccupied: occupied,
                      micStyleUrl: micStyleUrl,
                      micChairStyleUrl: micChairStyleUrl,
                      micLockStyleUrl: micLockStyleUrl,
                       micCircleScale: micCircleScale,
                      micChairScale: micChairScale,
                      micLockScale: micLockScale,
                      micCircleClarity: micCircleClarity,
                      micChairClarity: micChairClarity,
                      micLockClarity: micLockClarity,
                      micCircleOpacity: micCircleOpacity,
                      micChairOpacity: micChairOpacity,
                      micLockOpacity: micLockOpacity,
                      avatarSize: 46,
                      rippleStartSize: 51,
                      rippleEndSize: 64,
                      avatar: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 460),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: Container(
                          key: ValueKey<String>(userId.isNotEmpty ? userId : 'empty-$seatNumber'),
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: micStyleUrl.startsWith('https://')
                                ? Colors.transparent
                                : occupied
                                    ? Colors.white.withOpacity(.14)
                                    : const Color(0xFF1E1C2B).withOpacity(.70),
                            border: micStyleUrl.startsWith('https://')
                                ? Border.all(color: Colors.transparent, width: 0)
                                : Border.all(
                                    color: Colors.white.withOpacity(occupied ? .82 : .48),
                                    width: 2,
                                  ),
                            boxShadow: micStyleUrl.startsWith('https://')
                                ? const []
                                : const [
                                    BoxShadow(
                                      color: Color(0x99000000),
                                      blurRadius: 9,
                                      spreadRadius: 1,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipOval(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (visibleAvatar.startsWith('http'))
                                      Opacity(
                                        // صورة صاحب الطلب تبقى باهتة إلى أن يشغل المايك فعلياً.
                                        opacity: occupied ? 1 : 0.35,
                                        child: HappyNetworkImage(visibleAvatar, fit: BoxFit.cover),
                                      )
                                    else if (occupied && !micStyleUrl.startsWith('https://'))
                                      Icon(Icons.mic_rounded, color: Colors.white.withOpacity(.92), size: 20)
                                    else if (locked && !micStyleUrl.startsWith('https://'))
                                      Icon(Icons.lock_outline, color: Colors.white.withOpacity(.92), size: 20)
                                    else if (!micStyleUrl.startsWith('https://'))
                                      const Center(
                                        child: CustomPaint(
                                          size: Size(22, 22),
                                          painter: ChairCustomPainter(
                                            color: Color(0xFF9A98A6),
                                            strokeWidth: 2.0,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (!micStyleUrl.startsWith('https://') && !occupied && seatNumber == joinSeatNumber && visibleAvatar.startsWith('http'))
                                const CustomPaint(
                                  painter: _DashedCircleBorderPainter(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (occupied && pkPoints > 0)
                      Positioned(
                        top: -8,
                        right: -7,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 25),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: isBlueTeamSeat ? const Color(0xFF244BDA) : const Color(0xFFB51E58),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: Colors.white.withOpacity(.85), width: .7),
                          ),
                          child: Text(
                            pkPoints >= 1000000
                                ? '${(pkPoints / 1000000).toStringAsFixed(1)}M'
                                : pkPoints >= 1000
                                    ? '${(pkPoints / 1000).toStringAsFixed(1)}K'
                                    : pkPoints.toString(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900, height: 1.1),
                          ),
                        ),
                      ),
                    if (isMuted)
                      Positioned(
                        left: -2,
                        bottom: 0,
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: const Icon(Icons.mic_off_rounded, size: 10, color: Color(0xFFE91E63)),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  occupied
                      ? (seat?['name'] ?? seat?['displayName'] ?? 'مستخدم').toString()
                      : (seatNumber == joinSeatNumber ? 'انضمام' : '$seatNumber'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(occupied ? 1 : .7),
                    fontSize: occupied ? 10 : (seatNumber == joinSeatNumber ? 10 : 12),
                    fontWeight: occupied || seatNumber == joinSeatNumber
                        ? FontWeight.w700
                        : FontWeight.normal,
                    shadows: const [
                      Shadow(color: Color(0xCC000000), blurRadius: 4, offset: Offset(0, 1)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _loadingRoomContent(BuildContext context) {
    final cover = _roomInfoString(['imageUrl', 'image_url', 'coverUrl', 'cover_url']);
    final fallbackAvatar = ownerAvatarUrl.trim().isNotEmpty
        ? ownerAvatarUrl.trim()
        : (room['ownerAvatar'] ?? room['ownerAvatarUrl'] ?? '').toString().trim();
    final image = cover.startsWith('https://') ? cover : fallbackAvatar;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        textDirection: TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Container(
              constraints: BoxConstraints(
                maxWidth: (MediaQuery.sizeOf(context).width * .66).clamp(170.0, 260.0),
              ),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 42,
                      height: 42,
                      child: image.startsWith('https://')
                          ? Image.network(image, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const ColoredBox(
                                color: Colors.white12,
                                child: Icon(Icons.graphic_eq_rounded, color: Colors.white70),
                              ))
                          : const ColoredBox(
                              color: Colors.white12,
                              child: Icon(Icons.graphic_eq_rounded, color: Colors.white70),
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text('ID: $_id', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white60, fontSize: 10)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            InkWell(
              onTap: () => _showSaveLeaveDialog(context),
              borderRadius: BorderRadius.circular(20),
              child: const SizedBox(
                width: 36,
                height: 42,
                child: Icon(Icons.close_rounded, color: Colors.white, size: 28),
              ),
            ),
          ],
        ),
    );
  }

  Widget _pill(Widget child, {EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6)}) =>
    Container(padding: padding, decoration: BoxDecoration(color: Colors.black.withOpacity(.28), borderRadius: BorderRadius.circular(18)), child: child);

  String _roomInfoString(List<String> keys, [String fallback = '']) {
    for (final key in keys) {
      final value = room[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value != 'null') return value;
    }
    return fallback;
  }

  int _roomInfoIntFrom(Map<String, dynamic> source, List<String> keys, [int fallback = 0]) {
    for (final key in keys) {
      final value = source[key];
      if (value is num) return value.toInt();
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  int _roomInfoInt(List<String> keys, [int fallback = 0]) {
    for (final key in keys) {
      final value = room[key];
      if (value is num) return value.toInt();
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  Future<Map<String, dynamic>?> _loadAccountProfile(String userId) async {
    final id = userId.trim();
    if (id.isEmpty || accessToken.trim().isEmpty) return null;
    try {
      final response = await http.get(
        Uri.parse('https://happy-live-api.taher616270.workers.dev/api/v1/users/${Uri.encodeComponent(id)}/profile'),
        headers: {'Authorization': 'Bearer $accessToken'},
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['ok'] != true || decoded['profile'] is! Map) {
        return null;
      }
      return Map<String, dynamic>.from(decoded['profile'] as Map);
    } catch (_) {
      return null;
    }
  }

  String _profileValue(Map<String, dynamic>? profile, List<String> keys) {
    if (profile == null) return '';
    for (final key in keys) {
      final value = profile[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value != 'null') return value;
    }
    return '';
  }

  Future<void> _openRoomLevelSheet(
    BuildContext context,
    Map<String, dynamic> room,
  ) async {
    // Always read the latest counters from the authenticated room snapshot.
    // This same path is used by both the level chip and the room-info shortcut.
    final levelRoom = Map<String, dynamic>.from(room);
    final roomId = (room['id'] ?? room['roomId'] ?? room['room_id'] ?? '').toString().trim();
    if (roomId.isNotEmpty && accessToken.trim().isNotEmpty) {
      try {
        final response = await http.get(
          Uri.parse('https://happy-live-api.taher616270.workers.dev/api/v1/rooms/${Uri.encodeComponent(roomId)}/seats'),
          headers: {'Authorization': 'Bearer $accessToken'},
        ).timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) {
          final payload = jsonDecode(response.body);
          if (payload is Map && payload['room'] is Map) {
            levelRoom.addAll(Map<String, dynamic>.from(payload['room'] as Map));
          } else {
            debugPrint('[room-level] room snapshot missing room payload');
          }
        } else {
          debugPrint('[room-level] snapshot returned HTTP ${response.statusCode}');
        }
      } catch (error) {
        debugPrint('[room-level] fresh experience snapshot failed: $error');
      }
    }
    if (!context.mounted) return;
    final exp = _roomInfoIntFrom(levelRoom, ['experienceExp', 'experience_exp'], 0);
    final level = _roomInfoIntFrom(levelRoom, ['experienceLevel', 'experience_level'], 1)
        .clamp(1, 2147483647).toInt();
    final nextExp = _roomInfoIntFrom(
      levelRoom,
      ['experienceNextLevelExp', 'experience_next_level_exp'],
      roomLevelRequiredExpForLevel(level + 1),
    ).clamp(1, 2147483647).toInt();
    final dailyMax = _roomInfoIntFrom(
      levelRoom, ['dailyExperienceMax', 'daily_experience_max'], 14000000,
    ).clamp(1, 14000000).toInt();
    final breakdown = levelRoom['dailyExperienceBreakdown'] is Map
        ? Map<String, dynamic>.from(levelRoom['dailyExperienceBreakdown'] as Map)
        : <String, dynamic>{};
    final dailyMicExp = _roomInfoIntFrom(
      levelRoom, ['dailyMicExperienceExp', 'daily_mic_experience_exp'],
      _roomInfoIntFrom(breakdown, ['microphone'], 0),
    ).clamp(0, 1000000).toInt();
    final dailyGiftExp = _roomInfoIntFrom(
      levelRoom, ['dailyGiftExperienceExp', 'daily_gift_experience_exp'],
      _roomInfoIntFrom(breakdown, ['gifts'], 0),
    ).clamp(0, 13000000).toInt();
    // The daily total is explicitly the sum of the two active earning tasks.
    final dailyExp = (dailyMicExp + dailyGiftExp).clamp(0, dailyMax).toInt();
    final serverDailyExp = _roomInfoIntFrom(
      levelRoom, ['dailyExperienceExp', 'daily_experience_exp'],
      _roomInfoIntFrom(breakdown, ['total'], dailyExp),
    ).clamp(0, dailyMax).toInt();
    final resetSeconds = _roomInfoIntFrom(
      levelRoom, ['dailyResetInSeconds', 'daily_reset_in_seconds'], 0,
    ).clamp(0, 86400).toInt();
    final image = (levelRoom['imageUrl'] ?? levelRoom['image_url'] ?? '').toString();
    await showRoomLevelSheet(
      context,
      RoomLevelData(
        level: level,
        roomName: _name,
        roomId: _id,
        roomAvatar: image.startsWith('http') ? NetworkImage(image) : null,
        exp: exp,
        nextLevelExp: nextExp,
        dailyExpCurrent: serverDailyExp.toString(),
        dailyExpMax: '14m',
        dailyRatio: serverDailyExp / dailyMax,
        dailyResetIn: resetSeconds > 0 ? Duration(seconds: resetSeconds) : null,
        tasks: [
          ExpTask(
            title: 'اخذ المقعد',
            desc: '+600 نقاط خبرة الغرفة/5 دقائق المستخدمين الجدد: +1200 نقاط خبرة الغرفة/5 دقائق',
            current: dailyMicExp.toString(),
            max: '1m',
            icon: Icons.mic,
            ratio: dailyMicExp / 1000000,
          ),
          ExpTask(
            title: 'ارسل الهدايا في الغرفة',
            desc: '+1 نقاط خبرة الغرفة / 1 عملة ذهبية (خلال المبارزة: +2 نقاط خبرة الغرفة / 1 عملة ذهبية)',
            current: dailyGiftExp.toString(),
            max: '13m',
            icon: Icons.card_giftcard,
            ratio: dailyGiftExp / 13000000,
          ),
        ],
        perkGroups: kSamplePerks,
      ),
    );
  }

  RoomLevelData _roomLevelData() {
    // Room identity belongs in the level window; it must never show the owner profile.
    // Room experience remains independent from paid room upgrade tiers.
    final exp = _roomInfoInt(['experienceExp', 'experience_exp'], 0);
    final level = _roomInfoInt(['experienceLevel', 'experience_level'], 1)
        .clamp(1, 2147483647).toInt();
    final nextExp = _roomInfoInt(
      ['experienceNextLevelExp', 'experience_next_level_exp'],
      roomLevelRequiredExpForLevel(level + 1),
    ).clamp(1, 2147483647).toInt();
    final dailyExpMaxValue = _roomInfoInt(
      ['dailyExperienceMax', 'daily_experience_max'], 14000000,
    ).clamp(1, 14000000).toInt();
    final dailyExp = _roomInfoInt(
      ['dailyExperienceExp', 'daily_experience_exp'], 0,
    ).clamp(0, dailyExpMaxValue).toInt();
    final dailyMicExp = _roomInfoInt(
      ['dailyMicExperienceExp', 'daily_mic_experience_exp'], 0,
    ).clamp(0, 1000000).toInt();
    final dailyGiftExp = _roomInfoInt(
      ['dailyGiftExperienceExp', 'daily_gift_experience_exp'], 0,
    ).clamp(0, 13000000).toInt();
    final dailyResetSeconds = _roomInfoInt(
      ['dailyResetInSeconds', 'daily_reset_in_seconds'], 0,
    ).clamp(0, 86400).toInt();
    // Mic awards are the room's current daily experience contribution.
    // The 1m mic target is part of (not additional to) the room-wide 14m cap.
    final roomImage = _roomInfoString(
      ['imageUrl', 'image_url', 'coverUrl', 'cover_url'],
    );
    return RoomLevelData(
      level: level,
      roomName: _name,
      roomId: _id,
      roomAvatar: roomImage.startsWith('http') ? NetworkImage(roomImage) : null,
      exp: exp,
      nextLevelExp: nextExp,
      dailyExpCurrent: dailyExp.toString(),
      dailyExpMax: '14m',
      dailyRatio: dailyExp / dailyExpMaxValue,
      dailyResetIn: dailyResetSeconds > 0
          ? Duration(seconds: dailyResetSeconds)
          : null,
      tasks: [
        ExpTask(
          title: 'اخذ المقعد',
          desc: '+600 نقاط خبرة الغرفة/5 دقائق المستخدمين الجدد: +1200 نقاط خبرة الغرفة/5 دقائق)',
          current: dailyMicExp.toString(),
          max: '1m',
          icon: Icons.mic,
          ratio: dailyMicExp / 1000000,
        ),
        ExpTask(
          title: 'ارسل الهدايا في الغرفة',
          desc: '+1 نقاط خبرة الغرفة / 1 عملة ذهبية (خلال المبارزة: +2 نقاط خبرة الغرفة / 1 عملة ذهبية)',
          current: dailyGiftExp.toString(),
          max: '13m',
          icon: Icons.card_giftcard,
          ratio: dailyGiftExp / 13000000,
        ),
      ],
      perkGroups: kSamplePerks,
    );
  }

  Future<void> _openRoomInfo(BuildContext context) async {
    final roomKey = _id.trim().isEmpty ? 'room:${identityHashCode(room)}' : _id.trim();
    if (!_openingRoomInfo.add(roomKey)) return;
    try {
      final image = _roomInfoString(['imageUrl', 'image_url', 'coverUrl', 'cover_url']);
      final ownerData = room['owner'] is Map
          ? Map<String, dynamic>.from(room['owner'] as Map)
          : room['roomOwner'] is Map
              ? Map<String, dynamic>.from(room['roomOwner'] as Map)
              : room['room_owner'] is Map
                  ? Map<String, dynamic>.from(room['room_owner'] as Map)
                  : <String, dynamic>{};
  
      // Room data supplies only account identifiers and room roles.
      // Names, avatars and public IDs always come from the app's user profile API.
      final resolvedOwnerUserId = (ownerData['id'] ??
              ownerData['userId'] ??
              ownerData['user_id'] ??
              ownerData['uid'] ??
              _roomInfoString(['ownerId', 'owner_id', 'ownerUserId', 'owner_user_id']))
          .toString()
          .trim();
  
      final members = <RoomMember>[];
      final memberIndexes = <String, int>{};

      String memberValue(Map<String, dynamic> data, List<String> keys) {
        for (final key in keys) {
          final value = data[key]?.toString().trim() ?? '';
          if (value.isNotEmpty && value != 'null') return value;
        }
        return '';
      }

      void addRoomMember(Map<String, dynamic> data, {String fallbackRole = 'عضو'}) {
        final profile = data['profile'] is Map
            ? Map<String, dynamic>.from(data['profile'] as Map)
            : data;
        final userId = memberValue(data, [
          'userId', 'user_id', 'uid', 'accountId', 'account_id', 'id'
        ]).isNotEmpty
            ? memberValue(data, [
                'userId', 'user_id', 'uid', 'accountId', 'account_id', 'id'
              ])
            : memberValue(profile, ['userId', 'user_id', 'uid', 'id']);
        final avatarUrl = memberValue(profile, [
          'avatarUrl', 'avatar_url', 'avatar', 'photoUrl', 'photo_url',
          'profileImage', 'profile_image', 'imageUrl', 'image_url', 'picture'
        ]);
        final name = memberValue(profile, [
          'name', 'displayName', 'display_name', 'username'
        ]);
        final publicId = memberValue(profile, [
          'userCode', 'user_code', 'happy_id', 'gabo_id', 'publicId', 'public_id'
        ]);
        if (userId.isEmpty && avatarUrl.isEmpty && name.isEmpty) return;

        final role = memberValue(data, [
          'role', 'roleName', 'role_name'
        ]).isEmpty ? fallbackRole : memberValue(data, [
          'role', 'roleName', 'role_name'
        ]);
        final isOwner = data['isOwner'] == true ||
            data['isRoomOwner'] == true ||
            data['is_room_owner'] == true ||
            data['is_owner'] == true ||
            role.toLowerCase() == 'owner' ||
            role == 'المالك';
        final isModerator = data['isRoomModerator'] == true ||
            data['is_room_moderator'] == true ||
            role.toLowerCase() == 'moderator' ||
            role == 'مشرف' ||
            role == 'مشرفة';
        final resolvedRole = isOwner ? 'المالك' : isModerator ? 'مشرف' : role;
        final member = RoomMember(
          avatarUrl: avatarUrl,
          role: resolvedRole,
          isOwner: isOwner,
          name: name,
          id: publicId,
          userId: userId,
        );
        final key = userId.isNotEmpty
            ? userId
            : (publicId.isNotEmpty ? 'code:$publicId' : 'name:$name');
        final existingIndex = memberIndexes[key];
        if (existingIndex != null) {
          final existing = members[existingIndex];
          members[existingIndex] = RoomMember(
            avatarUrl: existing.avatarUrl.isNotEmpty ? existing.avatarUrl : member.avatarUrl,
            role: member.isOwner ? member.role :
                (member.role == 'مشرف' ? member.role : existing.role),
            isOwner: existing.isOwner || member.isOwner,
            name: existing.name.isNotEmpty ? existing.name : member.name,
            id: existing.id.isNotEmpty ? existing.id : member.id,
            userId: existing.userId.isNotEmpty ? existing.userId : member.userId,
          );
        } else {
          memberIndexes[key] = members.length;
          members.add(member);
        }
      }

      final rawMembers = room['members'] ?? room['roomMembers'] ?? room['room_members'];
      if (rawMembers is List) {
        for (final item in rawMembers) {
          if (item is Map) {
            addRoomMember(Map<String, dynamic>.from(item));
          }
        }
      }

      // Include currently seated speakers and listeners: their live room
      // payloads carry avatar URLs even when room.members has only IDs.
      for (final seat in seats) {
        final hasUser = seat['userId'] != null ||
            seat['user_id'] != null ||
            seat['uid'] != null;
        if (hasUser) addRoomMember(seat, fallbackRole: 'متحدث');
      }
      for (final user in audienceUsers) {
        addRoomMember(user, fallbackRole: 'مستمع');
      }

      // The room payload often contains only the owner's ID, not their
      // profile fields. Fetch the authenticated public profile so the room
      // information sheet receives the saved country instead of an empty flag.
      final fetchedOwnerProfile = await _loadAccountProfile(resolvedOwnerUserId);
      final ownerProfile = <String, dynamic>{
        ...ownerData,
        if (ownerData['profile'] is Map)
          ...Map<String, dynamic>.from(ownerData['profile'] as Map),
        if (fetchedOwnerProfile != null) ...fetchedOwnerProfile,
      };
      final ownerIndex = members.indexWhere((member) =>
          member.isOwner ||
          (resolvedOwnerUserId.isNotEmpty &&
              member.userId == resolvedOwnerUserId));
      final ownerMember = RoomMember(
        avatarUrl: _profileValue(ownerProfile, [
          'avatarUrl', 'avatar_url', 'avatar', 'photoUrl', 'photo_url',
          'profileImage', 'profile_image', 'imageUrl', 'image_url'
        ]).isNotEmpty
            ? _profileValue(ownerProfile, [
                'avatarUrl', 'avatar_url', 'avatar', 'photoUrl', 'photo_url',
                'profileImage', 'profile_image', 'imageUrl', 'image_url'
              ])
            : ownerAvatarUrl,
        role: 'المالك',
        isOwner: true,
        name: _profileValue(ownerProfile, [
          'name', 'displayName', 'display_name'
        ]).isNotEmpty
            ? _profileValue(ownerProfile, ['name', 'displayName', 'display_name'])
            : ownerName,
        id: _profileValue(ownerProfile, [
          'userCode', 'user_code', 'happy_id', 'gabo_id'
        ]),
        userId: resolvedOwnerUserId,
      );
      if (ownerIndex >= 0) {
        final existing = members[ownerIndex];
        members[ownerIndex] = RoomMember(
          avatarUrl: ownerMember.avatarUrl.isNotEmpty
              ? ownerMember.avatarUrl
              : existing.avatarUrl,
          role: 'المالك',
          isOwner: true,
          name: ownerMember.name.isNotEmpty ? ownerMember.name : existing.name,
          id: ownerMember.id.isNotEmpty ? ownerMember.id : existing.id,
          userId: ownerMember.userId.isNotEmpty ? ownerMember.userId : existing.userId,
        );
      } else {
        members.insert(0, ownerMember);
      }

      final ownerCountryName = _profileValue(
        ownerProfile,
        ['countryName', 'country_name', 'country', 'countryDisplayName', 'country_display_name', 'countryCode', 'country_code', 'countryIso', 'country_iso', 'flag'],
      ).isNotEmpty
          ? _profileValue(ownerProfile, [
              'countryName', 'country_name', 'country', 'countryDisplayName', 'country_display_name'
            ])
          : _roomInfoString(['ownerCountryName', 'owner_country_name', 'ownerCountryCode', 'owner_country_code']);
      if (!context.mounted) return;
  
      final info = RoomInfo(
        name: _name,
        flag: ownerCountryName,
        id: _id,
        imageUrl: image,
        imageBadge: _roomInfoString(['imageBadge', 'image_badge'], 'غرفة مميزة'),
        likes: _roomInfoInt(['likes', 'likeCount', 'like_count', 'trophies', 'trophyCount']),
        tribeName: _roomInfoString(['tribeName', 'tribe_name'], 'بدون قبيلة'),
        tribeOwner: _roomInfoString(['tribeOwner', 'tribe_owner']),
        tribeLogoUrl: _roomInfoString(['tribe_logo', 'tribeLogo', 'tribeLogoUrl', 'tribe_logo_url']),
        level: _roomInfoInt(['level', 'roomLevel', 'room_level'], 1),
        experienceLevel: _roomInfoInt(['experienceLevel', 'experience_level'], 1),
        palaceStatus: _roomInfoString(['palaceStatus', 'palace_status'], 'غير مفعّل'),
        membersCount: _roomInfoInt(['membersCount', 'members_count', 'memberCount'], 0) > members.length
            ? _roomInfoInt(['membersCount', 'members_count', 'memberCount'], 0)
            : members.length,
        membersMax: _roomInfoInt(['membersMax', 'members_max', 'maxMembers'], 100),
        members: members,
        announcement: _roomInfoString(['announcement', 'description']),
        groupName: _roomInfoString(['groupName', 'group_name'], 'مجموعة الغرفة'),
        groupCount: _roomInfoInt(['groupCount', 'group_count']),
        groupDesc: _roomInfoString(['groupDesc', 'group_desc', 'groupDescription']),
        ownerAvatarUrl: ownerMember.avatarUrl,
        isRoomOwner: isCurrentUserRoomOwner || room['isOwner'] == true ||
            room['is_owner'] == true ||
            room['isRoomOwner'] == true ||
            room['is_room_owner'] == true ||
            room['currentUserRole']?.toString().toLowerCase() == 'owner' ||
            room['current_user_role']?.toString().toLowerCase() == 'owner' ||
            room['myRole']?.toString().toLowerCase() == 'owner' ||
            room['my_role']?.toString().toLowerCase() == 'owner' ||
            ((room['ownerId'] ?? room['owner_id']) != null &&
             (room['currentUserId'] ?? room['current_user_id']) != null &&
             (room['ownerId'] ?? room['owner_id']).toString() ==
                 (room['currentUserId'] ?? room['current_user_id']).toString()),
      );
  
      await showRoomInfoSheet(
        context,
        info,
        onLevelTap: () => _openRoomLevelSheet(context, room),
        onUpgrade: () {
          Navigator.of(context).pop();
          final roomId = (room['id'] ?? '').toString().trim();
          if (roomId.isEmpty) {
            showCenteredNotification(context, 
              const SnackBar(content: Text('تعذر تحديد رقم الغرفة للترقية')),
            );
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RoomUpgradePage(
                ownerName: ownerMember.name,
                ownerId: ownerMember.id,
                ownerAvatar: ownerMember.avatarUrl.startsWith('http')
                    ? NetworkImage(ownerMember.avatarUrl)
                    : null,
                currentLevel: (info.level - 1).clamp(0, 4).toInt(),
                onUpgrade: (levelIndex) async {
                  final upgrade = onUpgradeRoom;
                  if (upgrade == null) {
                    throw Exception('خدمة ترقية الغرفة غير متاحة');
                  }
                  try {
                    await upgrade(roomId, levelIndex + 1);
                    room['level'] = levelIndex + 1;
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    showCenteredNotification(context, 
                      SnackBar(content: Text('تمت ترقية الغرفة إلى ${kLevels[levelIndex].name}')),
                    );
                  } catch (error) {
                    if (context.mounted) {
                      final message = error.toString().replaceFirst('Exception: ', '');
                      showCenteredNotification(context, 
                        SnackBar(content: Text(message)),
                      );
                    }
                  }
                },
              ),
            ),
          );
        },
        onFollow: () {
          Navigator.of(context).pop();
          showCenteredNotification(context, const SnackBar(content: Text('ميزة المتابعة قريبًا')));
        },
        onJoin: () {
          Navigator.of(context).pop();
          showCenteredNotification(context, const SnackBar(content: Text('ميزة الانضمام للمجموعة قريبًا')));
        },
        onSettings: () {
          Navigator.of(context).pop();
          final roomId = (room['id'] ?? room['roomId'] ?? room['room_id'] ?? '').toString().trim();
          if (roomId.isEmpty || accessToken.trim().isEmpty || !info.isRoomOwner) {
            showCenteredNotification(context, 
              const SnackBar(content: Text('تعذر فتح إعدادات الغرفة: تحقق من صلاحية المالك واتصال الحساب')),
            );
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RoomSettingsPage(
                c: RoomSettingsController(
                  api: MyWorkersApi(roomId: roomId, accessToken: accessToken),
                ),
                onCoverChanged: onRoomCoverChanged,
              ),
            ),
          ).then((_) => onRoomSettingsChanged?.call());
        },
        onInvite: () {
          Navigator.of(context).pop();
          showCenteredNotification(context, const SnackBar(content: Text('دعوة الأعضاء قريبًا')));
        },
        accessToken: accessToken,
      );
    } finally {
      _openingRoomInfo.remove(roomKey);
    }
  }

  Widget _header(BuildContext context) {
    // The room tile is the room cover, not the owner's profile photo.
    // New rooms receive a one-time owner-avatar default from the API; after
    // that, changing the cover never changes the owner's personal avatar.
    final roomCover = _roomInfoString(['imageUrl', 'image_url', 'coverUrl', 'cover_url']);
    final avatar = roomCover.startsWith('https://')
        ? roomCover
        : (ownerAvatarUrl.trim().isNotEmpty
            ? ownerAvatarUrl.trim()
            : (room['ownerAvatar'] ?? room['ownerAvatarUrl'] ?? '').toString().trim());
    final trophies = (room['trophies'] ?? room['trophyCount'] ?? 0).toString();
    return Transform.translate(
      offset: Theme.of(context).platform == TargetPlatform.android
          ? const Offset(0, -17)
          : Offset.zero,
      child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: 160.0,
              maxWidth: (MediaQuery.sizeOf(context).width * .60).clamp(160.0, 235.0),
            ),
            child: IntrinsicWidth(
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openRoomInfo(context),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 38,
                        height: 37,
                        child: avatar.startsWith('http')
                            ? HappyNetworkImage(avatar, fit: BoxFit.cover,
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
                  ),
                  const SizedBox(width: 3),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Transform.translate(
                                    offset: const Offset(-2, 1),
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _openRoomInfo(context),
                                      child: Text(
                                        _name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Transform.translate(
                                    offset: const Offset(-1, -2),
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _openRoomInfo(context),
                                      child: Transform.translate(
                                        offset: const Offset(1, 0),
                                        child: Text(
                                          'ID:$_id',
                                          style: const TextStyle(color: Colors.white60, fontSize: 11),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(width: 4),
                            Transform.translate(
                              offset: const Offset(-8, 0),
                              child: Container(
                                width: 44,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: const Color(0xD93D2E1F),
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: const Color(0xCCD4B779),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 14,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(7),
                                        gradient: const LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Color(0xFFFFF8E7),
                                            Color(0xFFE9C97B),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          SizedBox(
                                            width: 2.7,
                                            height: 10,
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: Color(0xFFC19A3E),
                                                borderRadius: BorderRadius.all(Radius.circular(2)),
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 10,
                                            height: 3,
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: Color(0xFFC19A3E),
                                                borderRadius: BorderRadius.all(Radius.circular(2)),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
                ],
              ),
            ),
          ),
          ),
          const Spacer(),
          const SizedBox(width: 10),
          InkWell(
            onTap: () {
              final roomId = _roomInfoString(['id', 'roomId', 'room_id']).trim();
              if (roomId.isEmpty || accessToken.trim().isEmpty) {
                showCenteredNotification(context, 
                  const SnackBar(content: Text('تعذر فتح تصنيف المساهمين: بيانات الغرفة أو الدخول غير مكتملة')),
                );
                return;
              }
              openContribSheet(context, roomId, accessToken: accessToken);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 38,
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.3),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text('🏆', style: TextStyle(fontSize: 16)),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      trophies,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
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
                          showCenteredNotification(context, 
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

  Widget _subHeader(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(12, 9, 12, 0),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: RoomLevelChip(
        data: _roomLevelData(),
        onTap: () => _openRoomLevelSheet(context, room),
      ),
    ),
  );

  Widget _seats(BuildContext context) {
    final configuredLayoutId =
        _roomInfoString(['micLayoutId', 'mic_layout_id']).trim().toLowerCase();
    final configuredMicCount =
        int.tryParse(_roomInfoString(['micCount', 'mic_count'], '0')) ?? 0;

    // Each room layout is selected by its own layout ID. The seat count is
    // only a compatibility fallback for older room snapshots that lack an ID;
    // it must never override an explicitly selected layout.
    final resolvedLayoutId = configuredLayoutId.isNotEmpty
        ? configuredLayoutId
        : configuredMicCount > 0
            ? 'm$configuredMicCount'
            : 'm8';
    // PK always uses the 12-seat battle arrangement; higher seat numbers
    // remain outside the battle in a separate naturally styled row.
    final roomLayout = micLayoutById(resolvedLayoutId);
    final layout = micLayoutById(pkVisualMode ? 'm12' : resolvedLayoutId);
    final seatStore = context.watch<SeatStateStore>();
    final roomSeatNumbers = <int>{
      for (final row in roomLayout.rows)
        for (final slot in row.whereType<MicSeat>())
          roomLayout.seatNumber(slot),
    }.toList()..sort();
    int? firstJoinSeat;
    if (seatStore.mySeat == null) {
      for (final number in roomSeatNumbers) {
        final state = seatStore.seats[number] ?? SeatState.empty(number);
        final pending = state.isPending ||
            seatStore.isPending(number) ||
            pendingSeatNumbers.contains(number);
        if (state.occupied || pending) continue;
        if (state.isLocked && !canModerateUsers) continue;
        firstJoinSeat = number;
        break;
      }
    }
    final overflowSlots = <MicSeat>[];
    if (pkVisualMode) {
      for (final row in roomLayout.rows) {
        for (final slot in row.whereType<MicSeat>()) {
          if (roomLayout.seatNumber(slot) > 12) overflowSlots.add(slot);
        }
      }
      overflowSlots.sort((a, b) => roomLayout.seatNumber(a).compareTo(roomLayout.seatNumber(b)));
    }
    final columns = pkVisualMode ? 4 : layout.maxCols;
    // Preserve each row's own alignment by building a padded row-major list.
    final arrangedCells = <MicSeat?>[];
    for (final row in layout.rows) {
      arrangedCells.addAll(row);
      arrangedCells.addAll(List<MicSeat?>.filled(columns - row.length, null));
    }
    if (pkVisualMode && layout.id == 'm12') {
      final slotsByNumber = <int, MicSeat>{};
      for (final slot in arrangedCells) {
        if (slot != null) slotsByNumber[layout.seatNumber(slot)] = slot;
      }
      // LTR grid: the first two columns reproduce leftSeats,
      // and the last two columns reproduce rightSeats from the supplied design.
      arrangedCells
        ..clear()
        ..addAll(
          [4, 3, 2, 1, 8, 7, 6, 5, 12, 11, 10, 9]
              .map((number) => slotsByNumber[number]!)
              .toList(),
        );
    } else if (pkTeamMode && layout.id == 'm8') {
      final slotsByNumber = <int, MicSeat>{};
      for (final slot in arrangedCells) {
        if (slot != null) slotsByNumber[layout.seatNumber(slot)] = slot;
      }
      arrangedCells
        ..clear()
        ..addAll([4, 3, 2, 1, 8, 7, 6, 5].map((number) => slotsByNumber[number]!).toList());
    }
    // Every microphone layout uses an exact 2px gap in both directions.
    // Give every layout an explicitly measured viewport so row offsets remain
    // visible and no bottom row is clipped by shrink-wrap measurement.
    const micRowGap = 2.0;
    const micColumnGap = 2.0;
    final gridHeight = (layout.rows.length * 88.0) +
        ((layout.rows.length - 1) * micRowGap);
    final pkTwelveSeatLayout = pkVisualMode;
    final micBorderColor = _micColorFromHex(normalMicBorderColor, Colors.white);
    final micFillColor = _micColorFromHex(normalMicFillColor, Colors.white);
    final pkBorderColor = _micColorFromHex(pkMicBorderColor, Colors.white);
    final pkFillColor = _micColorFromHex(pkMicFillColor, Colors.white);
    final pkBlueBorderColor = _micColorFromHex(pkBlueMicBorderColor, const Color(0xFF258BFF));
    final pkRedBorderColor = _micColorFromHex(pkRedMicBorderColor, const Color(0xFFFF4B5C));
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pkTwelveSeatLayout ? 8 : 12),
      child: SizedBox(
        height: gridHeight + (pkTwelveSeatLayout && overflowSlots.isNotEmpty ? 92 : 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: gridHeight,
              child: Stack(
                children: [
            if (pkTwelveSeatLayout)
              Positioned.fill(
                child: Row(
                  textDirection: TextDirection.ltr,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(44),
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                const Color(0xFF3B2FD6),
                                const Color(0xFF2A1EB5),
                                const Color(0xFF3A2BD6),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(width: 1, color: Colors.white.withOpacity(.15)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomRight: Radius.circular(44),
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                const Color(0xFFB01E5A),
                                const Color(0xFFC21E5E),
                                const Color(0xFF9E174E),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Directionality(
              textDirection: pkTwelveSeatLayout ? TextDirection.ltr : Directionality.of(context),
              child: GridView.builder(
                shrinkWrap: false,
                physics: const NeverScrollableScrollPhysics(),
                clipBehavior: Clip.none,
                padding: EdgeInsets.symmetric(horizontal: pkTwelveSeatLayout ? 4 : 12),
                itemCount: arrangedCells.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: micRowGap,
                  crossAxisSpacing: micColumnGap,
                  mainAxisExtent: 88,
                ),
                itemBuilder: (context, index) {
        final slot = arrangedCells[index];
        if (slot == null) return const SizedBox.shrink();
        final number = layout.seatNumber(slot);
        final rowIndex = index ~/ columns;
        // Raise microphone groups by their seat numbers in every layout:
        // seats 7–12 by 3px, 13–18 by 6px, and 19–24 by 12px.
        final baseVerticalOffset = number >= 19
            ? -18.0
            : number >= 13
                ? -12.0
                : number >= 7
                    ? -3.0
                    : 0.0;
        // The 15-seat layout must keep every seat level within its row.
        final verticalOffset = pkTwelveSeatLayout
            ? 0.0
            : layout.id == 'm8'
            ? 0.0
            : layout.id == 'm10'
                ? (number >= 5 && number <= 8
                    ? -8.0
                    : number <= 4
                        ? -5.0
                        : baseVerticalOffset)
                : layout.id == 'm12'
                    ? (number >= 9 && number <= 12
                        ? -15.0
                        : number >= 5 && number <= 8
                            ? -6.0
                            : baseVerticalOffset)
                    : layout.id == 'm14'
                        ? (number >= 13 && number <= 14
                            ? baseVerticalOffset - 10.0
                            : number >= 9 && number <= 12
                                ? -31.0
                                : number >= 5 && number <= 8
                                    ? -22.0
                                    : baseVerticalOffset - 16.0)
                : layout.id == 'm15'
                ? (number >= 11 && number <= 15
                    ? -13.0
                    : number >= 6 && number <= 10
                        ? -7.0
                        : 0.0)
                : baseVerticalOffset +
                    (layout.id == 'm20' && number >= 1 && number <= 18
                        ? -7.0
                        : 0.0);
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Selector<SeatStateStore, SeatState>(
          selector: (context, store) => store.seats[number] ?? SeatState.empty(number),
          builder: (context, seatState, child) {
        final seat = seatState.occupied ? seatState.toMap() : null;
        final occupied = seat != null;
        final mine = seat?['isMe'] == true;
        final name = (seat?['name'] ?? '').toString();
        final avatar = (seat?['avatar'] ?? seat?['avatarUrl'] ?? seat?['photoUrl'] ?? '').toString();
        final visibleAvatar = occupied ? avatar : (number == firstJoinSeat ? seatStore.currentAvatarUrl : '');
        final muted = seatState.isMuted || seat?['isMuted'] == true;
        final locked = seatState.isLocked || seat?['isLocked'] == true || seat?['locked'] == true;
        final speakerUid = seat?['uid'] is num
            ? (seat!['uid'] as num).toInt()
            : int.tryParse((seat?['userCode'] ?? '').toString());
        final voiceLevel = speakerUid == null ? 0.0 : (speakerLevels[speakerUid] ?? 0.0);
        final isSpeaking = occupied && !muted && voiceLevel >=
            (Theme.of(context).platform == TargetPlatform.android ? 0.02 : 0.6);
        final seatDiameter = slot.big ? 50.0 : 44.0;
        final seatBoxWidth = slot.big ? 66.0 : 58.0;
        // The row offset is applied by the parent Transform above;
        // the seat itself keeps its original 88px hit target and visuals.
        return Transform.translate(
          offset: Offset(0, verticalOffset),
          child: Align(
            alignment: Alignment.topCenter,
          child: GestureDetector(
                // Do not let the full seat rectangle block taps on listener
                // avatars painted underneath the transparent/empty seat area.
                behavior: HitTestBehavior.deferToChild,
                onTap: null,
                child: SizedBox(
                  width: seatBoxWidth,
                  height: 88,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: canModerateUsers
                        ? () => _showEmptySeatActions(context, number)
                        : occupied
                            ? () => _showUserProfile(context, seat!)
                            : (!isChangingSeat && !seatState.isPending && !locked
                                ? () => onTapSeat(number)
                                : null),
                    child: _GoldenVoiceWave(
                    isSpeaking: isSpeaking,
                      isLocked: locked,
                    isOccupied: occupied,
                    micStyleUrl: micStyleUrl,
                    micChairStyleUrl: micChairStyleUrl,
                    micLockStyleUrl: micLockStyleUrl,
                       micCircleScale: micCircleScale,
                      micChairScale: micChairScale,
                      micLockScale: micLockScale,
                      micCircleClarity: micCircleClarity,
                      micChairClarity: micChairClarity,
                      micLockClarity: micLockClarity,
                      micCircleOpacity: micCircleOpacity,
                      micChairOpacity: micChairOpacity,
                      micLockOpacity: micLockOpacity,
                    avatarSize: seatDiameter,
                    rippleStartSize: seatDiameter + 5,
                    rippleEndSize: seatDiameter + 18,
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
                      width: seatDiameter,
                      height: seatDiameter,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: micStyleUrl.startsWith('https://')
                            ? Colors.transparent
                            : (pkTwelveSeatLayout ? pkFillColor : micFillColor).withOpacity(
                                pkTwelveSeatLayout ? pkMicFillOpacity : normalMicFillOpacity,
                              ),
                        border: micStyleUrl.startsWith('https://')
                            ? Border.all(color: Colors.transparent, width: 0)
                            : Border.all(
                                color: pkTwelveSeatLayout
                                    ? pkBorderColor
                                    : pkTeamMode && layout.id == 'm8'
                                        ? (number <= 4 ? pkBlueBorderColor : pkRedBorderColor)
                                        : micBorderColor,
                                width: pkTwelveSeatLayout
                                    ? pkMicBorderWidth
                                    : pkTeamMode && layout.id == 'm8'
                                        ? pkMicBorderWidth
                                        : normalMicBorderWidth,
                              ),
                        // The uploaded SVGA replaces the old seat shell entirely.
                        boxShadow: micStyleUrl.startsWith('https://')
                            ? const []
                            : const [
                                BoxShadow(
                                  color: Color(0x99000000),
                                  blurRadius: 9,
                                  spreadRadius: 1,
                                  offset: Offset(0, 2),
                                ),
                              ],
                      ),
                      child: ClipOval(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (visibleAvatar.startsWith('http'))
                              Opacity(
                                // Keep the pending joiner's avatar faded until the mic is occupied.
                                opacity: occupied ? 1 : 0.35,
                                child: HappyNetworkImage(visibleAvatar, fit: BoxFit.cover),
                              ),
                            if (!visibleAvatar.startsWith('http') && !micStyleUrl.startsWith('https://'))
                              occupied
                                  ? Icon(Icons.mic_rounded, color: Colors.white.withOpacity(.92), size: slot.big ? 22 : 19)
                                  : locked
                                      ? Icon(Icons.lock_outline, color: Colors.white.withOpacity(.92), size: slot.big ? 22 : 19)
                                      : Center(
                                          child: CustomPaint(
                                            size: Size(slot.big ? 24 : 20, slot.big ? 24 : 20),
                                            painter: const ChairCustomPainter(
                                              color: Color(0xFF9A98A6),
                                              strokeWidth: 2.0,
                                            ),
                                          ),
                                        ),
                            if (!micStyleUrl.startsWith('https://') && !occupied && number == firstJoinSeat && visibleAvatar.startsWith('http'))
                              const CustomPaint(painter: _DashedCircleBorderPainter()),
                          ],
                        ),
                      ),
                      ),
                    ),
                    ),
                  ),

                  if (occupied && isRoomGiftCounterActive)
                    Positioned(
                      bottom: -8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 42, maxWidth: 58),
                          height: 16,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00BFA5), Color(0xFF00D7B0), Color(0xFF009F83)],
                            ),
                            border: Border.all(color: const Color(0xFF9CFFE8), width: .6),
                            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 3, offset: Offset(0, 1))],
                          ),
                          child: Text(
                            (roomGiftScores[(seat?['userId'] ?? '').toString()] ?? 0).toString(),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, height: 1.1),
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
              SizedBox(height: isRoomGiftCounterActive ? 12 : 4),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(color: Color(0xCC000000), blurRadius: 4, offset: Offset(0, 1)),
                      ],
                    ),
                  ),
                )
              else if (number == firstJoinSeat)
                _joinMicButton(
                  number,
                  disabled: isChangingSeat || seatState.isPending,
                )
              else
                Transform.translate(
                  offset: const Offset(0, 2),
                  child: Text(
                    '$number',
                    style: TextStyle(
                      color: Colors.white.withOpacity(.7),
                      fontSize: pkTwelveSeatLayout ? 16 : 13,
                      shadows: const [
                        Shadow(color: Color(0xCC000000), blurRadius: 4, offset: Offset(0, 1)),
                      ],
                    ),
                  ),
                ),
                    ],
                    ),
                  ),
                ),
            ),
          );
          },
          ),
        );
      },
    ),
    ),
                ],
              ),
            ),
            if (pkTwelveSeatLayout && overflowSlots.isNotEmpty)
              SizedBox(
                height: 88,
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: overflowSlots.map((slot) {
                        final number = roomLayout.seatNumber(slot);
                        return Padding(
                          padding: const EdgeInsetsDirectional.only(end: 5),
                          child: _pkOverflowSeat(
                            context,
                            slot,
                            number,
                            joinSeatNumber: firstJoinSeat,
                            currentUserAvatarUrl: seatStore.currentAvatarUrl,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _joinMicButton(int number, {required bool disabled}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : () => (onJoinSeat ?? onTapSeat)(number),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: disabled ? Colors.white.withOpacity(.55) : Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'انضمام',
            style: TextStyle(
              color: Colors.black,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _pkOverflowSeat(
    BuildContext context,
    MicSeat slot,
    int number, {
    required int? joinSeatNumber,
    required String currentUserAvatarUrl,
  }) {
    return SizedBox(
      width: 54,
      height: 72,
      child: Selector<SeatStateStore, SeatState>(
        selector: (context, store) => store.seats[number] ?? SeatState.empty(number),
        builder: (context, seatState, child) {
          final seat = seatState.occupied ? seatState.toMap() : null;
          final occupied = seat != null;
          final mine = seat?['isMe'] == true;
          final name = (seat?['name'] ?? '').toString();
          final avatar = (seat?['avatar'] ?? seat?['avatarUrl'] ?? seat?['photoUrl'] ?? '').toString();
          final visibleAvatar = occupied ? avatar : (number == joinSeatNumber ? currentUserAvatarUrl : '');
          final muted = seatState.isMuted || seat?['isMuted'] == true;
          final locked = seatState.isLocked || seat?['isLocked'] == true || seat?['locked'] == true;
          final speakerUid = seat?['uid'] is num
              ? (seat!['uid'] as num).toInt()
              : int.tryParse((seat?['userCode'] ?? '').toString());
          final voiceLevel = speakerUid == null ? 0.0 : (speakerLevels[speakerUid] ?? 0.0);
          final isSpeaking = occupied && !muted && voiceLevel >=
              (Theme.of(context).platform == TargetPlatform.android ? 0.02 : 0.6);
          final diameter = slot.big ? 38.0 : 34.0;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                // Keep the complete visible mic hit area interactive. The
                // animated SVGA is decorative only and must never replace the
                // original seat tap target.
                behavior: HitTestBehavior.opaque,
                onTap: occupied
                    ? (canModerateUsers
                        ? () => _showEmptySeatActions(context, number)
                        : () => _showUserProfile(context, seat!))
                    : (!isChangingSeat && !seatState.isPending && !locked
                        ? () => onTapSeat(number)
                        : null),
                onLongPress: canModerateUsers && !occupied
                    ? () => _showEmptySeatActions(context, number)
                    : null,
                child: SizedBox(
                  width: 54,
                  height: 46,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: 0,
                        left: (54 - diameter) / 2,
                        child: _GoldenVoiceWave(
                          isSpeaking: isSpeaking,
                          isLocked: locked,
                          isOccupied: occupied,
                          micStyleUrl: micStyleUrl,
                          micChairStyleUrl: micChairStyleUrl,
                          micLockStyleUrl: micLockStyleUrl,
                       micCircleScale: micCircleScale,
                      micChairScale: micChairScale,
                      micLockScale: micLockScale,
                      micCircleClarity: micCircleClarity,
                      micChairClarity: micChairClarity,
                      micLockClarity: micLockClarity,
                      micCircleOpacity: micCircleOpacity,
                      micChairOpacity: micChairOpacity,
                      micLockOpacity: micLockOpacity,
                          avatarSize: diameter,
                          rippleStartSize: diameter + 5,
                          rippleEndSize: diameter + 18,
                          avatar: Container(
                            width: diameter,
                            height: diameter,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: micStyleUrl.startsWith('https://')
                                  ? Colors.transparent
                                  : slot.big ? const Color(0x33E8C477) : Colors.white.withOpacity(.14),
                              border: micStyleUrl.startsWith('https://')
                                  ? Border.all(color: Colors.transparent, width: 0)
                                  : Border.all(
                                      color: mine
                                          ? Colors.transparent
                                          : slot.big
                                              ? const Color(0xFFFFD98A)
                                              : Colors.white.withOpacity(occupied ? .82 : .48),
                                      width: mine ? 0 : slot.big ? 2.2 : occupied ? 2 : 1,
                                    ),
                              boxShadow: micStyleUrl.startsWith('https://')
                                  ? const []
                                  : const [
                                      BoxShadow(color: Color(0x99000000), blurRadius: 9, spreadRadius: 1, offset: Offset(0, 2)),
                                    ],
                            ),
                            child: ClipOval(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (visibleAvatar.startsWith('http'))
                                    Opacity(
                                      opacity: occupied ? 1 : 0.35,
                                      child: HappyNetworkImage(visibleAvatar, fit: BoxFit.cover),
                                    )
                                  else if (!micStyleUrl.startsWith('https://'))
                                    occupied
                                        ? Icon(Icons.mic_rounded, color: Colors.white.withOpacity(.92), size: slot.big ? 18 : 16)
                                        : locked
                                            ? Icon(Icons.lock_outline, color: Colors.white.withOpacity(.92), size: slot.big ? 18 : 16)
                                            : Center(
                                                child: CustomPaint(
                                                  size: Size(slot.big ? 22 : 18, slot.big ? 22 : 18),
                                                  painter: const ChairCustomPainter(
                                                    color: Color(0xFF9A98A6),
                                                    strokeWidth: 1.8,
                                                  ),
                                                ),
                                              ),
                                  if (!micStyleUrl.startsWith('https://') && !occupied && number == joinSeatNumber && visibleAvatar.startsWith('http'))
                                    const CustomPaint(painter: _DashedCircleBorderPainter()),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
                    if (muted)
                      Positioned(
                        bottom: 0,
                        left: 2,
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: const Icon(Icons.mic_off_rounded, size: 11, color: Color(0xFFE91E63)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (!occupied && number == joinSeatNumber)
                _joinMicButton(
                  number,
                  disabled: isChangingSeat || seatState.isPending,
                ),
            ],
          );
        },
      ),
    );
  }

  void _showEmptySeatActions(BuildContext context, int seatNumber) {
    final seat = _seatAt(seatNumber) ?? <String, dynamic>{};
    final userId = (seat['userId'] ?? '').toString();
    final occupied = userId.isNotEmpty;
    final isLocked = seat['isLocked'] == true || seat['locked'] == true;
    final isMuted = seat['isMuted'] == true;

    Future<void> runAction(BuildContext sheetContext, String action) async {
      Navigator.of(sheetContext).pop();
      await onModerateSeat?.call(seatNumber, action);
    }

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
                    icon: isLocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                    label: isLocked ? 'فتح المايك' : 'إغلاق المايك',
                    onTap: () => runAction(sheetContext, 'toggle_seat_lock'),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _EmptySeatAction(
                    icon: isMuted ? Icons.mic_rounded : Icons.mic_off_rounded,
                    label: isMuted ? 'فتح الكتم' : 'كتم المايك',
                    onTap: () => runAction(sheetContext, 'toggle_seat_mute'),
                  ),
                ),
              ),
              if (!occupied) ...[
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
                      customIcon: const CustomPaint(
                        size: Size(26, 26),
                        painter: ChairCustomPainter(
                          color: Color(0xFF9A98A6),
                          strokeWidth: 2.2,
                        ),
                      ),
                      label: 'اطلع المايك',
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        onTapSeat(seatNumber);
                      },
                    ),
                  ),
                ),
              ],
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
      useRootNavigator: true,
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

  Widget _listeners(BuildContext context, {bool isPk = false}) => Container(
    height: 30,
    margin: EdgeInsets.symmetric(horizontal: isPk ? 4 : 12),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(.30),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withOpacity(.24), width: 1),
      boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2))],
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
                        child: Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => _showUserProfile(context, user),
                            child: HappyNetworkAvatar(
                              url: avatar,
                              size: 22,
                              backgroundColor: Colors.white24,
                              fallback: const Icon(Icons.person, color: Colors.white70, size: 14),
                            ),
                          ),
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
  );

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

  void _openGamesSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: DefaultTabController(
          length: 2,
          child: Container(
            height: MediaQuery.of(sheetContext).size.height * .72,
            decoration: const BoxDecoration(
              color: Color(0xFFF5EEDC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Color(0xFFB8AA8D),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'الألعاب',
                          style: TextStyle(
                            color: Color(0xFF211B16),
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close, color: Color(0xFF514735)),
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),
                const TabBar(
                  labelColor: Color(0xFF6B5120),
                  unselectedLabelColor: Color(0xFF817966),
                  indicatorColor: Color(0xFFD4AF37),
                  indicatorWeight: 3,
                  tabs: [
                    Tab(text: 'ألعاب طرف ثالث'),
                    Tab(text: 'ألعاب مخصصة'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _GamesTabPlaceholder(
                        message: 'ستظهر ألعاب الطرف الثالث هنا',
                      ),
                      _GamesTabPlaceholder(message: 'ستظهر الألعاب المخصصة هنا'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
            InkWell(
              onTap: () => _openGamesSheet(context),
              borderRadius: BorderRadius.circular(24),
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(Icons.sports_esports_outlined, color: Colors.white, size: 30),
              ),
            ),
            const SizedBox(width: 13),
            InkWell(
              onTap: onOpenGifts,
              borderRadius: BorderRadius.circular(24),
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(Icons.card_giftcard, color: Color(0xFFFFA726), size: 32),
              ),
            ),
            const SizedBox(width: 13),
            InkWell(
              onTap: onRoomTools,
              borderRadius: BorderRadius.circular(8),
              child: const CustomPaint(
                size: Size(26, 26),
                painter: _RoomGridIconPainter(),
              ),
            ),
          ],
        ),
      ),
    );
  }

}



class _RoomGridIconPainter extends CustomPainter {
  const _RoomGridIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const gap = 4.0;
    final cell = (size.width - gap) / 2;
    for (var row = 0; row < 2; row++) {
      for (var column = 0; column < 2; column++) {
        final rect = Rect.fromLTWH(
          column * (cell + gap),
          row * (cell + gap),
          cell,
          cell,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RoomGridIconPainter oldDelegate) => false;
}


class _CannonLaunchFireworksPainter extends CustomPainter {
  const _CannonLaunchFireworksPainter({
    required this.progress,
    required this.origin,
  });

  final double progress;
  final Offset origin;

  static const List<Color> _colors = <Color>[
    Color(0xFFFFD54F), Color(0xFFFF4F91), Color(0xFF56D9FF),
    Color(0xFFB58CFF), Color(0xFF65F0B2), Color(0xFFFF8A45),
  ];

  @override
  void paint(ui.Canvas canvas, Size size) {
    // Long white/blue beam and twin engine flames trail behind the ascending jet.
    final beamEnd = Offset(origin.dx, size.height + 30);
    final beamStart = Offset(origin.dx, origin.dy + size.width * .16);
    canvas.drawLine(
      beamStart,
      beamEnd,
      ui.Paint()
        ..shader = ui.Gradient.linear(
          beamStart,
          beamEnd,
          [
            const Color(0xFFF7FCFF).withOpacity(.92),
            const Color(0xFF62C9FF).withOpacity(.62),
            const Color(0xFF1D66FF).withOpacity(.02),
          ],
          const [0.0, .28, 1.0],
        )
        ..strokeWidth = size.width * .16
        ..strokeCap = ui.StrokeCap.round
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 24),
    );
    canvas.drawLine(
      beamStart,
      beamEnd,
      ui.Paint()
        ..color = Colors.white.withOpacity(.78)
        ..strokeWidth = size.width * .025
        ..strokeCap = ui.StrokeCap.round
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8),
    );

    // Two bright orange-white exhaust flames directly behind the twin engines.
    for (final side in [-1.0, 1.0]) {
      final flameStart = Offset(
        origin.dx + side * size.width * .075,
        origin.dy + size.width * .12,
      );
      final flameEnd = Offset(
        flameStart.dx + side * size.width * .018,
        flameStart.dy + size.height * (.12 + .05 * math.sin(progress * math.pi * 8)),
      );
      canvas.drawLine(
        flameStart,
        flameEnd,
        ui.Paint()
          ..color = const Color(0xFFFF7A24).withOpacity(.92)
          ..strokeWidth = size.width * .055
          ..strokeCap = ui.StrokeCap.round
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 13),
      );
      canvas.drawLine(
        flameStart,
        flameEnd,
        ui.Paint()
          ..color = const Color(0xFFFFF4D6).withOpacity(.96)
          ..strokeWidth = size.width * .018
          ..strokeCap = ui.StrokeCap.round
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5),
      );
    }

    // Soft white smoke curls along the flight path, never forming an explosion.
    final smokeRandom = math.Random(7200);
    for (var i = 0; i < 18; i++) {
      final y = origin.dy + size.height * (.12 + i * .052);
      final drift = math.sin(progress * 9 + i * .8) * (12 + i * 1.4);
      final x = origin.dx + drift + (smokeRandom.nextDouble() - .5) * 18;
      final radius = 9.0 + (i % 4) * 4.0;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        ui.Paint()
          ..color = Colors.white.withOpacity(.055 + (i % 3) * .012)
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, radius * 1.7),
      );
    }

    // Gold and blue sparks stream backward with long luminous tails.
    final random = math.Random(9107);
    for (var i = 0; i < 96; i++) {
      final lane = (random.nextDouble() - .5) * size.width * .9;
      final distance = random.nextDouble() * size.height * .82;
      final phase = (progress * 1.8 + random.nextDouble()) % 1.0;
      final y = origin.dy + size.height * (.10 + phase * .82);
      final x = origin.dx + lane + math.sin(progress * 10 + i) * 9;
      final length = 7 + random.nextDouble() * 24;
      final gold = i % 2 == 0;
      final color = gold ? const Color(0xFFFFD36B) : const Color(0xFF55BFFF);
      final alpha = (.28 + random.nextDouble() * .65).clamp(0.0, 1.0);
      canvas.drawLine(
        Offset(x, y - length),
        Offset(x + lane.sign * 2, y + length * .35),
        ui.Paint()
          ..color = color.withOpacity(alpha)
          ..strokeWidth = i % 7 == 0 ? 2.8 : 1.4
          ..strokeCap = ui.StrokeCap.round
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2),
      );
      canvas.drawCircle(
        Offset(x, y),
        i % 8 == 0 ? 2.7 : 1.5,
        ui.Paint()..color = Colors.white.withOpacity(alpha * .9),
      );
    }

    // A restrained blue/gold aura surrounds the jet's current position.
    canvas.drawCircle(
      origin,
      size.width * .22,
      ui.Paint()
        ..color = const Color(0xFF398DFF).withOpacity(.10)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 30),
    );
    canvas.drawCircle(
      origin,
      size.width * .17,
      ui.Paint()
        ..color = const Color(0xFFFFD36B).withOpacity(.07)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 22),
    );
  }

  @override
  bool shouldRepaint(covariant _CannonLaunchFireworksPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.origin != origin;
}

class _CannonRoomTile extends StatefulWidget {
  final String roomId;
  final String accessToken;
  final bool enableTestButton;
  final double bottomOffset;
  final VoidCallback onTap;

  const _CannonRoomTile({
    required this.roomId,
    required this.accessToken,
    this.enableTestButton = false,
    required this.bottomOffset,
    required this.onTap,
  });

  @override
  State<_CannonRoomTile> createState() => _CannonRoomTileState();
}

class _CannonRoomTileState extends State<_CannonRoomTile>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  late final AnimationController _flight = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4500),
  );
  final GlobalKey _cannonTileKey = GlobalKey();
  OverlayEntry? _flightOverlayEntry;
  bool _cannonAssetsPrecached = false;
  int _level = 1;
  int _progress = 0;
  int _need = 0;
  bool _requestInFlight = false;
  String _lastLaunchId = '';
  bool _hasInitialState = false;
  bool _testFlightMode = false;

  double get _ratio => _need <= 0
      ? 0
      : (_progress / _need).clamp(0.0, 1.0).toDouble();

  @override
  void initState() {
    super.initState();
    _flight.addStatusListener(_handleFlightStatus);
    CannonConfig.setAuthToken(widget.accessToken);
    _refreshCannon();
    _timer = Timer.periodic(CannonConfig.roomPoll, (_) => _refreshCannon());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cannonAssetsPrecached) return;
    _cannonAssetsPrecached = true;
    // Decode both animations before the launch event so the WEBP starts
    // immediately after the airplane instead of waiting for first decode.
    precacheImage(const AssetImage('assets/images/cannon/airplane_lv1.gif'), context);
  }

  @override
  void didUpdateWidget(covariant _CannonRoomTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId ||
        oldWidget.accessToken != widget.accessToken) {
      CannonConfig.setAuthToken(widget.accessToken);
      _lastLaunchId = '';
      _hasInitialState = false;
      _refreshCannon();
    }
  }

  Future<void> _refreshCannon() async {
    if (_requestInFlight || widget.roomId.isEmpty || widget.accessToken.isEmpty) {
      return;
    }
    _requestInFlight = true;
    try {
      CannonConfig.setAuthToken(widget.accessToken);
      final state = await CannonApi.fetchState(widget.roomId);
      if (!mounted || state == null) return;
      final nextLevel = state.level.clamp(1, 150).toInt();
      final nextProgress = state.progress.clamp(0, 2147483647).toInt();
      final nextNeed = state.need.clamp(0, 2147483647).toInt();

      // A new launch ID plus the level transition confirms that this room's
      // level-one contribution has completed. Play once for everyone in-room.
      if (_hasInitialState &&
          nextLevel != _level &&
          state.launching &&
          state.launchId.isNotEmpty &&
          state.launchId != _lastLaunchId) {
        _playLevelOneFlight(launchId: state.launchId);
      }

      _lastLaunchId = state.launchId;
      _hasInitialState = true;
      if (nextLevel != _level ||
          nextProgress != _progress ||
          nextNeed != _need) {
        setState(() {
          _level = nextLevel;
          _progress = nextProgress;
          _need = nextNeed;
        });
      }
    } finally {
      _requestInFlight = false;
    }
  }

  void _playTestBoxDrop() {
    if (!mounted || _boxDropOverlayEntry != null) return;
    _boxRoundId = '';
    _boxDropOverlayEntry = OverlayEntry(
      builder: (overlayContext) => CannonBoxDropOverlay(
        roundId: '',
        demoMode: true,
        onFinished: (_) {
          _boxDropOverlayEntry?.remove();
          _boxDropOverlayEntry = null;
        },
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_boxDropOverlayEntry!);
  }

  String _boxRoundId = '';
  OverlayEntry? _boxDropOverlayEntry;

  void _playTestFlight() {
    if (!mounted || _flight.isAnimating || _boxDropOverlayEntry != null) return;
    _testFlightMode = true;
    _boxRoundId = '';
    _insertFlightOverlay();
    _flight.forward(from: 0);
  }

  Future<void> _playLevelOneFlight({String launchId = ''}) async {
    if (_flight.isAnimating) return;
    _boxRoundId = '';
    if (launchId.isNotEmpty) {
      final round = await CannonApi.startBoxRound(launchId);
      if (!mounted) return;
      _boxRoundId = (round?['id'] ?? '').toString();
    }
    _insertFlightOverlay();
    _flight.forward(from: 0);
  }

  void _showFallingGiftBoxes() {
    if (!mounted || _boxRoundId.isEmpty) return;
    _boxDropOverlayEntry?.remove();
    _boxDropOverlayEntry = OverlayEntry(
      builder: (overlayContext) => CannonBoxDropOverlay(
        roundId: _boxRoundId,
        onFinished: (results) {
          _boxDropOverlayEntry?.remove();
          _boxDropOverlayEntry = null;
          if (!mounted || results.isEmpty) return;
          showDialog<void>(
            context: context,
            barrierDismissible: true,
            builder: (dialogContext) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: const Color(0xFF101747),
                title: const Text(
                  'جوائز الصناديق',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                ),
                content: SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: results.map((item) {
                        final icon = (item['rewardIcon'] ?? '').toString();
                        return Container(
                          width: 94,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF202B62),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFFD76A)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (icon.startsWith('https://'))
                                Image.network(icon, width: 42, height: 42, fit: BoxFit.contain)
                              else
                                const Icon(Icons.card_giftcard, color: Color(0xFFFFD76A), size: 40),
                              const SizedBox(height: 5),
                              Text(
                                (item['rewardName'] ?? 'هدية').toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('إغلاق', style: TextStyle(color: Color(0xFFFFD76A))),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_boxDropOverlayEntry!);
  }

  void _insertFlightOverlay() {
    _flightOverlayEntry?.remove();
    final overlay = Overlay.of(context, rootOverlay: true);
    _flightOverlayEntry = OverlayEntry(
      builder: (overlayContext) => AnimatedBuilder(
        animation: _flight,
        builder: (context, child) {
          final tileContext = _cannonTileKey.currentContext;
          final renderObject = tileContext?.findRenderObject();
          if (renderObject is! RenderBox || !renderObject.hasSize) {
            return const SizedBox.shrink();
          }
          final origin = renderObject.localToGlobal(Offset.zero);
          final screen = MediaQuery.sizeOf(overlayContext);
          final progress = _flight.value.clamp(0.0, 1.0).toDouble();

          // Launch from the cannon tile, reach the center at 65%, then
          // continue rising until the jet exits fully beyond the top edge.
          final startCenterX = origin.dx + renderObject.size.width / 2;
          final startCenterY = origin.dy + renderObject.size.height / 2;
          final ascent = (progress / .65).clamp(0.0, 1.0).toDouble();
          final exit = ((progress - .65) / .35).clamp(0.0, 1.0).toDouble();
          final centerEase = Curves.easeOutCubic.transform(ascent);
          final exitEase = Curves.easeInCubic.transform(exit);
          final planeCenterX = ui.lerpDouble(startCenterX, screen.width / 2, centerEase)!;
          final centerY = ui.lerpDouble(startCenterY, screen.height / 2, centerEase)!;
          final planeSize = screen.width * ui.lerpDouble(.65, .95, centerEase)!;
          final planeCenterY = progress <= .65
              ? centerY
              : ui.lerpDouble(centerY, -planeSize * .8, exitEase)!;
          final planeLeft = planeCenterX - planeSize / 2;
          final planeTop = planeCenterY - planeSize / 2;
          final cameraShake = (1 - progress) * 4.5;
          final shake = Offset(
            math.sin(progress * math.pi * 42) * cameraShake,
            math.cos(progress * math.pi * 37) * cameraShake,
          );
          final planeOpacity = 1.0;

          return SizedBox.expand(
            child: IgnorePointer(
              child: Transform.translate(
                offset: shake,
                child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _CannonLaunchFireworksPainter(
                        progress: progress,
                        origin: Offset(planeCenterX, planeCenterY),
                      ),
                    ),
                  ),
                  if (planeOpacity > .01)
                    Positioned(
                      left: planeLeft,
                      top: planeTop,
                      child: Opacity(
                        opacity: planeOpacity,
                        child: Image.asset(
                          'assets/images/cannon/airplane_lv1.gif',
                          width: planeSize,
                          height: planeSize,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                ],
                ),
              ),
            ),
          );
        },
      ),
    );
    overlay.insert(_flightOverlayEntry!);
  }

  void _handleFlightStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    _flightOverlayEntry?.remove();
    _flightOverlayEntry = null;
    if (_testFlightMode) {
      _testFlightMode = false;
      _playTestBoxDrop();
      return;
    }
    _showFallingGiftBoxes();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _flightOverlayEntry?.remove();
    _boxDropOverlayEntry?.remove();
    _flight.removeStatusListener(_handleFlightStatus);
    _flight.dispose();
    super.dispose();
  }

  Widget _progressTile() => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          Container(
            key: _cannonTileKey,
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.black.withOpacity(0.20),
            ),
            child: Center(
              child: CannonArt(level: _level, size: 66, dim: false),
            ),
          ),
          Positioned(
            left: 4,
            right: 4,
            bottom: 4,
            child: SizedBox(
              height: 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Color(0xFF101010)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: _ratio,
                        heightFactor: 1,
                        alignment: Alignment.centerLeft,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(color: Color(0xFF20D66B)),
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        '${(_ratio * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          shadows: [
                            Shadow(color: Colors.black, blurRadius: 2),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final tileTop = constraints.maxHeight - widget.bottomOffset - 72;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 12,
            bottom: widget.bottomOffset,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _progressTile(),
                const SizedBox(height: 8),
                const _RoomGameTile(
                  color1: Color(0xFF7A1F2B),
                  color2: Color(0xFFC9972C),
                  badge: 'VIP EXP ×1.8',
                ),
              ],
            ),
          ),
          if (widget.enableTestButton)
            Positioned(
              left: 92,
              bottom: widget.bottomOffset + 44,
              child: Material(
                color: const Color(0xFF16A6A0),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: _playTestFlight,
                  borderRadius: BorderRadius.circular(18),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Text('تجربة الطائرة كاملة', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _RoomGameTile extends StatelessWidget {
  const _RoomGameTile({
    required this.color1,
    required this.color2,
    required this.badge,
    this.timer,
    this.backgroundOpacity = 1,
    this.showContent = true,
    this.content,
    this.onTap,
  });

  final Color color1;
  final Color color2;
  final String badge;
  final String? timer;
  final double backgroundOpacity;
  final bool showContent;
  final Widget? content;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color1.withOpacity(backgroundOpacity),
              color2.withOpacity(backgroundOpacity),
            ],
          ),
        ),
        child: Stack(
          children: [
            if (content != null) Positioned.fill(child: content!),
            if (showContent && timer != null)
              Positioned(
                top: 3,
                right: 6,
                child: Text(timer!, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            if (showContent)
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
      ),
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

  Widget _countryFlag(
    BuildContext context, {
    required String countryName,
    required String countryCode,
  }) {
    // South Arabia is always resolved from the saved profile name first.
    final savedProfileFlag = countryFlagForProfileName(countryName);
    if (savedProfileFlag == 'SOUTH_ARABIA') {
      return SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: SquareCountryFlag('SOUTH_ARABIA', size: 24),
        ),
      );
    }

    // Match the saved country name before considering any ISO code.
    if (countryName.trim().isNotEmpty) {
      for (final country in CountryService().getAll()) {
        final translated = country.getTranslatedName(context) ?? country.name;
        if (translated.trim() == countryName.trim() ||
            country.name.trim().toLowerCase() ==
                countryName.trim().toLowerCase()) {
          return SizedBox(
            width: 24,
            height: 24,
            child: Center(child: SquareCountryFlag(country.flagEmoji, size: 24)),
          );
        }
      }
    }

    // Preserve other profile-specific flags after country-name matching.
    if (savedProfileFlag.isNotEmpty) {
      return SizedBox(
        width: 24,
        height: 24,
        child: Center(child: SquareCountryFlag(savedProfileFlag, size: 24)),
      );
    }

    // countryCode is only a fallback; it cannot override South Arabia above.
    final code = countryCode
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), '');
    if (code.length == 2 &&
        code.codeUnits.every((unit) => unit >= 65 && unit <= 90)) {
      return SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: SquareCountryFlag(String.fromCharCodes(code.codeUnits.map((unit) => 0x1F1E6 + unit - 65)), size: 24),
        ),
      );
    }

    // Keep compatibility with older data where the ISO code was stored in countryName.
    final nameCode = countryName
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), '');
    if (nameCode.length == 2 &&
        nameCode.codeUnits.every((unit) => unit >= 65 && unit <= 90)) {
      return SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: SquareCountryFlag(String.fromCharCodes(nameCode.codeUnits.map((unit) => 0x1F1E6 + unit - 65)), size: 24),
        ),
      );
    }
    return const SizedBox.shrink();
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
    final id = _value(['userCode', 'happyId', 'gaboId', 'publicId', 'happy_id', 'gabo_id'], '—');
    final avatar = _value(['avatarUrl', 'avatar', 'photoUrl']);
    final country = _value(
      ['countryName', 'country_name', 'country'],
    );
    final countryCode = _value(['countryCode', 'country_code']);
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
                        _countryFlag(context, countryName: country, countryCode: countryCode),
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
                            showCenteredNotification(context, 
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
                    color: const Color(0xFFE8E4EC),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: avatar.startsWith('http')
                      ? HappyNetworkImage(avatar, width: 110, height: 110, fit: BoxFit.cover)
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
    this.customIcon,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? customIcon;

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
          child: customIcon ?? Icon(icon, color: const Color(0xFFE5DFF0), size: 26),
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
            width: 14,
            height: 14,
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
    this.isLocked = false,
    required this.avatar,
    this.avatarSize = 48,
    this.rippleStartSize = 60,
    this.rippleEndSize = 120,
    this.micStyleUrl = '',
    this.micChairStyleUrl = '',
    this.micLockStyleUrl = '',
    this.micCircleScale = 100,
    this.micChairScale = 100,
    this.micLockScale = 100,
    this.micCircleClarity = 100,
    this.micChairClarity = 100,
    this.micLockClarity = 100,
    this.micCircleOpacity = 100,
    this.micChairOpacity = 100,
    this.micLockOpacity = 100,
    this.isOccupied = false,
  });

  final bool isSpeaking;
  final bool isLocked;
  final bool isOccupied;
  final Widget avatar;
  final double avatarSize;
  final double rippleStartSize;
  final double rippleEndSize;
  final String micStyleUrl;
  final String micChairStyleUrl;
  final String micLockStyleUrl;
  final double micCircleScale;
  final double micChairScale;
  final double micLockScale;
  final double micCircleClarity;
  final double micChairClarity;
  final double micLockClarity;
  final double micCircleOpacity;
  final double micChairOpacity;
  final double micLockOpacity;

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
          if (widget.micStyleUrl.startsWith('https://'))
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: _MicAssetEffects(
                    clarity: widget.micCircleClarity,
                    opacity: widget.micCircleOpacity,
                    child: Transform.scale(
                    scale: (widget.micCircleScale / 100).clamp(0.5, 1.5).toDouble(),
                    child: SVGAEasyPlayer(
                  key: ValueKey('mic-circle-${widget.micStyleUrl}'),
                  resUrl: widget.micStyleUrl,
                  fit: BoxFit.contain,
                  loops: true,
                  volume: 0,
                  muted: true,
                ),
                    ),
                    ),
                  ),
              ),
            ),
          if (!widget.isOccupied && widget.isLocked && widget.micLockStyleUrl.startsWith('https://'))
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: _MicAssetEffects(
                    clarity: widget.micLockClarity,
                    opacity: widget.micLockOpacity,
                    child: Transform.scale(
                    scale: (widget.micLockScale / 100).clamp(0.5, 1.5).toDouble(),
                    child: SVGAEasyPlayer(
                  key: ValueKey('mic-lock-${widget.micLockStyleUrl}'),
                  resUrl: widget.micLockStyleUrl,
                  fit: BoxFit.contain,
                  loops: true,
                  volume: 0,
                  muted: true,
                ),
                    ),
                    ),
                  ),
              ),
            ),
          if (!widget.isOccupied && !widget.isLocked && widget.micChairStyleUrl.startsWith('https://'))
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: _MicAssetEffects(
                    clarity: widget.micChairClarity,
                    opacity: widget.micChairOpacity,
                    child: Transform.scale(
                    scale: (widget.micChairScale / 100).clamp(0.5, 1.5).toDouble(),
                    child: SVGAEasyPlayer(
                  key: ValueKey('mic-chair-${widget.micChairStyleUrl}'),
                  resUrl: widget.micChairStyleUrl,
                  fit: BoxFit.contain,
                  loops: true,
                  volume: 0,
                  muted: true,
                ),
                    ),
                    ),
                  ),
              ),
            ),
          // Custom chair/lock animations replace the default empty-seat icon;
          // occupied seats always keep the participant avatar in front.
          if (widget.isOccupied ||
              (widget.isLocked
                  ? !widget.micLockStyleUrl.startsWith('https://')
                  : !widget.micChairStyleUrl.startsWith('https://')))
            Transform.scale(
              // صورة الشخص المشغول تملأ دائرة المايك بالكامل؛ لا نصغّرها
              // عند استخدام إطار SVGA مخصص.
              scale: widget.isOccupied
                  ? 1.0
                  : (widget.micStyleUrl.startsWith('https://') ? 0.76 : 1.0),
              child: widget.avatar,
            ),
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


// إطار دائري متقطع حول صورة المستخدم المنتظر لانضمامه للمايك.
class _DashedCircleBorderPainter extends CustomPainter {
  const _DashedCircleBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE6E0FF).withOpacity(.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 1.5;
    const dashCount = 22;
    const dashSweep = .13;
    for (var i = 0; i < dashCount; i++) {
      final start = -math.pi / 2 + (2 * math.pi * i / dashCount);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        dashSweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCircleBorderPainter oldDelegate) => false;
}

class HappyLevelBadge extends StatelessWidget {
  final String level;
  const HappyLevelBadge({super.key, this.level = "1"});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.only(left: 4, right: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF1E6B3A),
            Color(0xFF3CB35F),
            Color(0xFF8FD176),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Lv. $level",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 5),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.3),
                radius: 0.9,
                colors: [
                  Colors.white.withOpacity(0.95),
                  const Color(0xFFB9E8C0),
                  const Color(0xFF7ED490).withOpacity(0.8),
                ],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.6),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.5),
                  blurRadius: 4,
                  offset: const Offset(-1, -1),
                ),
              ],
            ),
            child: Center(
              child: Text(
                "H",
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withOpacity(0.95),
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Asymmetric PK timer silhouette: straight top, inward side curves,
/// deep lower corner cut-outs and a soft centered V-shaped dip.

class StartPkButton extends StatelessWidget {
  const StartPkButton({super.key});

  @override
  Widget build(BuildContext context) {
    // Match the countdown's natural compact footprint without scaling the
    // original 280px button down (which made it difficult to see).
    return SizedBox(
      width: 110,
      height: 22,
      child: ClipPath(
        clipper: StartButtonShape(),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFF3A5BFF), Color(0xFF7A4DFF), Color(0xFFFF4D8D)],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: StartButtonBorder())),
              const Center(
                child: Text('بدأ', style: TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900,
                )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StartButtonShape extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    // Rounded double-ended arrow: the left and right frame tips point
    // outward while all transitions remain softly curved.
    final w = size.width;
    final h = size.height;
    final tip = h * 0.48;
    final radius = h * 0.12;

    return Path()
      ..moveTo(radius, 0)
      ..lineTo(w - radius, 0)
      ..quadraticBezierTo(w - radius * 0.25, 0, w - radius * 0.1, radius)
      ..quadraticBezierTo(w - tip * 0.28, h * 0.34, w, h / 2)
      ..quadraticBezierTo(w - tip * 0.28, h * 0.66, w - radius * 0.1, h - radius)
      ..quadraticBezierTo(w - radius * 0.25, h, w - radius, h)
      ..lineTo(radius, h)
      ..quadraticBezierTo(radius * 0.25, h, radius * 0.1, h - radius)
      ..quadraticBezierTo(tip * 0.28, h * 0.66, 0, h / 2)
      ..quadraticBezierTo(tip * 0.28, h * 0.34, radius * 0.1, radius)
      ..quadraticBezierTo(radius * 0.25, 0, radius, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class StartButtonBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = StartButtonShape().getClip(size);
    canvas.drawPath(path, Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);
    final innerPath = StartButtonShape().getClip(Size(size.width - 6, size.height - 6));
    canvas.save();
    canvas.translate(3, 3);
    canvas.drawPath(innerPath, Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PkTimerFrame extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;

    // Large capsule-like rounding across both lower corners.
    path.moveTo(w * 0.18, h);
    path.lineTo(w * 0.82, h);
    path.cubicTo(
      w * 0.94, h,
      w * 0.98, h * 0.85,
      w * 0.97, h * 0.25,
    );
    // Double the previous extension: extend 30% beyond each side, preserving the edge shape.
    path.quadraticBezierTo(w, 0, w * 1.30, 0);
    path.lineTo(w * -0.30, 0);
    path.quadraticBezierTo(0, 0, w * 0.03, h * 0.25);
    path.cubicTo(
      w * 0.03, h * 0.85,
      w * 0.06, h,
      w * 0.18, h,
    );
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _GamesTabPlaceholder extends StatelessWidget {
  const _GamesTabPlaceholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.sports_esports_outlined,
          size: 42,
          color: Color(0xFFB49A58),
        ),
        const SizedBox(height: 12),
        Text(
          message,
          style: const TextStyle(
            color: Color(0xFF756B58),
            fontSize: 14,
          ),
        ),
      ],
    ),
  );
}


class _MicAssetEffects extends StatelessWidget {
  const _MicAssetEffects({required this.child, required this.clarity, required this.opacity});
  final Widget child;
  final double clarity;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final factor = (clarity / 100).clamp(0.5, 1.5).toDouble();
    final alpha = (opacity / 100).clamp(0.0, 1.0).toDouble();
    return Opacity(
      opacity: alpha,
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(<double>[
          factor, 0, 0, 0, 0,
          0, factor, 0, 0, 0,
          0, 0, factor, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: child,
      ),
    );
  }
}
