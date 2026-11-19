import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'ranking_sheet_pro.dart';

class VoiceRoomDesignPreview extends StatelessWidget {
  static final Set<String> _openingRoomInfo = <String>{};

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
    this.ownerAvatarUrl = '',
    this.ownerCountryName = '',
    this.isCurrentUserRoomOwner = false,
    this.canModerateUsers = false,
    this.selfMicMuted = false,
    this.onToggleSelfMic,
    this.onModerateUser,
    this.showRoomActions = false,
    this.onRoomActions,
    this.onMinimizeRoom,
    this.onCloseRoom,
    this.onUpgradeRoom,
    this.onOpenGifts,
    this.onRoomSettingsChanged,
    required this.chatController,
    required this.chatFocusNode,
    required this.onSendChat,
    required this.accessToken,
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
  final String ownerAvatarUrl;
  final String ownerCountryName;
  final bool isCurrentUserRoomOwner;
  final bool canModerateUsers;
  final bool selfMicMuted;
  final Future<bool> Function()? onToggleSelfMic;
  final Future<bool> Function(String targetUserId, String action)? onModerateUser;
  final bool showRoomActions;
  final VoidCallback? onRoomActions;
  final VoidCallback? onMinimizeRoom;
  final VoidCallback? onCloseRoom;
  final Future<void> Function(String roomId, int level)? onUpgradeRoom;
  final VoidCallback? onOpenGifts;
  final VoidCallback? onRoomSettingsChanged;
  final TextEditingController chatController;
  final FocusNode chatFocusNode;
  final Future<void> Function() onSendChat;
  final String accessToken;

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
          Positioned.fill(
            child: Image.asset(
              'assets/images/room_background/happy_live_room_bg.png.PNG',
              fit: BoxFit.cover,
              alignment: Alignment.center,
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
                    final micLayout = micLayoutById(_roomInfoString(['micLayoutId', 'mic_layout_id'], 'm8'));
                    final columns = micLayout.maxCols;
                    final rows = micLayout.rows.length;
                    final tileWidth = (constraints.maxWidth - (columns - 1) * 12) / columns;
                    final seatsHeight = (tileWidth / .88) * rows + 12 * (rows - 1);
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
                            // Keep hit testing aligned with the chat's visual
                            // position so sender names and avatars receive taps.
                            transformHitTests: true,
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
            ScaffoldMessenger.of(context).showSnackBar(
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تمت ترقية الغرفة إلى ${kLevels[levelIndex].name}')),
                    );
                  } catch (error) {
                    if (context.mounted) {
                      final message = error.toString().replaceFirst('Exception: ', '');
                      ScaffoldMessenger.of(context).showSnackBar(
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ميزة المتابعة قريبًا')));
        },
        onJoin: () {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ميزة الانضمام للمجموعة قريبًا')));
        },
        onSettings: () {
          Navigator.of(context).pop();
          final roomId = (room['id'] ?? room['roomId'] ?? room['room_id'] ?? '').toString().trim();
          if (roomId.isEmpty || accessToken.trim().isEmpty || !info.isRoomOwner) {
            ScaffoldMessenger.of(context).showSnackBar(
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
              ),
            ),
          ).then((_) => onRoomSettingsChanged?.call());
        },
        onInvite: () {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('دعوة الأعضاء قريبًا')));
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
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              barrierColor: Colors.black.withOpacity(.55),
              builder: (sheetContext) => SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: const [RankingSheet()],
                ),
              ),
            ),
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
    final layout = micLayoutById(_roomInfoString(['micLayoutId', 'mic_layout_id'], 'm8'));
    final columns = layout.maxCols;
    // Preserve each row's own alignment by building a padded row-major list.
    final arrangedCells = <MicSeat?>[];
    for (final row in layout.rows) {
      arrangedCells.addAll(row);
      arrangedCells.addAll(List<MicSeat?>.filled(columns - row.length, null));
    }
    return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: arrangedCells.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: .88,
      ),
      itemBuilder: (context, index) {
        final slot = arrangedCells[index];
        if (slot == null) return const SizedBox.shrink();
        final number = layout.seatNumber(slot);
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Selector<SeatStateStore, SeatState>(
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
        final isDefaultEight = layout.id == 'm8';
        final seatOffset = !isDefaultEight
            ? 0.0
            : isAndroid
                ? (number <= 4 ? 2.0 : -12.0)
                : (number <= 4 ? -5.0 : -21.0);
        return Transform.translate(
          offset: Offset(0, seatOffset + (isAndroid ? 0 : 5)),
          child: Transform.translate(
            offset: Offset(0, seatOffset + (number <= 4 ? 1 : 3)),
            child: Align(
              alignment: Alignment.topCenter,
              child: Transform.translate(
                offset: isDefaultEight && number == 5 ? const Offset(5, 0) : Offset.zero,
                child: GestureDetector(
                // Do not let the full seat rectangle block taps on listener
                // avatars painted underneath the transparent/empty seat area.
                behavior: HitTestBehavior.deferToChild,
                onTap: null,
                child: SizedBox(
                  width: 72,
                  height: number == 5 ? 82 : 72,
                  child: Transform.translate(
                    offset: Offset(isDefaultEight && number == 5 ? -5 : 0, isDefaultEight && number > 4 ? 5 : 0),
                    transformHitTests: false,
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: occupied
                        ? () => _showUserProfile(context, seat!)
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
                    child: _GoldenVoiceWave(
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
                        color: Colors.white.withOpacity(.14),
                        border: Border.all(
                          color: mine ? Colors.transparent : Colors.white.withOpacity(occupied ? .82 : .48),
                          width: mine ? 0 : occupied ? 2 : 1,
                        ),
                        // Improve separation from the new wallpaper without
                        // changing the seats' original transparency.
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x99000000),
                            blurRadius: 9,
                            spreadRadius: 1,
                            offset: Offset(0, 2),
                          ),
                        ],
                        image: avatar.startsWith('http')
                            ? DecorationImage(image: NetworkImage(avatar), fit: BoxFit.cover)
                            : null,
                      ),
                      child: avatar.startsWith('http')
                          ? null
                          : Icon(
                              occupied ? Icons.mic_rounded : locked ? Icons.lock_outline : Icons.weekend_outlined,
                              color: Colors.white.withOpacity(.92),
                              size: 23,
                            ),
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
              else
                Transform.translate(
                  offset: const Offset(0, 2),
                  child: Text(
                    locked ? 'مقفل' : '$number',
                    style: TextStyle(
                      color: Colors.white.withOpacity(.65),
                      fontSize: 13,
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
              ),
            ),
          ),
        );
          },
        ));
      },
    ),
  );
  }

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

  Widget _listeners(BuildContext context) => Transform.translate(
    offset: Theme.of(context).platform == TargetPlatform.android
        ? const Offset(0, -112)
        : const Offset(0, -65),
    child: Container(
    height: 30,
    margin: const EdgeInsets.symmetric(horizontal: 12),
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
                            child: CircleAvatar(
                              radius: 11,
                              backgroundColor: Colors.white24,
                              backgroundImage: avatar.startsWith('http')
                                  ? NetworkImage(avatar)
                                  : null,
                              child: !avatar.startsWith('http')
                                  ? const Icon(Icons.person,
                                      color: Colors.white70, size: 14)
                                  : null,
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



