import 'dart:async';
import '../widgets/centered_notification.dart';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:happy_live/models/message.dart';
import 'package:happy_live/models/seat_state.dart';
import 'package:happy_live/pages/voice_room_design_preview.dart';
import 'package:happy_live/widgets/room_level_sheet.dart';
import 'package:happy_live/services/agora_room_bridge.dart';
import 'package:happy_live/services/room_seat_socket.dart';
import 'package:happy_live/pages/wallet_page.dart';
import 'package:happy_live/widgets/room_gift_sheet.dart';
import 'package:flutter_svga/flutter_svga.dart';
import 'package:gif_view/gif_view.dart';
import 'package:happy_live/widgets/happy_network_image.dart';
import 'package:audioplayers/audioplayers.dart';
import '../room_tools/room_tools_controller.dart';
import '../room_tools/room_tools_models.dart';
import '../room_tools/room_tools_api.dart';
import '../room_tools/room_tools_sheet.dart';
import '../room_tools/room_tools_media_sheet.dart';
import '../room_settings/room_settings_controller.dart';
import '../room_settings/my_workers_api.dart';
import '../room_settings/pages/room_settings_page.dart';
import '../widgets/mic_count_sheet.dart';
import '../models/mic_layout.dart';
import '../widgets/dynamic_games_list.dart';
import '../cannon/cannon_service.dart';
import '../cannon/cannon_sheet.dart';
import '../pk/pk_sheet.dart';

class RoomPage extends StatefulWidget {
  const RoomPage({super.key, required this.room, required this.accessToken});

  final Map<String, dynamic> room;
  final String accessToken;

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  static const _background = Color(0xFF09080D);
  static const _surface = Color(0xFF17131F);
  static const _purple = Color(0xFFD9A93C);
  static const _gold = Color(0xFFE8C477);
  static const _muted = Color(0xFFAAA2B5);
  static const String _apiBase = 'https://happy-live-api.taher616270.workers.dev/api/v1';
  // Short-lived in-memory room snapshots make recently visited rooms appear immediately.
  // The authenticated seat response is scoped to this session and is always refreshed from the API.
  static final Map<String, Map<String, dynamic>> _roomPreviewCache = <String, Map<String, dynamic>>{};
  static const Duration _roomPreviewCacheTtl = Duration(seconds: 15);
  // Persistent country fallback keeps speaker flags visible during temporary
  // network loss or incomplete realtime seat snapshots.
  static const String _countryNameCacheKey = 'happy_live_country_name_cache_v1';
  final Map<String, String> _countryNameCache = <String, String>{};
  bool _countryNameCacheLoaded = false;

  Timer? _refreshTimer;
  Timer? _volumeTimer;
  Map<int, double> _speakerLevels = <int, double>{};
  final Map<int, DateTime> _speakerLastHeardAt = <int, DateTime>{};
  final Map<int, Timer> _hideTimers = <int, Timer>{};
  final Set<int> speaking = <int>{};
  WebSocketChannel? _chatChannel;
  StreamSubscription<dynamic>? _chatSubscription;
  Timer? _chatReconnectTimer;
  Timer? _chatFallbackTimer;
  bool _chatSessionActive = false;
  bool _chatStarting = false;
  bool _chatConnecting = false;
  bool _chatSocketConnected = false;
  bool _chatSending = false;
  bool _chatHistoryLoading = false;
  int _chatReconnectAttempts = 0;
  final Set<String> _messageIds = <String>{};
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _roomChatFocusNode = FocusNode();
  final List<Message> _messages = [];
  final GlobalKey<AnimatedListState> _roomAnimatedListKey = GlobalKey<AnimatedListState>();
  final ScrollController _roomMessagesController = ScrollController();
  DateTime _lastLocalMessageAt = DateTime.fromMillisecondsSinceEpoch(0);
  late String _roomAnnouncement;
  DateTime _lastHeartbeat = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isLoading = true;
  bool _roomDataReady = false;
  bool _isRefreshing = false;
  bool _refreshSeatsQueued = false;
  bool _isMinimized = false;
  bool _showRoomActions = false;
  bool _isClosingRoom = false;
  Offset _miniOffset = const Offset(18, 170);
  OverlayEntry? _miniOverlayEntry;
  Route<dynamic>? _roomRoute;
  bool _isChangingSeat = false;
  final Set<int> _pendingSeatNumbers = <int>{};
  final Map<int, int> _seatModerationRevision = <int, int>{};
  // Prevent overlapping lock/unlock writes for the same microphone.
  final Set<int> _pendingSeatLockRequests = <int>{};
  final Map<int, bool> _pendingSeatLockValues = <int, bool>{};
  final Map<int, Stopwatch> _seatMoveTimers = <int, Stopwatch>{};
  final SeatStateStore _seatStateStore = SeatStateStore();
  RoomSeatSocket? _seatSocket;
  bool _agoraSyncInProgress = false;
  bool? _agoraDesiredPublish;
  bool? _agoraJoinedPublish;
  bool _voiceEnabled = true;
  bool _amRoomOwner = false;
  bool _amRoomModerator = false;
  bool _selfMicMuted = false;
  bool _isBannedFromRoom = false;
  String? _loadError;
  int? _mySeat;
  String _ownerName = 'صاحب الغرفة';
  String _ownerId = '';
  String _ownerAvatarUrl = '';
  String _roomCoverUrl = '';
  String _ownerCountryName = '';
  List<Map<String, dynamic>> _seats = [];
  List<Map<String, dynamic>> _audienceUsers = [];
  int _audienceCount = 0;
  Map<String, dynamic>? _activeRoomGift;
  Timer? _roomGiftOverlayTimer;
  int _roomGiftOverlayNonce = 0;
  bool _giftAudioUnlocked = false;
  final AudioPlayer _giftAudioPlayer = AudioPlayer();
  int _roomLevel = 1;
  int _roomExperienceLevel = 1;
  int _roomExperienceExp = 0;
  int _roomExperienceNextLevelExp = 3300000;
  int _roomDailyExperienceExp = 0;
  int _micCount = 0;
  String _micLayoutId = '';
  Map<String, dynamic>? _roomCounter;
  Map<String, int> _roomGiftScores = <String, int>{};
  bool _roomBattleTeamMode = false;
  bool _roomBattleActive = false;
  bool _pkVisualMode = false;
  bool _pkStarted = false;
  int _pkDurationMinutes = 5;
  int _pkDefaultDurationMinutes = 5;
  int _pkBlueScore = 0;
  int _pkRedScore = 0;
  Map<String, int> _pkUserScores = <String, int>{};
  DateTime? _pkEndsAt;
  Timer? _pkTicker;
  Timer? _pkStartCountdownTimer;
  bool _pkStartingCountdown = false;
  int _pkNowMs = DateTime.now().millisecondsSinceEpoch;
  bool _pkActionBusy = false;
  bool _pkEnabled = true;
  String _pkChallengeTitle = 'تحدي PK';
  String _pkSquareMediaUrl = '';
  String _pkSquareMediaType = '';
  bool _pkShowChallengeTitle = true;
  bool _pkShowStartText = true;
  bool _pkShowTimer = true;
  String _pkStartMediaUrl = '';
  String _pkStartMediaType = '';
  int _pkStartShowDurationSeconds = 3;
  double _pkStartHideDurationSeconds = 0.5;
  bool _pkStartHiding = false;
  double _pkSquareRadius = 26;
  double _pkSquareWidthPercent = 100;
  double _pkSquareHeight = 284;
  double _pkMediaOpacity = 0.85;
  String _normalMicBorderColor = '#FFFFFF';
  double _normalMicBorderWidth = 1.5;
  String _normalMicFillColor = '#FFFFFF';
  double _normalMicFillOpacity = 0.14;
  String _pkMicBorderColor = '#FFFFFF';
  double _pkMicBorderWidth = 2.4;
  String _pkMicFillColor = '#FFFFFF';
  double _pkMicFillOpacity = 0.12;
  String _pkBlueMicBorderColor = '#258BFF';
  String _pkRedMicBorderColor = '#FF4B5C';
  String _micStyleSvgaUrl = '';
  String _micChairSvgaUrl = '';
  String _micLockSvgaUrl = '';
  double _micCircleScale = 100;
  double _micChairScale = 100;
  double _micLockScale = 100;
  double _micCircleClarity = 100;
  double _micChairClarity = 100;
  double _micLockClarity = 100;
  double _micCircleOpacity = 100;
  double _micChairOpacity = 100;
  double _micLockOpacity = 100;
  List<int> _pkDurationOptions = <int>[5, 15, 30, 120];
  Timer? _roomCounterTicker;
  int _roomCounterNow = 0;

  String get _roomId => (widget.room['id'] ?? '').toString();
  String get _roomName => (widget.room['name'] ?? 'غرفة صوتية').toString();
  String get _roomCode => (widget.room['roomCode'] ?? '').toString();
  String? get _imageUrl {
    final value = widget.room['imageUrl']?.toString();
    return value != null && value.startsWith('https://') ? value : null;
  }

  Uri get _seatsUri => Uri.parse('$_apiBase/rooms/${Uri.encodeComponent(_roomId)}/seats');
  Uri get _chatSessionUri => Uri.parse('$_apiBase/rooms/${Uri.encodeComponent(_roomId)}/chat-session');
  Uri get _messagesUri => Uri.parse('$_apiBase/rooms/${Uri.encodeComponent(_roomId)}/messages');
  Uri get _announcementUri => Uri.parse('$_apiBase/rooms/${Uri.encodeComponent(_roomId)}/announcement');
  Uri get _moderationUri => Uri.parse('$_apiBase/rooms/${Uri.encodeComponent(_roomId)}/moderation');
  Uri get _roomBattleUri => Uri.parse('$_apiBase/rooms/${Uri.encodeComponent(_roomId)}/battle');
  Uri get _chatStreamUri {
    final base = Uri.parse(_apiBase);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path}/rooms/${Uri.encodeComponent(_roomId)}/chat-stream',
      query: null,
      fragment: null,
    );
  }
  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${widget.accessToken}',
    'Content-Type': 'application/json',
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _roomRoute ??= ModalRoute.of(context);
  }

  @override
  void initState() {
    super.initState();
    _roomAnnouncement = (widget.room['announcement'] ?? widget.room['description'] ?? '').toString();
    _roomCoverUrl = (widget.room['imageUrl'] ?? widget.room['image_url'] ?? widget.room['coverUrl'] ?? widget.room['cover_url'] ?? '').toString();
    _restoreRoomPreviewCache();
    unawaited(_restoreCountryNameCache());

    // Let Flutter paint the room immediately from the room card data first.
    // Network work starts after the first frame and never blocks the room UI.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_refreshSeats());
      unawaited(_startRoomChat());
      unawaited(_connectRoomSeatSocket());
      unawaited(_loadInitialPkState());
      unawaited(_joinAgora(publish: false));
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_refreshSeats());
      unawaited(_sendHeartbeat());
    });
    _volumeTimer = Timer.periodic(const Duration(milliseconds: 160), (_) {
      unawaited(_refreshAudioLevels());
    });
  }

  Future<void> _restoreCountryNameCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_countryNameCacheKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            final userId = key.toString().trim();
            final countryName = value?.toString().trim() ?? '';
            if (userId.isNotEmpty && countryName.isNotEmpty) {
              _countryNameCache[userId] = countryName;
            }
          });
        }
      }
    } catch (_) {
      // Cache is best-effort; room functionality must not depend on it.
    } finally {
      _countryNameCacheLoaded = true;
    }
    if (!mounted || _seats.isEmpty || _countryNameCache.isEmpty) return;
    var changed = false;
    final restored = _seats.map((seat) {
      final next = Map<String, dynamic>.from(seat);
      final userId = (next['userId'] ?? '').toString();
      if ((next['countryName'] ?? '').toString().trim().isEmpty &&
          (_countryNameCache[userId] ?? '').isNotEmpty) {
        next['countryName'] = _countryNameCache[userId];
        changed = true;
      }
      return next;
    }).toList();
    if (changed) setState(() => _seats = restored);
  }

  void _rememberCountryNames(List<Map<String, dynamic>> seats) {
    var changed = false;
    for (final seat in seats) {
      final userId = (seat['userId'] ?? '').toString().trim();
      final countryName = (seat['countryName'] ?? seat['country_name'] ?? '').toString().trim();
      if (userId.isEmpty || countryName.isEmpty) continue;
      if (_countryNameCache[userId] != countryName) {
        _countryNameCache[userId] = countryName;
        changed = true;
      }
    }
    if (changed) unawaited(_persistCountryNameCache());
  }

  Future<void> _persistCountryNameCache() async {
    if (!_countryNameCacheLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_countryNameCacheKey, jsonEncode(_countryNameCache));
    } catch (_) {
      // A failed local write must never interrupt room updates.
    }
  }

  Future<void> _connectRoomSeatSocket() async {
    if (_roomId.isEmpty || widget.accessToken.isEmpty || _seatSocket != null) return;
    final socket = RoomSeatSocket(
      apiBase: _apiBase,
      roomId: _roomId,
      accessToken: widget.accessToken,
      onEvent: _handleSeatSocketEvent,
    );
    _seatSocket = socket;
    await socket.connect();
  }

  void _handleSeatSocketEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final type = event['type']?.toString();
    if (type == 'room_gift') {
      _showRoomGiftOverlay(event);
      return;
    }
    if (type == 'room_battle') {
      _applyPkBattleState(event);
      return;
    }
    if (type == 'room_battle_score') {
      _applyPkBattleScores(event);
      return;
    }
    if (type == 'room_counter') {
      final rawCounter = event['counter'];
      _roomCounterTicker?.cancel();
      final nextCounter = rawCounter is Map ? Map<String, dynamic>.from(rawCounter) : null;
      final rawScores = nextCounter?['scores'];
      final nextScores = <String, int>{};
      if (rawScores is Map) {
        rawScores.forEach((key, value) {
          final score = value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
          if (score != null && score >= 0) nextScores[key.toString()] = score;
        });
      }
      setState(() {
        _roomCounter = nextCounter;
        _roomGiftScores = nextScores;
        _roomCounterNow = DateTime.now().millisecondsSinceEpoch;
      });
      if (_roomCounter != null) {
        _roomCounterTicker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _roomCounterNow = DateTime.now().millisecondsSinceEpoch);
        });
      }
      return;
    }
    if (type == 'room_counter_history') {
      final records = event['records'] is List
          ? (event['records'] as List).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
          : <Map<String, dynamic>>[];
      _showRoomCounterHistory(records);
      return;
    }
    if (type == 'room_counter_error') {
      _showMessage(event['code'] == 'counter_already_active' ? 'العداد يعمل بالفعل' : 'تعذر تشغيل العداد، تحقق من المدة المحددة');
      return;
    }
    final rawSeats = event['seats'];
    var seats = rawSeats is List ? rawSeats : const <dynamic>[];
    final socketSeatControls = event['seatControls'] is Map
        ? Map<String, dynamic>.from(event['seatControls'] as Map)
        : null;
    if (socketSeatControls != null) {
      final byNumber = <int, Map<String, dynamic>>{
        for (final raw in seats)
          if (raw is Map && raw['seatNumber'] is num)
            (raw['seatNumber'] as num).toInt(): Map<String, dynamic>.from(raw),
      };
      seats = List<dynamic>.generate(_micCount, (index) {
        final number = index + 1;
        final seat = byNumber[number] ?? <String, dynamic>{
          'seatNumber': number,
          'userId': '',
          'isMuted': false,
          'isLocked': false,
          'isMe': false,
        };
        final control = socketSeatControls[number.toString()];
        if (control is Map) {
          seat['isLocked'] = control['isLocked'] == true;
          seat['isMuted'] = seat['isMuted'] == true || control['isMuted'] == true;
        }
        return seat;
      });
    }

    if (type == 'seat_snapshot') {
      _seatMoveTimers.clear();
      _applyRealtimeSeatSnapshot(
        seats,
        mySeat: event['mySeat'] is num ? (event['mySeat'] as num).toInt() : null,
        seatControls: event['seatControls'] is Map ? Map<String, dynamic>.from(event['seatControls'] as Map) : null,
        reconcilePending: true,
      );
      return;
    }
    if (type == 'seat_updated') {
      _applyRealtimeSeatSnapshot(
        seats,
        seatControls: event['seatControls'] is Map ? Map<String, dynamic>.from(event['seatControls'] as Map) : null,
      );
      return;
    }

    if (type == 'ack') {
      final version = event['version'];
      if (version is! num) return;
      final moveVersion = version.toInt();
      final moveTimer = _seatMoveTimers.remove(moveVersion);
      if (moveTimer != null) {
        debugPrint('[SeatLatency] server_ack_ms=${(moveTimer.elapsedMicroseconds / 1000).toStringAsFixed(2)} version=$moveVersion');
      }
      final accepted = event['ok'] == true;
      final isLatest = _seatStateStore.isLatest(moveVersion);
      _seatStateStore.resolveMove(
        version: moveVersion,
        accepted: accepted,
        serverSeats: seats,
        serverMySeat: event['mySeat'] is num ? (event['mySeat'] as num).toInt() : null,
      );
      if (isLatest) {
        _applyRealtimeSeatSnapshot(
          seats,
          mySeat: event['mySeat'] is num ? (event['mySeat'] as num).toInt() : null,
          updateStore: false,
        );
        if (!accepted && event['code'] == 'seat_occupied') {
          _showMessage('هذا المايك مشغول، اختر مايكًا آخر');
        } else if (!accepted && event['code'] == 'mic_restricted') {
          _showMessage('استخدام المايك متاح للمالك والمشرفين فقط');
        } else if (!accepted && event['code'] == 'seat_locked') {
          _showMessage('هذا المايك مقفل');
        } else if (!accepted) {
          _showMessage('تعذر تغيير المايك، تمت استعادة المقعد السابق');
        }
      }
      return;
    }

    if (type == 'socket_unavailable') {
      // The optimistic avatar remains visible while the socket reconnects.
      return;
    }
  }

  void _applyRealtimeSeatSnapshot(
    List<dynamic> rawSeats, {
    int? mySeat,
    Map<String, dynamic>? seatControls,
    bool updateStore = true,
    bool reconcilePending = false,
  }) {
    if (seatControls != null) {
      final byNumber = <int, Map<String, dynamic>>{
        for (final raw in rawSeats)
          if (raw is Map && raw['seatNumber'] is num)
            (raw['seatNumber'] as num).toInt(): Map<String, dynamic>.from(raw),
      };
      rawSeats = List<dynamic>.generate(_micCount, (index) {
        final number = index + 1;
        final seat = byNumber[number] ?? <String, dynamic>{
          'seatNumber': number,
          'userId': '',
          'isMuted': false,
          'isLocked': false,
          'isMe': false,
        };
        final control = seatControls[number.toString()];
        if (control is Map) {
          seat['isLocked'] = control['isLocked'] == true;
          seat['isMuted'] = seat['isMuted'] == true || control['isMuted'] == true;
        }
        return seat;
      });
    }
    final previousSeatsByUserId = <String, Map<String, dynamic>>{
      for (final previous in _seats)
        if ((previous['userId'] ?? '').toString().isNotEmpty)
          (previous['userId'] ?? '').toString(): previous,
    };
    final normalizedByUser = <String, Map<String, dynamic>>{};
    final normalizedEmptySeats = <Map<String, dynamic>>[];
    for (final item in rawSeats.whereType<Map>()) {
      final seat = Map<String, dynamic>.from(item);
      final userId = (seat['userId'] ?? '').toString();
      final previous = previousSeatsByUserId[userId];
      // Keep the latest DB-backed country while realtime seat events update mic state.
      if ((seat['countryName'] ?? '').toString().trim().isEmpty &&
          (previous?['countryName'] ?? '').toString().trim().isNotEmpty) {
        seat['countryName'] = previous!['countryName'];
      }
      if ((seat['countryName'] ?? '').toString().trim().isEmpty &&
          (_countryNameCache[userId] ?? '').isNotEmpty) {
        seat['countryName'] = _countryNameCache[userId];
      }
      seat['isMe'] = userId.isNotEmpty &&
          userId == _seatStateStore.currentUserId;
      if (userId.isEmpty) {
        normalizedEmptySeats.add(seat);
        continue;
      }
      final existing = normalizedByUser[userId];
      final seatNumber = seat['seatNumber'];
      final existingNumber = existing?['seatNumber'];
      final isPreferred = (mySeat != null && seatNumber is num && seatNumber.toInt() == mySeat) || seat['isMe'] == true;
      final existingPreferred = existing != null &&
          ((mySeat != null && existingNumber is num && existingNumber.toInt() == mySeat) || existing['isMe'] == true);
      if (existing == null || (isPreferred && !existingPreferred)) {
        normalizedByUser[userId] = seat;
      }
    }
    final normalized = <Map<String, dynamic>>[
      ...normalizedByUser.values,
      ...normalizedEmptySeats,
    ]..sort((a, b) => ((a['seatNumber'] as num?)?.toInt() ?? 0)
        .compareTo((b['seatNumber'] as num?)?.toInt() ?? 0));
    // Keep an optimistic lock state stable while HTTP/socket/periodic snapshots
    // are still catching up with the server write.
    for (final seat in normalized) {
      final number = (seat['seatNumber'] as num?)?.toInt();
      final pendingLock = number == null ? null : _pendingSeatLockValues[number];
      if (pendingLock != null) {
        seat['isLocked'] = pendingLock;
        seat['locked'] = pendingLock;
      }
    }
    _rememberCountryNames(normalized);
    final mine = normalized.where((seat) => seat['isMe'] == true).toList();
    final nextMySeat = mySeat ?? (mine.isEmpty ? null : (mine.first['seatNumber'] as num).toInt());
    final hasPendingLocalMove = updateStore && !reconcilePending && _seatStateStore.hasPendingMoves;
    final effectiveMySeat = hasPendingLocalMove ? _seatStateStore.mySeat : nextMySeat;
    final previousMySeat = _mySeat;
    final mySeatEntries = normalized.where((seat) => seat['isMe'] == true).toList();
    final nextRealtimeMuted = mySeatEntries.isNotEmpty && mySeatEntries.first['isMuted'] == true;
    final realtimeMuteChanged = !hasPendingLocalMove && mySeatEntries.isNotEmpty && _selfMicMuted != nextRealtimeMuted;
    if (updateStore) {
      if (reconcilePending) {
        _seatStateStore.reconcileSnapshot(normalized, mySeat: nextMySeat);
      } else if (_seatStateStore.hasPendingMoves) {
        _seatStateStore.applyRemoteSnapshotPreservingPending(normalized);
      } else {
        _seatStateStore.applySnapshot(normalized, mySeat: nextMySeat);
      }
    }
    if (mounted) {
      setState(() {
        _seats = normalized;
        _mySeat = effectiveMySeat;
        if (!hasPendingLocalMove && mySeatEntries.isNotEmpty) _selfMicMuted = nextRealtimeMuted;
      });
    } else {
      _seats = normalized;
      _mySeat = effectiveMySeat;
    }
    if (realtimeMuteChanged) {
      if (nextRealtimeMuted) unawaited(AgoraRoomBridge.setMuted(true));
      unawaited(_joinAgora(publish: nextMySeat != null && !nextRealtimeMuted));
    } else if (previousMySeat == null && effectiveMySeat != null) {
      unawaited(_joinAgora(publish: true));
    } else if (previousMySeat != null && effectiveMySeat == null) {
      unawaited(_joinAgora(publish: false));
    }
  }

  @override
  void dispose() {
    unawaited(AgoraRoomBridge.leave());
    _miniOverlayEntry?.remove();
    _miniOverlayEntry = null;
    _roomGiftOverlayTimer?.cancel();
    _roomCounterTicker?.cancel();
    _pkTicker?.cancel();
    _pkStartCountdownTimer?.cancel();
    unawaited(_giftAudioPlayer.dispose());
    _refreshTimer?.cancel();
    _volumeTimer?.cancel();
    for (final timer in _hideTimers.values) {
      timer.cancel();
    }
    _hideTimers.clear();
    speaking.clear();
    _chatReconnectTimer?.cancel();
    _chatFallbackTimer?.cancel();
    _chatSubscription?.cancel();
    _chatChannel?.sink.close();
    unawaited(_seatSocket?.dispose());
    _seatStateStore.dispose();
    _seatMoveTimers.clear();
    _chatSocketConnected = false;
    if (_chatSessionActive) {
      _chatSessionActive = false;
      http.post(
        _chatSessionUri,
        headers: _headers,
        body: jsonEncode({'action': 'leave'}),
      ).timeout(const Duration(seconds: 4)).catchError((_) => http.Response('', 500));
    }
    _messageController.dispose();
    _roomChatFocusNode.dispose();
    _roomMessagesController.dispose();
    if (_mySeat != null) {
      // Best-effort release; the server-side lease also expires automatically.
      http.post(_seatsUri, headers: _headers, body: jsonEncode({'seatNumber': null}))
          .timeout(const Duration(seconds: 4)).catchError((_) => http.Response('', 500));
    }
    super.dispose();
  }

  Future<void> _refreshSeats() async {
    if (_roomId.isEmpty || widget.accessToken.isEmpty) {
      if (mounted) setState(() { _isLoading = false; _loadError = 'بيانات الغرفة أو جلسة الدخول غير مكتملة'; });
      return;
    }
    if (_isRefreshing) {
      _refreshSeatsQueued = true;
      return;
    }
    _isRefreshing = true;
    try {
      final response = await http.get(_seatsUri, headers: _headers).timeout(const Duration(seconds: 8));
      final data = jsonDecode(response.body);
      if (response.statusCode == 403 && data is Map && data['error'] == 'room_kicked') {
        if (mounted) {
          _showMessage('تم طردك من الغرفة');
          await Future<void>.delayed(const Duration(milliseconds: 250));
          if (mounted) Navigator.of(context).maybePop();
        }
        return;
      }
      if (response.statusCode != 200 || data is! Map<String, dynamic> || data['ok'] != true) {
        if (mounted && _isLoading) setState(() { _isLoading = false; _loadError = response.statusCode == 401 ? 'انتهت جلسة الدخول، سجّل الدخول مجددًا' : 'تعذر تحميل مقاعد الغرفة'; });
        return;
      }
      _applySeatData(data);
    } catch (_) {
      if (!mounted) return;
      if (_isLoading) setState(() { _isLoading = false; _loadError = 'تعذر الاتصال بالغرفة، تحقق من الإنترنت'; });
    } finally {
      _isRefreshing = false;
      if (_refreshSeatsQueued && mounted) {
        _refreshSeatsQueued = false;
        scheduleMicrotask(() => _refreshSeats());
      }
    }
  }

  String get _roomCacheKey => '$_roomId:${widget.accessToken}';

  void _restoreRoomPreviewCache() {
    final cached = _roomPreviewCache[_roomCacheKey];
    if (cached == null) return;
    final savedAt = cached['savedAt'];
    if (savedAt is! DateTime || DateTime.now().difference(savedAt) > _roomPreviewCacheTtl) {
      _roomPreviewCache.remove(_roomCacheKey);
      return;
    }
    final cachedSeats = cached['seats'];
    final cachedAudience = cached['audienceUsers'];
    _seats = cachedSeats is List
        ? cachedSeats.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
        : <Map<String, dynamic>>[];
    _audienceUsers = cachedAudience is List
        ? cachedAudience.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
        : <Map<String, dynamic>>[];
    final mySeatEntries = _seats.where((seat) => seat['isMe'] == true).toList();
    _mySeat = mySeatEntries.isEmpty || mySeatEntries.first['seatNumber'] is! num
        ? null
        : (mySeatEntries.first['seatNumber'] as num).toInt();
    if (mySeatEntries.isNotEmpty) {
      final mine = mySeatEntries.first;
      _seatStateStore.setCurrentUser(
        userId: (mine['userId'] ?? '').toString(),
        name: (mine['name'] ?? 'مستخدم').toString(),
        userCode: (mine['userCode'] ?? '').toString(),
        avatarUrl: (mine['avatarUrl'] ?? mine['avatar'] ?? '').toString(),
        countryName: (mine['countryName'] ?? mine['country_name'] ?? '').toString(),
      );
    }
    _seatStateStore.applySnapshot(_seats, mySeat: _mySeat);
    _audienceCount = cached['audienceCount'] is num ? (cached['audienceCount'] as num).toInt() : 0;
    _ownerName = (cached['ownerName'] ?? _ownerName).toString();
    _ownerId = (cached['ownerId'] ?? _ownerId).toString();
    _roomAnnouncement = (cached['announcement'] ?? _roomAnnouncement).toString();
    // Keep the entry loader visible until the authenticated room response arrives.
    // Cached seat data may render underneath, but it does not count as a fresh DB response.
  }

  void _rememberRoomPreview(
    List<Map<String, dynamic>> seats,
    List<Map<String, dynamic>> audienceUsers,
    int audienceCount,
    String ownerName,
    String ownerId,
    String announcement,
  ) {
    _roomPreviewCache[_roomCacheKey] = <String, dynamic>{
      'savedAt': DateTime.now(),
      'seats': seats.map((seat) => Map<String, dynamic>.from(seat)).toList(),
      'audienceUsers': audienceUsers.map((user) => Map<String, dynamic>.from(user)).toList(),
      'audienceCount': audienceCount,
      'ownerName': ownerName,
      'ownerId': ownerId,
      'announcement': announcement,
    };
  }

  void _applySeatData(Map<String, dynamic> data) {
    if (!mounted) return;
    final rawSeats = data['seats'];
    final seats = rawSeats is List
        ? rawSeats.whereType<Map>().map((item) {
            final seat = Map<String, dynamic>.from(item);
            final userId = (seat['userId'] ?? '').toString();
            if ((seat['countryName'] ?? '').toString().trim().isEmpty &&
                (_countryNameCache[userId] ?? '').isNotEmpty) {
              seat['countryName'] = _countryNameCache[userId];
            }
            return seat;
          }).toList()
        : <Map<String, dynamic>>[];
    _rememberCountryNames(seats);
    final nextMySeat = data['mySeat'] is num ? (data['mySeat'] as num).toInt() : null;
    final hasPendingSeatMove = _seatStateStore.hasPendingMoves;
    final effectiveMySeat = hasPendingSeatMove ? _seatStateStore.mySeat : nextMySeat;
    final nextAudienceCount = data['audienceCount'] is num ? (data['audienceCount'] as num).toInt() : _audienceCount;
    final rawAudienceUsers = data['audienceUsers'];
    final nextAudienceUsers = rawAudienceUsers is List
        ? rawAudienceUsers.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
        : _audienceUsers;
    final owner = data['owner'];
    final nextOwnerName = owner is Map && owner['name'] != null
        ? owner['name'].toString()
        : _ownerName;
    final nextOwnerId = owner is Map
        ? (owner['id'] ?? owner['userId'] ?? owner['uid'] ?? '').toString()
        : _ownerId;
    final nextOwnerAvatarUrl = owner is Map && (owner['avatarUrl'] ?? '').toString().trim().isNotEmpty
        ? owner['avatarUrl'].toString().trim()
        : _ownerAvatarUrl;
    final nextOwnerCountryName = owner is Map && (owner['countryName'] ?? '').toString().trim().isNotEmpty
        ? owner['countryName'].toString().trim()
        : _ownerCountryName;
    final roomData = data['room'];
    final nextRoomLevel = roomData is Map && roomData['level'] is num
        ? (roomData['level'] as num).toInt().clamp(1, 5).toInt()
        : _roomLevel;
    final nextExperienceLevel = roomData is Map && roomData['experienceLevel'] is num
        ? (roomData['experienceLevel'] as num).toInt().clamp(1, 2147483647).toInt()
        : _roomExperienceLevel;
    final nextExperienceExp = roomData is Map && roomData['experienceExp'] is num
        ? (roomData['experienceExp'] as num).toInt().clamp(0, 2147483647).toInt()
        : _roomExperienceExp;
    final nextExperienceTarget = roomData is Map && roomData['experienceNextLevelExp'] is num
        ? (roomData['experienceNextLevelExp'] as num).toInt().clamp(1, 2147483647).toInt()
        : _roomExperienceNextLevelExp;
    final nextDailyExperience = roomData is Map && roomData['dailyExperienceExp'] is num
        ? (roomData['dailyExperienceExp'] as num).toInt().clamp(0, 3000000).toInt()
        : _roomDailyExperienceExp;
    final nextAnnouncement = roomData is Map && roomData['announcement'] != null
        ? roomData['announcement'].toString()
        : _roomAnnouncement;
    final nextMicCount = roomData is Map && roomData['micCount'] is num
        ? (roomData['micCount'] as num).toInt().clamp(2, 24).toInt()
        : _micCount;
    final nextMicLayoutId = roomData is Map && roomData['micLayoutId'] != null
        ? roomData['micLayoutId'].toString().trim()
        : _micLayoutId;
    final nextIsOwner = data['isOwner'] == true;
    final nextIsModerator = data['isModerator'] == true;
    final meData = data['me'];
    if (meData is Map) {
      _seatStateStore.setCurrentUser(
        userId: (meData['id'] ?? '').toString(),
        name: (meData['name'] ?? 'مستخدم').toString(),
        userCode: (meData['userCode'] ?? '').toString(),
        avatarUrl: (meData['avatarUrl'] ?? '').toString(),
        countryName: (meData['countryName'] ?? meData['country_name'] ?? '').toString(),
      );
    }
    if (!_seatStateStore.hasPendingMoves) {
      _seatStateStore.applySnapshot(seats, mySeat: nextMySeat);
    }
    final nextSelfMuted = meData is Map && meData['isMuted'] == true;
    final nextIsBanned = meData is Map && meData['isBanned'] == true;
    final nextVoiceEnabled = data['voiceEnabled'] != false;
    _rememberRoomPreview(seats, nextAudienceUsers, nextAudienceCount, nextOwnerName, nextOwnerId, nextAnnouncement);
    final voiceJustDisabled = _voiceEnabled && !nextVoiceEnabled;
    final voiceJustEnabled = !_voiceEnabled && nextVoiceEnabled;
    final lostMySeat = _mySeat != null && effectiveMySeat == null;
    final gainedMySeat = _mySeat == null && effectiveMySeat != null;
    final newlyMuted = !_selfMicMuted && nextSelfMuted;
    final newlyBanned = !_isBannedFromRoom && nextIsBanned;
    final changed = jsonEncode(_seats) != jsonEncode(seats) ||
        _mySeat != effectiveMySeat ||
        _audienceCount != nextAudienceCount ||
        jsonEncode(_audienceUsers) != jsonEncode(nextAudienceUsers) ||
        _ownerName != nextOwnerName ||
        _ownerId != nextOwnerId ||
        _ownerAvatarUrl != nextOwnerAvatarUrl ||
        _ownerCountryName != nextOwnerCountryName ||
        _roomAnnouncement != nextAnnouncement ||
        _micCount != nextMicCount ||
        _micLayoutId != nextMicLayoutId ||
        _roomLevel != nextRoomLevel ||
        _roomExperienceLevel != nextExperienceLevel ||
        _roomExperienceExp != nextExperienceExp ||
        _roomExperienceNextLevelExp != nextExperienceTarget ||
        _roomDailyExperienceExp != nextDailyExperience ||
        _amRoomOwner != nextIsOwner ||
        _amRoomModerator != nextIsModerator ||
        _selfMicMuted != nextSelfMuted ||
        _isBannedFromRoom != nextIsBanned ||
        _voiceEnabled != nextVoiceEnabled ||
        _isLoading ||
        _loadError != null;
    if (!mounted) return;
    if (!changed) {
      if (!nextVoiceEnabled) {
        _agoraDesiredPublish = null;
        _agoraJoinedPublish = null;
        unawaited(AgoraRoomBridge.leave());
      }
      return;
    }
    setState(() {
      _seats = seats;
      _mySeat = effectiveMySeat;
      _audienceCount = nextAudienceCount;
      _audienceUsers = nextAudienceUsers;
      _ownerName = nextOwnerName;
      _ownerId = nextOwnerId;
      _ownerAvatarUrl = nextOwnerAvatarUrl;
      _ownerCountryName = nextOwnerCountryName;
      _roomAnnouncement = nextAnnouncement;
      _micCount = nextMicCount;
      _micLayoutId = nextMicLayoutId;
      _roomLevel = nextRoomLevel;
      _roomExperienceLevel = nextExperienceLevel;
      _roomExperienceExp = nextExperienceExp;
      _roomExperienceNextLevelExp = nextExperienceTarget;
      _roomDailyExperienceExp = nextDailyExperience;
      _amRoomOwner = nextIsOwner;
      _amRoomModerator = nextIsModerator;
      _selfMicMuted = nextSelfMuted;
      _isBannedFromRoom = nextIsBanned;
      _voiceEnabled = nextVoiceEnabled;
      _isLoading = false;
      _roomDataReady = true;
      _loadError = null;
    });
    if (!nextVoiceEnabled) {
      for (final timer in _hideTimers.values) {
        timer.cancel();
      }
      _hideTimers.clear();
      speaking.clear();
      _agoraDesiredPublish = null;
      _agoraJoinedPublish = null;
      unawaited(AgoraRoomBridge.leave());
      if (voiceJustDisabled) _showMessage('تم إيقاف الصوت في التطبيق من الإدارة');
      return;
    }
    if (voiceJustEnabled) {
      unawaited(_joinAgora(publish: false));
    } else if (lostMySeat || newlyMuted || newlyBanned) {
      if (newlyMuted) unawaited(AgoraRoomBridge.setMuted(true));
      unawaited(_joinAgora(publish: false));
    } else if ((gainedMySeat || (effectiveMySeat != null && _agoraJoinedPublish == false)) &&
        !nextSelfMuted && !nextIsBanned) {
      unawaited(_joinAgora(publish: true));
    }
  }

  Future<void> _refreshAudioLevels() async {
    if (!mounted || !_voiceEnabled) return;
    try {
      final raw = await AgoraRoomBridge.getVolumeLevels();
      final next = <int, double>{};
      final now = DateTime.now();

      raw.forEach((uid, level) {
        if (level >= 0.0002) {
          next[uid] = level.clamp(0.0, 1.0).toDouble();
          _speakerLastHeardAt[uid] = now;

          // Every detected sound keeps the wave active and restarts its
          // 400ms hide timer, measured from the most recent sound sample.
          final wasSpeaking = speaking.add(uid);
          _hideTimers[uid]?.cancel();
          _hideTimers[uid] = Timer(const Duration(milliseconds: 400), () {
            _hideTimers.remove(uid);
            if (mounted) setState(() => speaking.remove(uid));
          });
          if (wasSpeaking && mounted) {
            setState(() {});
          }
        }
      });

      // Keep the existing speaker-level grace period unchanged for the
      // room's other voice UI; it does not control the circular wave.
      _speakerLastHeardAt.removeWhere(
        (uid, heardAt) =>
            now.difference(heardAt) > const Duration(milliseconds: 7000),
      );
      for (final entry in _speakerLastHeardAt.entries) {
        if (!next.containsKey(entry.key)) {
          next[entry.key] = _speakerLevels[entry.key] ?? 0.003;
        }
      }

      var changed = next.length != _speakerLevels.length;
      if (!changed) {
        for (final entry in next.entries) {
          if (((_speakerLevels[entry.key] ?? 0) - entry.value).abs() > 0.06) {
            changed = true;
            break;
          }
        }
      }
      if (changed && mounted) setState(() => _speakerLevels = next);
    } catch (_) {
      // Meter updates must never interrupt room audio.
    }
  }

  Future<void> _joinAgora({required bool publish}) async {
    if (!_voiceEnabled || _roomId.isEmpty || widget.accessToken.isEmpty) return;
    _agoraDesiredPublish = publish;
    if (_agoraSyncInProgress) return;

    _agoraSyncInProgress = true;
    try {
      while (mounted && _agoraDesiredPublish != null) {
        final targetPublish = _agoraDesiredPublish!;
        _agoraDesiredPublish = null;

        // Join Agora once as broadcaster. Seat changes only renew the token
        // and toggle the microphone track; the channel is never left/rejoined.
        if (_agoraJoinedPublish == null) {
          final response = await http.post(
            Uri.parse('$_apiBase/rooms/${Uri.encodeComponent(_roomId)}/agora-token'),
            headers: _headers,
            body: jsonEncode({'publish': false}),
          ).timeout(const Duration(seconds: 25));
          final data = jsonDecode(response.body);
          if (!mounted) return;
          if (!_voiceEnabled) return;
          if (response.statusCode != 200 || data is! Map || data['ok'] != true) {
            if (mounted) {
              final message = data is Map ? (data['message'] ?? '').toString() : '';
              _showMessage(message.isNotEmpty ? message : 'تعذر الاتصال بخدمة الصوت');
            }
            continue;
          }
          await AgoraRoomBridge.join(
            appId: (data['appId'] ?? '').toString(),
            channel: (data['channel'] ?? '').toString(),
            token: (data['token'] ?? '').toString(),
            uid: (data['uid'] as num).toInt(),
            publish: false,
          );
          if (!mounted) return;
          _agoraJoinedPublish = false;
        }

        if (_agoraDesiredPublish != null && _agoraDesiredPublish != targetPublish) {
          continue;
        }
        if (_agoraJoinedPublish == targetPublish) continue;

        if (targetPublish) {
          final response = await http.post(
            Uri.parse('$_apiBase/rooms/${Uri.encodeComponent(_roomId)}/agora-token'),
            headers: _headers,
            body: jsonEncode({'publish': true}),
          ).timeout(const Duration(seconds: 8));
          final data = jsonDecode(response.body);
          if (!mounted) return;
          if (response.statusCode != 200 || data is! Map || data['ok'] != true || data['canPublish'] != true) {
            if (mounted && _mySeat != null && !_selfMicMuted) _showMessage('تعذر تفعيل المايك، تحقق من صلاحية المقعد');
            continue;
          }
          await AgoraRoomBridge.setPublishing(true, token: (data['token'] ?? '').toString());
        } else {
          final response = await http.post(
            Uri.parse('$_apiBase/rooms/${Uri.encodeComponent(_roomId)}/agora-token'),
            headers: _headers,
            body: jsonEncode({'publish': false}),
          ).timeout(const Duration(seconds: 8));
          final data = jsonDecode(response.body);
          if (response.statusCode == 200 && data is Map && data['ok'] == true) {
            await AgoraRoomBridge.setPublishing(false, token: (data['token'] ?? '').toString());
          } else {
            await AgoraRoomBridge.setPublishing(false);
          }
        }
        if (!mounted) return;
        _agoraJoinedPublish = targetPublish;
      }
    } catch (_) {
      if (_agoraJoinedPublish == null) {
        _agoraJoinedPublish = null;
      } else {
        _agoraJoinedPublish = false;
      }
      if (mounted && _mySeat != null && !_selfMicMuted && !_isBannedFromRoom) {
        _showMessage('تعذر تحديث المايك دون قطع اتصال الغرفة');
      }
    } finally {
      _agoraSyncInProgress = false;
      if (mounted && _agoraDesiredPublish != null) {
        unawaited(_joinAgora(publish: _agoraDesiredPublish!));
      }
    }
  }

  Future<bool> _toggleSelfMic() async {
    final previousMuted = _selfMicMuted;
    final targetMuted = !previousMuted;
    // Mute is applied to the local audio track immediately; server sync follows.
    if (targetMuted) {
      if (mounted) setState(() => _selfMicMuted = true);
      unawaited(AgoraRoomBridge.setMuted(true));
    }
    try {
      final response = await http.post(
        _moderationUri,
        headers: _headers,
        body: jsonEncode({'action': 'self_mic_toggle'}),
      ).timeout(const Duration(seconds: 8));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map && data['ok'] == true) {
        final confirmedMuted = data['isMuted'] == true;
        if (mounted) setState(() => _selfMicMuted = confirmedMuted);
        if (confirmedMuted) {
          unawaited(AgoraRoomBridge.setMuted(true));
          unawaited(_joinAgora(publish: false));
        } else {
          await _joinAgora(publish: true);
        }
        _showMessage(confirmedMuted ? 'تم كتم مايكك' : 'تم فتح مايكك');
        unawaited(_refreshSeats());
        return true;
      }
      if (mounted) setState(() => _selfMicMuted = previousMuted);
      if (targetMuted) unawaited(AgoraRoomBridge.setMuted(false));
      final message = data is Map ? (data['message'] ?? '').toString() : '';
      _showMessage(message.isNotEmpty ? message : 'تعذر تغيير حالة المايك');
    } catch (_) {
      if (mounted) setState(() => _selfMicMuted = previousMuted);
      if (targetMuted) unawaited(AgoraRoomBridge.setMuted(false));
      _showMessage('تعذر الاتصال بالخادم، لم تتغير حالة المايك');
    }
    return false;
  }

  Future<bool> _moderateRoomUser(String targetUserId, String action) async {
    if (!_isRoomOwner && !_amRoomModerator) {
      _showMessage('هذه الصلاحية لمالك الغرفة ومشرفيها فقط');
      return false;
    }
    if (targetUserId.isEmpty) {
      _showMessage('تعذر تحديد المستخدم');
      return false;
    }
    try {
      final response = await http.post(
        _moderationUri,
        headers: _headers,
        body: jsonEncode({'action': action, 'targetUserId': targetUserId}),
      ).timeout(const Duration(seconds: 8));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map && data['ok'] == true) {
        final labels = {
          'toggle_mute': 'تم تحديث كتم المستخدم',
          'kick': 'تم طرد المستخدم من الغرفة',
          'ban': 'تم حظر المستخدم من الغرفة',
          'lower': 'تم إنزال المستخدم من المايك',
        };
        _showMessage(labels[action] ?? 'تم تنفيذ الإجراء');
        await _refreshSeats();
        return true;
      }
      final message = data is Map ? (data['message'] ?? '').toString() : '';
      _showMessage(message.isNotEmpty ? message : response.statusCode == 403
          ? 'ليست لديك صلاحية لتنفيذ هذا الإجراء'
          : 'تعذر تنفيذ الإجراء، حاول مرة أخرى');
    } catch (_) {
      _showMessage('تعذر الاتصال بالخادم، لم يتم تنفيذ الإجراء');
    }
    return false;
  }

  Future<bool> _moderateRoomSeat(int seatNumber, String action) async {
    if (!_isRoomOwner && !_amRoomModerator) {
      _showMessage('هذه الصلاحية لمالك الغرفة ومشرفيها فقط');
      return false;
    }
    if (seatNumber < 1 || seatNumber > _micCount) {
      _showMessage('رقم المايك غير صحيح');
      return false;
    }
    final isLockAction = action == 'toggle_seat_lock';
    // A second tap while the first write is in flight must not invert the
    // requested state again or race a second HTTP write against it.
    if (isLockAction && !_pendingSeatLockRequests.add(seatNumber)) return true;
    final originalSeats = _seats.map((seat) => Map<String, dynamic>.from(seat)).toList();
    final optimisticSeats = originalSeats.map((seat) => Map<String, dynamic>.from(seat)).toList();
    final targetIndex = optimisticSeats.indexWhere((seat) => (seat['seatNumber'] as num?)?.toInt() == seatNumber);
    final currentSeat = targetIndex >= 0 ? optimisticSeats[targetIndex] : <String, dynamic>{};
    final wasLocked = currentSeat['isLocked'] == true || currentSeat['locked'] == true;
    final wasMuted = currentSeat['isMuted'] == true || currentSeat['muted'] == true;
    final optimisticLocked = action == 'toggle_seat_lock' ? !wasLocked : wasLocked;
    final requestAction = action == 'toggle_seat_lock' ? 'set_seat_lock' : action;
    final revision = (_seatModerationRevision[seatNumber] ?? 0) + 1;
    _seatModerationRevision[seatNumber] = revision;
    if (isLockAction) _pendingSeatLockValues[seatNumber] = optimisticLocked;
    final optimisticMuted = action == 'toggle_seat_mute' ? !wasMuted : wasMuted;

    // Update the visible seat state on this frame instead of waiting for HTTP + a second refresh.
    if (targetIndex >= 0) {
      optimisticSeats[targetIndex]['isLocked'] = optimisticLocked;
      optimisticSeats[targetIndex]['locked'] = optimisticLocked;
      optimisticSeats[targetIndex]['isMuted'] = optimisticMuted;
      optimisticSeats[targetIndex]['muted'] = optimisticMuted;
      _applyRealtimeSeatSnapshot(optimisticSeats, mySeat: _mySeat);
    }

    try {
      final response = await http.post(
        _moderationUri,
        headers: _headers,
        body: jsonEncode({'action': requestAction, 'seatNumber': seatNumber, if (requestAction == 'set_seat_lock') 'isLocked': optimisticLocked}),
      ).timeout(const Duration(seconds: 8));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map && data['ok'] == true) {
        if (_seatModerationRevision[seatNumber] != revision) return true;
        final confirmedLocked = data['isLocked'] == true;
        final confirmedMuted = data['isMuted'] == true;
        if (isLockAction) _pendingSeatLockValues[seatNumber] = confirmedLocked;
        final confirmedSeats = _seats.map((seat) => Map<String, dynamic>.from(seat)).toList();
        final confirmedIndex = confirmedSeats.indexWhere((seat) => (seat['seatNumber'] as num?)?.toInt() == seatNumber);
        if (confirmedIndex >= 0) {
          confirmedSeats[confirmedIndex]['isLocked'] = confirmedLocked;
          confirmedSeats[confirmedIndex]['locked'] = confirmedLocked;
          confirmedSeats[confirmedIndex]['isMuted'] = confirmedMuted;
          confirmedSeats[confirmedIndex]['muted'] = confirmedMuted;
          _applyRealtimeSeatSnapshot(confirmedSeats, mySeat: _mySeat);
        }
        _showMessage(action == 'toggle_seat_lock'
            ? (confirmedLocked ? 'تم قفل المايك' : 'تم فتح المايك')
            : (confirmedMuted ? 'تم كتم المايك' : 'تم فتح كتم المايك'));
        return true;
      }
      if (_seatModerationRevision[seatNumber] == revision) {
        if (isLockAction) _pendingSeatLockValues.remove(seatNumber);
        _applyRealtimeSeatSnapshot(originalSeats, mySeat: _mySeat);
        unawaited(_refreshSeats());
      }
      final message = data is Map ? (data['message'] ?? '').toString() : '';
      _showMessage(message.isNotEmpty ? message : response.statusCode == 403
          ? 'ليست لديك صلاحية للتحكم بهذا المايك'
          : 'تعذر تحديث المايك، حاول مرة أخرى');
    } catch (_) {
      // Ignore stale failures from an older tap; a newer microphone action
      // may already have updated the visible state.
      if (_seatModerationRevision[seatNumber] == revision) {
        if (isLockAction) _pendingSeatLockValues.remove(seatNumber);
        _applyRealtimeSeatSnapshot(originalSeats, mySeat: _mySeat);
        unawaited(_refreshSeats());
        _showMessage('تعذر الاتصال بالخادم، لم تتغير حالة المايك');
      }
    } finally {
      if (isLockAction) {
        _pendingSeatLockRequests.remove(seatNumber);
        _pendingSeatLockValues.remove(seatNumber);
      }
    }
    return false;
  }

  Future<void> _sendHeartbeat() async {
    if (DateTime.now().difference(_lastHeartbeat) < const Duration(seconds: 15)) return;
    _lastHeartbeat = DateTime.now();
    try {
      await http.post(_seatsUri, headers: _headers, body: jsonEncode({'heartbeat': true}))
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  bool get _isRoomOwner => _amRoomOwner;

  void _scrollChatToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_roomMessagesController.hasClients) return;
      final target = _roomMessagesController.position.maxScrollExtent;
      if (animated) {
        _roomMessagesController.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOutQuart);
      } else {
        _roomMessagesController.jumpTo(target);
      }
    });
  }

  void _appendLocalMessage(Message message) => _mergeRoomMessages([message]);

  void _mergeRoomMessages(Iterable<Message> incoming) {
    if (!mounted) return;

    // Keep the reader's position when they are browsing older chat messages.
    // Only follow new messages automatically when the list was already near its bottom.
    final shouldFollowLatest = _messages.isNotEmpty &&
        (!_roomMessagesController.hasClients ||
            (_roomMessagesController.position.maxScrollExtent -
                    _roomMessagesController.position.pixels) <=
                96);

    final ordered = incoming.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    var insertedAny = false;
    for (final message in ordered) {
      if (message.id.isEmpty || !_messageIds.add(message.id)) continue;
      _messages.add(message);
      insertedAny = true;
      final listState = _roomAnimatedListKey.currentState;
      if (listState != null) {
        listState.insertItem(_messages.length, duration: const Duration(milliseconds: 400));
      } else {
        setState(() {});
      }
    }
    if (insertedAny && shouldFollowLatest) {
      _scrollChatToBottom();
    }
  }

  Message _messageFromApi(Map<String, dynamic> item, {String type = 'text'}) {
    final messageText = (item['message'] ?? item['text'] ?? '').toString();
    final resolvedType = type == 'text' && messageText == 'انضم للغرفة'
        ? 'system'
        : type;
    return Message(
      id: (item['id'] ?? '').toString(),
      type: resolvedType,
      senderId: (item['userId'] ?? item['senderId'] ?? item['user_id'] ?? item['sender_id'] ?? '').toString(),
      senderName: (item['name'] ?? item['senderName'] ?? item['displayName'] ?? 'مستخدم').toString(),
      senderAvatar: (item['senderAvatar'] ?? item['senderAvatarUrl'] ?? item['avatarUrl'] ?? item['avatar'] ?? item['photoUrl'] ?? item['photo_url'] ?? '').toString(),
      text: messageText,
      createdAt: DateTime.tryParse((item['createdAt'] ?? '').toString()) ?? DateTime.now(),
    );
  }

  void _handleRoomChatEvent(dynamic rawEvent) {
    try {
      final decoded = jsonDecode(rawEvent.toString());
      if (decoded is! Map) return;
      final eventType = (decoded['type'] ?? 'message').toString();
      if (eventType == 'clear_chat') {
        _clearRoomChatLocally();
        return;
      }
      final rawMessage = decoded['message'];
      if (rawMessage is! Map) return;
      final item = Map<String, dynamic>.from(rawMessage);
      final type = eventType == 'system'
          ? 'system'
          : eventType == 'announcement'
              ? 'announcement'
              : 'text';
      _appendLocalMessage(_messageFromApi(item, type: type));

    } catch (_) {
      // Ignore malformed or unrelated stream frames without interrupting the chat.
    }
  }

  Future<String?> _askRoomEntryPassword() async {
    final controller = TextEditingController();
    var invalid = false;
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (context, setDialogState) => Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('الغرفة مقفلة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF222222))),
                    const SizedBox(height: 8),
                    const Text('أدخل كلمة المرور المكوّنة من 6 أرقام للدخول', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF777777))),
                    const SizedBox(height: 18),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(fontSize: 22, letterSpacing: 12, color: Color(0xFF222222)),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '••••••',
                        errorText: invalid ? 'كلمة المرور غير صحيحة' : null,
                        filled: true,
                        fillColor: const Color(0xFFF7F7F7),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (_) => setDialogState(() => invalid = false),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('إلغاء', style: TextStyle(color: Color(0xFF999999))),
                        )),
                        Expanded(child: ElevatedButton(
                          onPressed: () {
                            if (!RegExp(r'^[0-9]{6}$').hasMatch(controller.text)) {
                              setDialogState(() => invalid = true);
                              return;
                            }
                            Navigator.of(dialogContext).pop(controller.text);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD6B65F),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                          ),
                          child: const Text('دخول'),
                        )),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _startRoomChat() async {
    if (_chatStarting || _chatSessionActive || _roomId.isEmpty || widget.accessToken.isEmpty) return;
    _chatStarting = true;
    try {
      http.Response response;
      dynamic data;
      response = await http.post(
        _chatSessionUri,
        headers: _headers,
        body: jsonEncode({'action': 'join'}),
      ).timeout(const Duration(seconds: 10));
      data = jsonDecode(response.body);

      if (response.statusCode == 423 &&
          data is Map &&
          data['error'] == 'room_password_required' &&
          mounted) {
        var joined = false;
        for (var attempt = 0; attempt < 3; attempt++) {
          final password = await _askRoomEntryPassword();
          if (password == null || !mounted) {
            if (mounted) Navigator.of(context).maybePop();
            return;
          }
          response = await http.post(
            _chatSessionUri,
            headers: _headers,
            body: jsonEncode({'action': 'join', 'password': password}),
          ).timeout(const Duration(seconds: 10));
          data = jsonDecode(response.body);
          if (response.statusCode == 200 && data is Map && data['ok'] == true) {
            joined = true;
            break;
          }
          if (data is Map && data['error'] == 'room_password_incorrect') {
            _showMessage('كلمة المرور غير صحيحة، حاول مرة أخرى');
            continue;
          }
          break;
        }
        if (!joined) {
          if (mounted && (response.statusCode != 423)) {
            final error = data is Map ? (data['message'] ?? data['error'] ?? '').toString() : '';
            _showMessage(error.isNotEmpty ? error : 'تعذر الدخول إلى الغرفة');
          }
          return;
        }
      }

      if (response.statusCode != 200 || data is! Map || data['ok'] != true) {
        if (mounted) {
          final error = data is Map ? (data['message'] ?? data['error'] ?? '').toString() : '';
          _showMessage(error.isNotEmpty ? error : 'تعذر الاتصال بدردشة الغرفة');
        }
        return;
      }
      if (!mounted) {
        http.post(_chatSessionUri, headers: _headers, body: jsonEncode({'action': 'leave'}))
            .timeout(const Duration(seconds: 4)).catchError((_) => http.Response('', 500));
        return;
      }
      _chatSessionActive = true;
      // Fetch chat history and establish the live stream concurrently.
      // A slow WebSocket handshake must not delay the first visible messages.
      unawaited(_refreshSeats());
      unawaited(_loadRoomMessages());
      unawaited(_connectRoomChatSocket());
      _startChatFallbackPolling();
    } catch (_) {
      if (mounted) _showMessage('تعذر الاتصال بدردشة الغرفة، جارٍ إعادة المحاولة');
      if (_chatSessionActive) {
        _scheduleChatReconnect();
        _startChatFallbackPolling();
      }
    } finally {
      _chatStarting = false;
    }
  }

  Future<void> _connectRoomChatSocket() async {
    if (!_chatSessionActive || _chatConnecting || !mounted) return;
    _chatConnecting = true;
    WebSocketChannel? channel;
    try {
      final connectedChannel = WebSocketChannel.connect(
        _chatStreamUri,
        protocols: ['happy-live-chat', widget.accessToken],
      );
      channel = connectedChannel;
      _chatChannel = connectedChannel;
      _chatSubscription = connectedChannel.stream.listen(
        _handleRoomChatEvent,
        onError: (_) => _handleChatSocketClosed(connectedChannel),
        onDone: () => _handleChatSocketClosed(connectedChannel),
        cancelOnError: true,
      );
      await connectedChannel.ready.timeout(const Duration(seconds: 8));
      if (!mounted || !identical(_chatChannel, connectedChannel)) return;
      _chatSocketConnected = true;
      _chatReconnectAttempts = 0;
      _chatReconnectTimer?.cancel();
      _chatReconnectTimer = null;
      _chatFallbackTimer?.cancel();
      _chatFallbackTimer = null;
      // Reconcile history after every initial connection or reconnect so messages
      // sent while this client was offline are not missed.
      unawaited(_loadRoomMessages());
    } catch (_) {
      if (channel != null && identical(_chatChannel, channel)) {
        _chatChannel = null;
        _chatSocketConnected = false;
        _chatSubscription?.cancel();
        _chatSubscription = null;
        channel.sink.close();
      }
      if (_chatSessionActive && mounted) {
        _scheduleChatReconnect();
        _startChatFallbackPolling();
      }
    } finally {
      _chatConnecting = false;
    }
  }

  void _handleChatSocketClosed(WebSocketChannel channel) {
    if (!identical(_chatChannel, channel)) return;
    _chatChannel = null;
    _chatSocketConnected = false;
    _chatSubscription?.cancel();
    _chatSubscription = null;
    if (_chatSessionActive && mounted) {
      _scheduleChatReconnect();
      _startChatFallbackPolling();
    }
  }

  void _scheduleChatReconnect() {
    if (!_chatSessionActive || !mounted || (_chatReconnectTimer?.isActive ?? false)) return;
    const delays = [1, 2, 4, 8, 16, 30];
    final index = _chatReconnectAttempts < delays.length ? _chatReconnectAttempts : delays.length - 1;
    final delay = delays[index];
    _chatReconnectAttempts++;
    _chatReconnectTimer = Timer(Duration(seconds: delay), () {
      _chatReconnectTimer = null;
      _connectRoomChatSocket();
    });
  }

  void _startChatFallbackPolling() {
    if (!_chatSessionActive || (_chatFallbackTimer?.isActive ?? false)) return;
    _chatFallbackTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_chatSessionActive && !_chatSocketConnected) _loadRoomMessages();
    });
  }

  Future<void> _loadRoomMessages() async {
    if (!_chatSessionActive || _chatHistoryLoading) return;
    _chatHistoryLoading = true;
    try {
      final response = await http.get(_messagesUri, headers: _headers)
          .timeout(const Duration(seconds: 8));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data is! Map || data['ok'] != true) return;
      final rawMessages = data['messages'];
      if (rawMessages is! List) return;
      final messages = rawMessages
          .whereType<Map>()
          .map((item) => _messageFromApi(Map<String, dynamic>.from(item)))
          .where((message) => message.id.isNotEmpty)
          .toList();
      _mergeRoomMessages(messages);
    } catch (_) {
      // Keep the current conversation visible; the next fallback poll retries.
    } finally {
      _chatHistoryLoading = false;
    }
  }

  Future<void> _sendRoomMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _chatSending) return;
    if (text.length > 100) {
      _showMessage('الرسالة يجب ألا تتجاوز 100 حرف');
      return;
    }

    // Wait for the room chat session instead of silently dropping the first tap
    // while the room is still connecting.
    if (!_chatSessionActive) {
      if (_chatStarting) {
        final waitUntil = DateTime.now().add(const Duration(seconds: 12));
        while (_chatStarting && !_chatSessionActive && DateTime.now().isBefore(waitUntil)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      } else {
        await _startRoomChat();
      }
      if (!_chatSessionActive) {
        if (mounted) _showMessage('تعذر الاتصال بالدردشة، حاول الإرسال مرة أخرى');
        return;
      }
    }

    final now = DateTime.now();
    if (now.difference(_lastLocalMessageAt).inMilliseconds < 1000) {
      _showMessage('انتظر ثانية قبل إرسال رسالة أخرى');
      return;
    }

    _chatSending = true;
    try {
      final response = await http.post(
        _messagesUri,
        headers: _headers,
        body: jsonEncode({'message': text}),
      ).timeout(const Duration(seconds: 12));
      final dynamic data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map && data['ok'] == true) {
        _lastLocalMessageAt = DateTime.now();
        final rawMessages = data['messages'];
        if (rawMessages is List && rawMessages.isNotEmpty) {
          _mergeRoomMessages(rawMessages
              .whereType<Map>()
              .map((item) => _messageFromApi(Map<String, dynamic>.from(item))));
        } else if (mounted) {
          _showMessage('تم الإرسال، لكن تعذر عرض الرسالة محلياً');
        }
        if (_messageController.text.trim() == text) {
          _messageController.clear();
        }      } else {        final serverMessage = data is Map            ? (data['message'] ?? data['error'] ?? '').toString()
            : '';
        if (mounted) {
          _showMessage(serverMessage.isNotEmpty
              ? serverMessage
              : response.statusCode == 401
                  ? 'انتهت جلسة الدخول، سجّل الدخول مجددًا'
                  : response.statusCode == 409
                      ? 'جلسة الدردشة غير نشطة، جارٍ إعادة الاتصال'
                      : 'تعذر إرسال الرسالة، حاول مرة أخرى');
        }
        if (response.statusCode == 409) unawaited(_startRoomChat());
      }
    } catch (error) {
      if (mounted) _showMessage('تعذر إرسال الرسالة، تحقق من الاتصال');
    } finally {
      _chatSending = false;
    }
  }

  Widget _chatAvatar(String avatar, String name, {double size = 34, VoidCallback? onTap}) {
    final avatarWidget = HappyNetworkAvatar(
      url: avatar,
      size: size,
      backgroundColor: const Color(0xFF46304F),
      fallback: Text(
        name.isEmpty ? '؟' : name.characters.first,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
    if (onTap == null) return avatarWidget;
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: avatarWidget),
      ),
    );
  }

  void _showChatUserProfile(Message message) {
    if (!mounted || message.senderId.trim().isEmpty) return;
    final matchingSeat = _seats.where((seat) =>
      (seat['userId'] ?? '').toString() == message.senderId).toList();
    final cachedUser = <String, dynamic>{
      if (matchingSeat.isNotEmpty) ...matchingSeat.first,
      'userId': message.senderId,
      'name': message.senderName,
      'displayName': message.senderName,
      'avatarUrl': message.senderAvatar,
      'avatar': message.senderAvatar,
      'isMe': matchingSeat.any((seat) => seat['isMe'] == true),
    };

    // Resolve the permanent profile by account UUID, not by the active audience
    // list. A user can leave the room and their old message remains tappable.
    final profileFuture = http.get(
      Uri.parse('$_apiBase/users/${Uri.encodeComponent(message.senderId)}/profile'),
      headers: _headers,
    ).timeout(const Duration(seconds: 12));

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(.55),
      isScrollControlled: true,
      useRootNavigator: true,
      enableDrag: true,
      builder: (sheetContext) => FutureBuilder<http.Response>(
        future: profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator(color: _gold)),
              ),
            );
          }
          var user = Map<String, dynamic>.from(cachedUser);
          final response = snapshot.data;
          if (response != null && response.statusCode == 200) {
            try {
              final decoded = jsonDecode(response.body);
              if (decoded is Map && decoded['ok'] == true && decoded['profile'] is Map) {
                final profile = Map<String, dynamic>.from(decoded['profile'] as Map);
                user.addAll(profile);
                user['userId'] = profile['userId'] ?? message.senderId;
                user['name'] = profile['name'] ?? message.senderName;
                user['displayName'] = user['name'];
                user['userCode'] = profile['userCode'] ?? '';
                user['avatarUrl'] = profile['avatarUrl'] ?? message.senderAvatar;
                user['countryName'] = profile['country'] ?? '';
                user['country_name'] = profile['country'] ?? '';
                user['isMe'] = profile['isMine'] == true;
              }
            } catch (_) {
              // Keep the message snapshot as a safe fallback if the response is malformed.
            }
          }
          final isMe = user['isMe'] == true;
          return UserInfoBottomSheet(
            user: user,
            isMe: isMe,
            canModerate: !isMe && (_isRoomOwner || _amRoomModerator) &&
                user['isRoomOwner'] != true && user['isRoomModerator'] != true,
            selfMicMuted: isMe ? _selfMicMuted : user['isMuted'] == true,
            onToggleSelfMic: _toggleSelfMic,
            onModerateUser: _moderateRoomUser,
          );
        },
      ),
    );
  }

  Widget _roomMessageItem(Message message) {
    final isSystem = message.type == 'system' || message.type == 'join' || message.type == 'announcement';
    final isWelcome = message.text.contains('دخل الغرفة') || message.text.contains('انضم') || message.text == 'انضم للغرفة';
    final isOwnerEntry = isWelcome && message.senderId.isNotEmpty && message.senderId == _ownerId;
    final displayText = isSystem && isWelcome
        ? isOwnerEntry
            ? 'مالك الغرفة @ ${message.senderName} دخل الغرفة'
            : '${message.senderName} دخل الغرفة'
        : isSystem && message.type != 'announcement'
            ? '${message.senderName} @ ${message.text}'
            : message.type == 'announcement'
                ? message.text
                : '${message.senderName}: ${message.text}';

    final hasSender = message.senderId.isNotEmpty;
    final senderLabel = isOwnerEntry
        ? 'مالك الغرفة @ ${message.senderName}'
        : message.senderName;

    final messageBubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: const Color(0xAA20182A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(.20), width: .8),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Text(
          isSystem && isWelcome
              ? 'دخل الغرفة'
              : isSystem && message.type != 'announcement'
                  ? message.text
                  : message.type == 'announcement'
                      ? displayText
                      : message.text,
          textAlign: TextAlign.right,
          softWrap: true,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: GestureDetector(
        onTap: message.type == 'announcement' && _isRoomOwner ? _editRoomAnnouncement : null,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(end: 50, bottom: 14),
          child: hasSender && message.type != 'announcement'
              ? Row(
                  mainAxisSize: MainAxisSize.max,
                  textDirection: TextDirection.rtl,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _chatAvatar(
                      message.senderAvatar,
                      message.senderName,
                      size: 30,
                      onTap: () => _showChatUserProfile(message),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Transform.translate(
                            offset: const Offset(0, -2),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _showChatUserProfile(message),
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: 2,
                                  top: 1,
                                  bottom: 4,
                                ),
                                child: Text(
                                  senderLabel,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    height: 1.2,
                                    fontWeight: FontWeight.w800,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.only(top: 2),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: messageBubble,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      textDirection: TextDirection.rtl,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0x5520182A),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withOpacity(.12)),
                          ),
                          child: Icon(
                            Icons.notifications_active_rounded,
                            size: 14,
                            color: Colors.white.withOpacity(0.82),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: 2),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: messageBubble,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _roomMessageAnimatedItem(Message message, Animation<double> animation, {bool removing = false}) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutQuart, reverseCurve: Curves.easeInCubic);
    return SizeTransition(
      sizeFactor: curved,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: removing ? const Offset(0, -0.16) : const Offset(0, 0.22),
            end: Offset.zero,
          ).animate(curved),
          child: _roomMessageItem(message),
        ),
      ),
    );
  }

  Widget _roomMessagesPanel() {
    return SizedBox.expand(
      child: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Scrollbar(
            controller: _roomMessagesController,
            thumbVisibility: true,
            interactive: true,
            child: AnimatedList(
              key: _roomAnimatedListKey,
              controller: _roomMessagesController,
              reverse: false,
              primary: false,
              shrinkWrap: false,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 0),
              initialItemCount: _messages.length + 1,
              itemBuilder: (context, index, animation) {
              if (index == 0) {
                return SizeTransition(
                  sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeOutQuart),
                  axisAlignment: -1,
                  child: _roomAnnouncementCard(),
                );
              }
                return _roomMessageAnimatedItem(_messages[index - 1], animation);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _roomAnnouncementCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0x8820182A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(.20), width: .8),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 7, offset: Offset(0, 2))],
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          const Icon(Icons.campaign_rounded, color: _gold, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('إعلان:', style: TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(_roomAnnouncement, style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.4)),
            ],
          )),
        ],
      ),
    );
  }

  Future<void> upgradeRoom(String roomId, int level) async {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) throw Exception('تعذر تحديد رقم الغرفة');
    if (level < 2 || level > 5) throw Exception('المستوى المطلوب غير صالح');
    final response = await http.post(
      Uri.parse('$_apiBase/rooms/${Uri.encodeComponent(normalizedRoomId)}/upgrade'),
      headers: _headers,
      body: jsonEncode({'level': level}),
    ).timeout(const Duration(seconds: 15));
    final dynamic data = jsonDecode(response.body);
    if (response.statusCode == 200 && data is Map && data['ok'] == true) {
      if (mounted && normalizedRoomId == _roomId) {
        setState(() => _roomLevel = (data['level'] as num?)?.toInt() ?? level);
      }
      return;
    }
    final error = data is Map ? (data['error'] ?? '').toString() : '';
    final serverMessage = data is Map ? (data['message'] ?? '').toString() : '';
    final message = serverMessage.isNotEmpty
        ? serverMessage
        : error == 'insufficient_funds'
            ? 'رصيد العملات غير كافٍ'
            : error == 'level_price_unavailable'
                ? 'سعر هذا المستوى لم يُحدد بعد'
                : error == 'room_level_not_higher'
                    ? 'الغرفة وصلت إلى هذا المستوى أو أعلى'
                    : 'تعذر تنفيذ الترقية، حاول مرة أخرى';
    throw Exception(message);
  }

  Future<void> _editRoomAnnouncement() async {
    if (!_isRoomOwner) {
      _showMessage('تعديل الإعلان متاح لمالك الغرفة فقط');
      return;
    }
    final controller = TextEditingController(text: _roomAnnouncement);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF21182B),
        title: const Text('تعديل إعلان الغرفة', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          maxLines: 4,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(hintText: 'اكتب الإعلان...', hintStyle: TextStyle(color: _muted)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('حفظ')),
        ],
      ),
    );
    final announcement = result?.trim();
    controller.dispose();
    if (announcement == null || !mounted) return;
    try {
      final response = await http.patch(
        _announcementUri,
        headers: _headers,
        body: jsonEncode({'announcement': announcement}),
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map && data['ok'] == true) {
        if (mounted) {
          final savedAnnouncement = (data['announcement'] ?? announcement).toString();
          setState(() => _roomAnnouncement = savedAnnouncement);

        }
        _showMessage('تم تحديث إعلان الغرفة');
      } else {
        final message = data is Map ? (data['message'] ?? '').toString() : '';
        _showMessage(message.isNotEmpty ? message : response.statusCode == 403
            ? 'تعديل الإعلان متاح لمالك الغرفة فقط'
            : 'تعذر حفظ إعلان الغرفة، حاول مرة أخرى');
      }
    } catch (_) {
      if (mounted) _showMessage('تعذر الاتصال بالخادم، لم يتم حفظ الإعلان');
    }
  }



  Future<void> _openRoomTools() async {
    if (_roomId.isEmpty || widget.accessToken.isEmpty || !_roomDataReady) {
      _showMessage('انتظر حتى تكتمل بيانات الغرفة');
      return;
    }

    RoomToolsConfig.authToken = () => widget.accessToken;
    RoomToolsConfig.userId = () => _seatStateStore.currentUserId;
    final controller = RoomToolsController(
      roomId: _roomId,
      role: _isRoomOwner
          ? RoomRole.owner
          : (_amRoomModerator ? RoomRole.admin : RoomRole.member),
      micOpen: !_selfMicMuted,
      actions: RoomToolsActions(
        counter: _showRoomCounter,
        pk: _openRoomBattleTools,
        salute: (ctx) {
          CannonService.instance.enterRoom(_roomId, widget.accessToken);
          showCannonSheet(ctx, roomId: _roomId, onSendGift: () => _openRoomGiftPicker());
        },
        onOpenGifts: () => _openRoomGiftPicker(),
        onMicToggle: (open) async {
          if (open == !_selfMicMuted) return true;
          return _toggleSelfMic();
        },
        clearChat: _clearRoomChatForEveryone,
        settings: _openRoomSettings,
        music: (ctx) => showRoomToolsMediaSheet(ctx, music: true),
        soundEffect: (ctx) => showRoomToolsMediaSheet(ctx, music: false),
        micMode: _changeRoomMicLayout,
        background: _openRoomSettings,
        visualEffect: (ctx) => _openRoomGiftPicker(initialCategory: 'trending'),
        redEnvelope: (ctx) => _openRoomGiftPicker(initialCategory: 'event'),
        games: _openRoomGames,
        lucky: (ctx) => _openRoomGiftPicker(initialCategory: 'lucky'),
        store: _openRoomWallet,
        activity: _openRoomActivity,
      ),
    );

    try {
      await showRoomToolsSheet(context, controller);
    } finally {
      controller.dispose();
    }
  }

  void _showRoomCounter(BuildContext host) {
    // The room counter is unavailable while the room is in PK mode.
    if (_pkVisualMode || _roomBattleActive) {
      _showMessage('لا يمكن تبديل وضع الغرفة في هذا الوقت');
      return;
    }
    if (_roomCounter != null) {
      _showMessage('العداد يعمل بالفعل؛ استخدم زر X لإيقافه');
      return;
    }
    const options = <(int, String)>[
      (0, 'التحكم اليدوي'),
      (60, '1 دقيقة'),
      (120, '2 دقيقة'),
      (180, '3 دقائق'),
      (240, '4 دقائق'),
      (300, '5 دقائق'),
      (600, '10 دقائق'),
      (900, '15 دقيقة'),
      (1200, '20 دقيقة'),
      (1800, '30 دقيقة'),
      (3600, '60 دقيقة'),
    ];
    final picker = FixedExtentScrollController(initialItem: 0);
    var selectedIndex = 0;
    showModalBottomSheet<void>(
      context: host,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            top: false,
            child: Container(
              height: MediaQuery.sizeOf(context).height * .58,
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Color(0xFF6428F5), Color(0xFF7334C5), Color(0xFF49245F)]),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(children: [
                Row(children: [
                  IconButton(
                    onPressed: () {
                      final sent = _seatSocket?.send({'type': 'get_room_counter_history'}) ?? false;
                      if (!sent) _showMessage('انتظر اتصال الغرفة لعرض السجل');
                    },
                    icon: const Icon(Icons.receipt_long_rounded, color: Colors.white70, size: 24),
                  ),
                  const Expanded(
                    child: Text('لوحة النتيجة', textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                  ),
                  IconButton(
                    onPressed: () => _showRoomCounterHelp(context),
                    icon: const Icon(Icons.help_outline_rounded, color: Colors.white70, size: 25),
                  ),
                ]),
                const Spacer(),
                SizedBox(
                  height: 190,
                  child: ListWheelScrollView(
                    controller: picker,
                    itemExtent: 48,
                    diameterRatio: 1.8,
                    perspective: .003,
                    physics: const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: (index) => setSheetState(() => selectedIndex = index),
                    children: [
                      for (var i = 0; i < options.length; i++)
                        Center(
                          child: Text(options[i].$2,
                            style: TextStyle(
                              color: selectedIndex == i ? Colors.white : Colors.white.withOpacity(.35),
                              fontSize: selectedIndex == i ? 22 : 17,
                              fontWeight: selectedIndex == i ? FontWeight.w900 : FontWeight.w600,
                            )),
                        ),
                    ],
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () async {
                      final selected = options[selectedIndex].$1;
                      Navigator.pop(sheetContext);
                      var durationSeconds = selected;
                      if (durationSeconds == 0) {
                        final minutes = await _askManualRoomCounterMinutes(host);
                        if (minutes == null) return;
                        durationSeconds = minutes * 60;
                      }
                      final sent = _seatSocket?.send({'type': 'start_room_counter', 'durationSeconds': durationSeconds}) ?? false;
                      if (!sent) _showMessage('انتظر اتصال الغرفة ثم حاول تشغيل العداد');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF2B1B38),
                      elevation: 0,
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('بدء', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ).whenComplete(picker.dispose);
  }

  Future<int?> _askManualRoomCounterMinutes(BuildContext host) async {
    final controller = TextEditingController(text: '1');
    try {
      return await showDialog<int>(
        context: host,
        builder: (dialogContext) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF21152F),
            title: const Text('التحكم اليدوي', style: TextStyle(color: _gold, fontWeight: FontWeight.w900)),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white, fontSize: 20),
              decoration: const InputDecoration(
                labelText: 'مدة العداد بالدقائق',
                labelStyle: TextStyle(color: Colors.white70),
                helperText: 'من دقيقة واحدة إلى 60 دقيقة',
                helperStyle: TextStyle(color: Colors.white54),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () {
                  final minutes = int.tryParse(controller.text.trim());
                  if (minutes == null || minutes < 1 || minutes > 60) return;
                  Navigator.pop(dialogContext, minutes);
                },
                child: const Text('تأكيد'),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  void _showRoomCounterHelp(BuildContext dialogContext) {
    showDialog<void>(
      context: dialogContext,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF21152F),
          title: const Text('طريقة احتساب النتيجة', style: TextStyle(color: _gold, fontWeight: FontWeight.w900)),
          content: const Text(
            'بعد بدء العداد، تُضاف قيمة كل هدية إلى نتيجة مستلمها فوق المايك. يظهر الوقت المتبقي في الشريط البرتقالي، ويمكن إيقاف الجولة بزر X. عند انتهاء الوقت تُحفظ النتيجة في السجل وتبدأ الجولة التالية من الصفر.',
            style: TextStyle(color: Colors.white, height: 1.6),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً'))],
        ),
      ),
    );
  }

  void _showRoomCounterHistory(List<Map<String, dynamic>> records) {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF21152F),
      isScrollControlled: true,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .55,
            child: Column(children: [
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text('سجل لوحة النتيجة', style: TextStyle(color: _gold, fontSize: 18, fontWeight: FontWeight.w900)),
              ),
              Expanded(
                child: records.isEmpty
                    ? const Center(child: Text('لا توجد جولات سابقة', style: TextStyle(color: Colors.white70)))
                    : ListView.separated(
                        itemCount: records.length,
                        separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
                        itemBuilder: (context, index) {
                          final record = records[index];
                          final startedAt = (record['startedAt'] as num?)?.toInt() ?? 0;
                          final date = startedAt > 0
                              ? DateTime.fromMillisecondsSinceEpoch(startedAt).toLocal().toString().substring(0, 16)
                              : '—';
                          final seconds = (record['durationSeconds'] as num?)?.toInt() ?? 0;
                          final coins = (record['totalCoins'] as num?)?.toInt() ?? 0;
                          final members = (record['participantCount'] as num?)?.toInt() ?? 0;
                          return ListTile(
                            leading: const Icon(Icons.emoji_events_rounded, color: _gold),
                            title: Text(date, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                            subtitle: Text('المدة: ${(seconds / 60).round()} دقيقة • المشاركون: $members',
                              style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            trailing: Text(coins.toString(), style: const TextStyle(color: Color(0xFF55E0C2), fontWeight: FontWeight.w900)),
                          );
                        },
                      ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _roomCounterBanner() {
    final counter = _roomCounter;
    if (counter == null) return const SizedBox.shrink();
    final endsAt = (counter['endsAt'] as num?)?.toInt() ?? 0;
    final remaining = ((endsAt - _roomCounterNow) / 1000).ceil().clamp(0, 3600);
    final minutes = (remaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (remaining % 60).toString().padLeft(2, '0');
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 76,
      left: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight,
            colors: [Color(0xFFFFA21A), Color(0xFFFFC85A), Color(0xFFE84A55)]),
          border: Border.all(color: const Color(0xFFFFE6A6), width: 1.2),
          boxShadow: const [BoxShadow(color: Color(0x77000000), blurRadius: 9, offset: Offset(0, 3))],
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
          InkWell(
            onTap: () {
              final sent = _seatSocket?.send({'type': 'stop_room_counter'}) ?? false;
              if (!sent) _showMessage('تعذر إيقاف العداد، تحقق من اتصال الغرفة');
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 23, height: 23,
              decoration: const BoxDecoration(color: Color(0xFF6A3A18), shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 17),
            ),
          ),
          const SizedBox(width: 7),
          Text('$minutes:$seconds', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(width: 5),
          const Text('جاري', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }

  String get _pkTimerLabel {
    final remaining = _roomBattleActive && _pkEndsAt != null
        ? ((_pkEndsAt!.millisecondsSinceEpoch - _pkNowMs) / 1000).ceil().clamp(0, 7200).toInt()
        : _pkDurationMinutes * 60;
    final minutes = (remaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (remaining % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _syncPkTicker() {
    _pkTicker?.cancel();
    if (!_roomBattleActive) return;
    _pkTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _pkNowMs = DateTime.now().millisecondsSinceEpoch);
    });
  }

  void _applyPkBattleScores(Map<String, dynamic> data) {
    final rawUsers = data['userScores'];
    final users = <String, int>{};
    if (rawUsers is Map) {
      rawUsers.forEach((key, value) {
        final score = value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
        if (score != null && score > 0) users[key.toString()] = score;
      });
    }
    setState(() {
      _pkBlueScore = (data['blueScore'] as num?)?.toInt() ?? 0;
      _pkRedScore = (data['redScore'] as num?)?.toInt() ?? 0;
      _pkUserScores = users;
    });
  }

  void _applyPkBattleState(Map<String, dynamic> data) {
    final endsAtValue = data['endsAt']?.toString();
    final parsedEndsAt = endsAtValue == null || endsAtValue.isEmpty
        ? null
        : DateTime.tryParse(endsAtValue)?.toLocal();
    setState(() {
      _roomBattleTeamMode = data['teamMode'] == true;
      _roomBattleActive = data['active'] == true;
      _pkVisualMode = _roomBattleTeamMode;
      _pkStarted = _roomBattleActive;
      _pkEndsAt = parsedEndsAt;
      final durationSeconds = (data['durationSeconds'] as num?)?.toInt();
      if (_roomBattleActive && durationSeconds != null && durationSeconds > 0) {
        _pkDurationMinutes = (durationSeconds ~/ 60).clamp(1, 120).toInt();
      } else if (!_pkDurationOptions.contains(_pkDurationMinutes)) {
        _pkDurationMinutes = _pkDefaultDurationMinutes;
      }
      _pkNowMs = DateTime.now().millisecondsSinceEpoch;
    });
    if (data.containsKey('userScores') || data.containsKey('blueScore') || data.containsKey('redScore')) {
      _applyPkBattleScores(data);
    }
    _syncPkTicker();
  }

  Future<void> _loadInitialPkState() async {
    await _loadPkSettings();
    await _loadRoomBattleState();
  }

  Future<void> _loadPkSettings() async {
    try {
      final response = await http.get(Uri.parse('$_apiBase/pk/settings'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['ok'] != true || decoded['settings'] is! Map) return;
      final settings = Map<String, dynamic>.from(decoded['settings'] as Map);
      final rawOptions = settings['durationOptions'];
      final options = rawOptions is List
          ? (rawOptions.map((value) => value is num ? value.toInt() : int.tryParse(value.toString()))
              .whereType<int>().where((value) => value >= 1 && value <= 120).toSet().toList()..sort())
          : <int>[5, 15, 30, 120];
      if (!mounted) return;
      setState(() {
        _pkEnabled = settings['enabled'] != false;
        _pkChallengeTitle = (settings['challengeTitle'] ?? 'تحدي PK').toString();
        _pkSquareMediaUrl = (settings['mediaUrl'] ?? '').toString();
        _pkSquareMediaType = (settings['mediaType'] ?? '').toString().toLowerCase();
        _pkShowChallengeTitle = settings['showChallengeTitle'] != false;
        _pkShowStartText = settings['showStartText'] != false;
        _pkShowTimer = settings['showTimer'] != false;
        _pkStartMediaUrl = (settings['startMediaUrl'] ?? '').toString();
        _pkStartMediaType = (settings['startMediaType'] ?? '').toString().toLowerCase();
        _pkStartShowDurationSeconds = ((settings['startShowDurationSeconds'] as num?)?.toInt() ?? 3).clamp(1, 30).toInt();
        _pkStartHideDurationSeconds = ((settings['startHideDurationSeconds'] as num?)?.toDouble() ?? 0.5).clamp(0, 5).toDouble();
        _pkSquareRadius = ((settings['squareRadius'] as num?)?.toDouble() ?? 26).clamp(0, 48).toDouble();
        _pkSquareWidthPercent = ((settings['squareWidthPercent'] as num?)?.toDouble() ?? 100).clamp(50, 100).toDouble();
        _pkSquareHeight = ((settings['squareHeight'] as num?)?.toDouble() ?? 284).clamp(240, 500).toDouble();
        _pkMediaOpacity = (((settings['mediaOpacity'] as num?)?.toDouble() ?? 85) / 100).clamp(0, 1).toDouble();
        _normalMicBorderColor = (settings['normalMicBorderColor'] ?? '#FFFFFF').toString();
        _normalMicBorderWidth = ((settings['normalMicBorderWidth'] as num?)?.toDouble() ?? 1.5).clamp(0, 8).toDouble();
        _normalMicFillColor = (settings['normalMicFillColor'] ?? '#FFFFFF').toString();
        _normalMicFillOpacity = (((settings['normalMicFillOpacity'] as num?)?.toDouble() ?? 14) / 100).clamp(0, 1).toDouble();
        _pkMicBorderColor = (settings['pkMicBorderColor'] ?? '#FFFFFF').toString();
        _pkMicBorderWidth = ((settings['pkMicBorderWidth'] as num?)?.toDouble() ?? 2.4).clamp(0, 8).toDouble();
        _pkMicFillColor = (settings['pkMicFillColor'] ?? '#FFFFFF').toString();
        _pkMicFillOpacity = (((settings['pkMicFillOpacity'] as num?)?.toDouble() ?? 12) / 100).clamp(0, 1).toDouble();
        _pkBlueMicBorderColor = (settings['pkBlueMicBorderColor'] ?? '#258BFF').toString();
        _pkRedMicBorderColor = (settings['pkRedMicBorderColor'] ?? '#FF4B5C').toString();
        _micStyleSvgaUrl = (settings['micCircleSvgaUrl'] ?? '').toString();
        _micChairSvgaUrl = (settings['micChairSvgaUrl'] ?? '').toString();
        _micLockSvgaUrl = (settings['micLockSvgaUrl'] ?? '').toString();
        _micCircleScale = ((settings['micCircleScale'] as num?)?.toDouble() ?? 100).clamp(50, 150).toDouble();
        _micChairScale = ((settings['micChairScale'] as num?)?.toDouble() ?? 100).clamp(50, 150).toDouble();
        _micLockScale = ((settings['micLockScale'] as num?)?.toDouble() ?? 100).clamp(50, 150).toDouble();
        _micCircleClarity = ((settings['micCircleClarity'] as num?)?.toDouble() ?? 100).clamp(50, 150).toDouble();
        _micChairClarity = ((settings['micChairClarity'] as num?)?.toDouble() ?? 100).clamp(50, 150).toDouble();
        _micLockClarity = ((settings['micLockClarity'] as num?)?.toDouble() ?? 100).clamp(50, 150).toDouble();
        _micCircleOpacity = ((settings['micCircleOpacity'] as num?)?.toDouble() ?? 100).clamp(0, 100).toDouble();
        _micChairOpacity = ((settings['micChairOpacity'] as num?)?.toDouble() ?? 100).clamp(0, 100).toDouble();
        _micLockOpacity = ((settings['micLockOpacity'] as num?)?.toDouble() ?? 100).clamp(0, 100).toDouble();
        _pkDurationOptions = options.isEmpty ? <int>[5, 15, 30, 120] : options;
        final defaultDuration = (settings['defaultDurationMinutes'] as num?)?.toInt() ?? 5;
        _pkDefaultDurationMinutes = _pkDurationOptions.contains(defaultDuration) ? defaultDuration : _pkDurationOptions.first;
        if (_pkDurationOptions.contains(defaultDuration) && !_roomBattleActive) {
          _pkDurationMinutes = defaultDuration;
        } else if (!_pkDurationOptions.contains(_pkDurationMinutes) && !_roomBattleActive) {
          _pkDurationMinutes = _pkDurationOptions.first;
        }
      });
    } catch (error) {
      debugPrint('[room-pk] settings load failed: $error');
    }
  }

  Widget? _buildPkSquareAnimation() {
    if (!_pkSquareMediaUrl.startsWith('https://')) return null;
    if (_pkSquareMediaType == 'svga') {
      return SVGAEasyPlayer(
        key: ValueKey('pk-square-svga-$_pkSquareMediaUrl'),
        resUrl: _pkSquareMediaUrl,
        // Stretch the uploaded SVGA to the admin-configured PK square bounds.
        fit: BoxFit.fill,
        loops: true,
        volume: 0,
        muted: true,
      );
    }
    if (_pkSquareMediaType == 'gif') {
      return GifView.network(
        _pkSquareMediaUrl,
        key: ValueKey('pk-square-gif-$_pkSquareMediaUrl'),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.fill,
        frameRate: 24,
        autoPlay: true,
        loop: true,
      );
    }
    return null;
  }

  Widget? _buildPkStartAnimation() {
    if (!_pkStartMediaUrl.startsWith('https://')) return null;
    if (_pkStartMediaType == 'svga') {
      return SizedBox(width: 240, height: 120, child: SVGAEasyPlayer(key: ValueKey('pk-start-svga-$_pkStartMediaUrl'), resUrl: _pkStartMediaUrl, fit: BoxFit.contain, loops: true, volume: 0, muted: true));
    }
    if (_pkStartMediaType == 'gif') {
      return GifView.network(_pkStartMediaUrl, key: ValueKey('pk-start-gif-$_pkStartMediaUrl'), width: 240, height: 120, fit: BoxFit.contain, frameRate: 24, autoPlay: true, loop: true);
    }
    return null;
  }

  Future<void> _loadRoomBattleState() async {
    if (_roomId.isEmpty || widget.accessToken.isEmpty) return;
    try {
      final response = await http.get(_roomBattleUri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(response.body);
      if (mounted && decoded is Map && decoded['ok'] == true) {
        _applyPkBattleState(Map<String, dynamic>.from(decoded));
      }
    } catch (error) {
      debugPrint('[room-pk] state load failed: $error');
    }
  }

  Future<void> _submitRoomBattleAction(String action) async {
    if (!mounted || _pkActionBusy || _roomId.isEmpty) return;
    // إغلاق PK يعيد شكل المايكات محلياً فور الضغط، دون انتظار استجابة الشبكة.
    final previousPkState = (
      teamMode: _roomBattleTeamMode,
      visualMode: _pkVisualMode,
      active: _roomBattleActive,
      started: _pkStarted,
      endsAt: _pkEndsAt,
    );
    setState(() {
      _pkActionBusy = true;
      if (action == 'end') {
        _roomBattleTeamMode = false;
        _pkVisualMode = false;
        _roomBattleActive = false;
        _pkStarted = false;
        _pkEndsAt = null;
      }
    });
    if (action == 'end') _syncPkTicker();
    try {
      final response = await http.post(
        _roomBattleUri,
        headers: _headers,
        body: jsonEncode({
          'action': action,
          if (action == 'start' || action == 'prepare') 'durationMinutes': _pkDurationMinutes,
        }),
      ).timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300 || decoded is! Map || decoded['ok'] != true) {
        final code = decoded is Map ? (decoded['error'] ?? '').toString() : '';
        final message = code == 'room_moderator_permission_required'
            ? 'بدء تحدي PK متاح للمالك والمشرفين فقط'
            : code == 'invalid_battle_duration'
                ? 'مدة تحدي PK غير صحيحة'
                : 'تعذر تنفيذ تحدي PK، حاول مرة أخرى';
        if (mounted) {
          _showMessage(message);
          if (action == 'end') {
            setState(() {
              _roomBattleTeamMode = previousPkState.teamMode;
              _pkVisualMode = previousPkState.visualMode;
              _roomBattleActive = previousPkState.active;
              _pkStarted = previousPkState.started;
              _pkEndsAt = previousPkState.endsAt;
            });
            _syncPkTicker();
          }
        }
        return;
      }
      if (mounted) {
        _applyPkBattleState(Map<String, dynamic>.from(decoded));
        // استجابة الإغلاق تحتوي الحالة النهائية؛ لا نؤخرها بطلب GET إضافي.
        if (action != 'end') await _loadRoomBattleState();
      }
    } catch (_) {
      if (mounted) {
        _showMessage('تعذر الاتصال بالخادم، لم يتم تغيير حالة PK');
        if (action == 'end') {
          setState(() {
            _roomBattleTeamMode = previousPkState.teamMode;
            _pkVisualMode = previousPkState.visualMode;
            _roomBattleActive = previousPkState.active;
            _pkStarted = previousPkState.started;
            _pkEndsAt = previousPkState.endsAt;
          });
          _syncPkTicker();
        }
      }
    } finally {
      if (mounted) setState(() => _pkActionBusy = false);
    }
  }

  void _startRoomBattle() {
    if (!mounted || !_pkEnabled || _pkStartingCountdown || _roomBattleActive || _pkActionBusy) return;
    // START is an independent visual cue. Its display/fade never delays PK start.
    setState(() { _pkStartingCountdown = true; _pkStartHiding = false; });
    _pkStartCountdownTimer?.cancel();
    _pkStartCountdownTimer = Timer(Duration(seconds: _pkStartShowDurationSeconds), () {
      if (!mounted) return;
      if (_pkStartHideDurationSeconds <= 0) {
        setState(() { _pkStartingCountdown = false; _pkStartHiding = false; });
        return;
      }
      setState(() => _pkStartHiding = true);
      _pkStartCountdownTimer = Timer(Duration(milliseconds: (_pkStartHideDurationSeconds * 1000).round()), () {
        if (!mounted) return;
        setState(() { _pkStartingCountdown = false; _pkStartHiding = false; });
      });
    });
    unawaited(_submitRoomBattleAction('start'));
  }

  void _openRoomBattleTools(BuildContext host) {
    showPkSheet(
      host,
      isPkVisualMode: _pkVisualMode,
      isPkActive: _roomBattleActive,
      selectedDurationMinutes: _pkDurationMinutes,
      onDurationChanged: (minutes) {
        if (!mounted || _roomBattleActive || !_pkDurationOptions.contains(minutes)) return;
        setState(() => _pkDurationMinutes = minutes);
      },
      // زر «بدأ» يبدأ الجولة فعلياً فوراً؛ لا يمر بمرحلة prepare.
      // عند وجود جولة نشطة يتحول نفس الزر إلى إيقاف PK.
      onToggle: () {
        if (_pkVisualMode) {
          unawaited(_submitRoomBattleAction('end'));
        } else {
          _startRoomBattle();
        }
      },
      onReset: () => unawaited(_submitRoomBattleAction('reset')),
      durationOptions: _pkDurationOptions,
      challengeTitle: _pkShowChallengeTitle ? _pkChallengeTitle : '',
    );
  }

  void _openRoomGames(BuildContext host) {
    showModalBottomSheet<void>(
      context: host,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          height: MediaQuery.sizeOf(sheetContext).height * .78,
          padding: EdgeInsets.fromLTRB(16, 18, 16, MediaQuery.paddingOf(sheetContext).bottom + 12),
          decoration: const BoxDecoration(
            color: Color(0xFFF5EEDC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const Text('مركز الألعاب', style: TextStyle(color: Color(0xFF211B16), fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              const Expanded(child: SingleChildScrollView(child: DynamicGamesList())),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openRoomSettings(BuildContext host) async {
    await Navigator.of(host).push(
      MaterialPageRoute<void>(
        builder: (_) => RoomSettingsPage(
          c: RoomSettingsController(
            api: MyWorkersApi(roomId: _roomId, accessToken: widget.accessToken),
          ),
          onCoverChanged: _applyRoomCoverUpdate,
        ),
      ),
    );
    if (mounted) await _refreshSeats();
  }

  Future<void> _changeRoomMicLayout(BuildContext host) async {
    final selected = await showMicCountSheet(host, currentId: _micLayoutId);
    if (selected == null || selected == _micLayoutId || !host.mounted) return;
    final layout = micLayoutById(selected);
    final settings = RoomSettingsController(
      api: MyWorkersApi(roomId: _roomId, accessToken: widget.accessToken),
    );
    try {
      await settings.load();
      await settings.setMicLayout(layout.id, layout.count);
      await _refreshSeats();
      if (host.mounted) _showMessage('تم تحديث عدد المقاعد');
    } catch (_) {
      if (host.mounted) _showMessage('تعذر حفظ عدد المقاعد');
    } finally {
      settings.dispose();
    }
  }

  void _openRoomWallet(BuildContext host) {
    Navigator.of(host).push(MaterialPageRoute<void>(
      builder: (_) => WalletPage(apiBase: _apiBase, accessToken: widget.accessToken),
    ));
  }

  void _openRoomActivity(BuildContext host) {
    showModalBottomSheet<void>(
      context: host,
      backgroundColor: const Color(0xFF21152F),
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('نشاط الغرفة', style: TextStyle(color: _gold, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              _roomActivityLine('مستوى الغرفة', '$_roomExperienceLevel'),
              _roomActivityLine('نقاط الخبرة', _roomExperienceExp.toString()),
              _roomActivityLine('خبرة اليوم', _roomDailyExperienceExp.toString()),
              _roomActivityLine('عدد الحضور', _audienceCount.toString()),
              _roomActivityLine('عدد المقاعد', _micCount.toString()),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _roomActivityLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: Colors.white70))),
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
    ]),
  );

  void _clearRoomChatLocally() {
    final listState = _roomAnimatedListKey.currentState;
    if (listState == null) {
      if (mounted) {
        setState(() {
          _messages.clear();
          _messageIds.clear();
        });
      } else {
        _messages.clear();
        _messageIds.clear();
      }
      return;
    }
    for (var index = _messages.length - 1; index >= 0; index--) {
      final message = _messages.removeAt(index);
      listState.removeItem(
        index + 1,
        (context, animation) => _roomMessageAnimatedItem(message, animation, removing: true),
        duration: const Duration(milliseconds: 140),
      );
    }
    _messageIds.clear();
  }

  Future<void> _clearRoomChatForEveryone(BuildContext host) async {
    if (!_isRoomOwner && !_amRoomModerator) {
      _showMessage('مسح الدردشة متاح لمالك الغرفة والمشرفين فقط');
      return;
    }
    try {
      final response = await http.delete(_messagesUri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      final payload = jsonDecode(response.body);
      if (response.statusCode == 200 && payload is Map && payload['ok'] == true) {
        _clearRoomChatLocally();
        if (host.mounted) _showMessage('تم مسح دردشة الغرفة للجميع');
        return;
      }
      final message = payload is Map ? (payload['message'] ?? '').toString() : '';
      if (host.mounted) _showMessage(message.isNotEmpty ? message : 'تعذر مسح دردشة الغرفة');
    } catch (_) {
      if (host.mounted) _showMessage('تعذر الاتصال بالخادم، لم يتم مسح الدردشة');
    }
  }

  void _showChatToolMessage(String label) {
    _showMessage('$label — واجهة تجريبية للمرحلة الأولى');
  }

  void _showRoomChatMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF21182B),
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.people_outline, color: _gold), title: const Text('أعضاء الغرفة', style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(context); _showChatToolMessage('أعضاء الغرفة'); }),
        ListTile(leading: const Icon(Icons.flag_outlined, color: _gold), title: const Text('إبلاغ', style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(context); _showChatToolMessage('الإبلاغ'); }),
      ])),
    );
  }

  Future<void> _copyRoomCode() async {
    if (_roomCode.length != 8) return;
    await Clipboard.setData(ClipboardData(text: _roomCode));
    if (!mounted) return;
    showCenteredNotification(context, 
      const SnackBar(content: Text('تم نسخ رقم الغرفة'), behavior: SnackBarBehavior.floating),
    );
  }

  // PK overflow microphones form a fixed first-come queue (13, 14, 15...).
  // A user who has joined this queue cannot hop between its seats.
  void _selectPkOverflowQueueSeat(int tappedSeatNumber) {
    if (tappedSeatNumber <= 12) {
      _selectSeat(tappedSeatNumber);
      return;
    }

    if (_mySeat != null && _mySeat! > 12) {
      _showMessage('أنت في الطابور بالفعل، لا يمكنك التنقل بين مايكاته');
      return;
    }

    // The overflow row is interactive: join the exact seat the user tapped.
    // Do not silently redirect the tap to the first available queue seat.
    final selectedSeat = _seatStateStore.seats[tappedSeatNumber];
    final seatFromSnapshot = _seats.cast<Map<String, dynamic>?>().firstWhere(
      (seat) => seat?['seatNumber'] == tappedSeatNumber,
      orElse: () => null,
    );
    final occupied = selectedSeat?.occupied == true ||
        (seatFromSnapshot?['userId'] ?? '').toString().trim().isNotEmpty;
    final locked = selectedSeat?.isLocked == true ||
        seatFromSnapshot?['isLocked'] == true ||
        seatFromSnapshot?['locked'] == true;

    if (occupied) {
      _showMessage('هذا المايك مشغول، اختر مايكًا فارغًا');
      return;
    }
    if (locked) {
      _showMessage('هذا المايك مقفل');
      return;
    }
    if (_pendingSeatNumbers.contains(tappedSeatNumber) ||
        selectedSeat?.isPending == true) {
      return;
    }

    unawaited(_selectSeat(tappedSeatNumber));
  }

  Future<void> _selectSeat(int seatNumber) async {
    if (!_voiceEnabled) {
      _showMessage('خدمة الصوت متوقفة حاليًا من إدارة التطبيق');
      return;
    }
    if (_isBannedFromRoom) {
      _showMessage('أنت محظور من استخدام المايك في هذه الغرفة');
      return;
    }

    if (_seatStateStore.seats[seatNumber]?.isLocked == true) {
      _showMessage('هذا المايك مقفل');
      return;
    }
    final tapTimer = Stopwatch()..start();
    final command = _seatStateStore.beginOptimisticMove(seatNumber);
    if (command == null) return;
    _seatMoveTimers[command.version] = tapTimer;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[SeatLatency] optimistic_avatar_frame_ms=${(tapTimer.elapsedMicroseconds / 1000).toStringAsFixed(2)} version=${command.version}');
    });

    final socket = _seatSocket;
    if (socket != null && socket.isConnected &&
        socket.sendMove(from: command.from, to: command.to, version: command.version)) {
      return;
    }

    // Short reconnect fallback. The Worker forwards this mutation to the
    // same room Durable Object; the move itself is never committed in D1.
    try {
      final response = await http.post(
        _seatsUri,
        headers: _headers,
        body: jsonEncode({'seatNumber': command.to, 'version': command.version}),
      ).timeout(const Duration(seconds: 8));
      final data = jsonDecode(response.body);
      final fallbackTimer = _seatMoveTimers.remove(command.version);
      if (fallbackTimer != null) {
        debugPrint('[SeatLatency] http_fallback_ack_ms=${(fallbackTimer.elapsedMicroseconds / 1000).toStringAsFixed(2)} version=${command.version}');
      }
      final hasSnapshot = data is Map && data['seats'] is List;
      if (!hasSnapshot) {
        _seatStateStore.rollbackAfterDisconnect(command.version);
        await _refreshSeats();
        _showMessage('تعذر تأكيد تغيير المايك، تمت مزامنة الغرفة');
        return;
      }
      final accepted = response.statusCode == 200 && data['ok'] == true;
      final rawSeats = data['seats'] as List;
      final isLatest = _seatStateStore.isLatest(command.version);
      _seatStateStore.resolveMove(
        version: command.version,
        accepted: accepted,
        serverSeats: rawSeats,
        serverMySeat: data['mySeat'] is num ? (data['mySeat'] as num).toInt() : null,
      );
      if (isLatest) {
        _applyRealtimeSeatSnapshot(
          rawSeats,
          mySeat: data['mySeat'] is num ? (data['mySeat'] as num).toInt() : null,
          updateStore: false,
        );
      }
      if (!accepted) {
        _showMessage(data is Map && data['error'] == 'mic_restricted'
            ? 'استخدام المايك متاح للمالك والمشرفين فقط'
            : response.statusCode == 409
                ? 'هذا المايك مشغول، اختر مايكًا آخر'
                : 'تعذر تغيير المايك، تمت استعادة الحالة السابقة');
      }
    } catch (_) {
      _seatMoveTimers.remove(command.version);
      _seatStateStore.rollbackAfterDisconnect(command.version);
      _showMessage('تعذر الاتصال بالغرفة، تمت استعادة المقعد السابق');
    }
  }

  Future<void> _leaveSeat() async {
    if (_mySeat == null || _isChangingSeat) return;
    setState(() => _isChangingSeat = true);
    try {
      final response = await http.post(
        _seatsUri,
        headers: _headers,
        body: jsonEncode({'seatNumber': null}),
      ).timeout(const Duration(seconds: 8));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map && data['ok'] == true) {
        _applySeatData(Map<String, dynamic>.from(data));
      } else {
        _showMessage('تعذر مغادرة المايك');
        await _refreshSeats();
      }
    } catch (_) {
      _showMessage('تعذر الاتصال بالخادم');
    } finally {
      if (mounted) setState(() => _isChangingSeat = false);
    }
  }

  void _showRoomGiftOverlay(Map<String, dynamic> event) {
    final gift = Map<String, dynamic>.from(event);
    final mediaType = (gift['mediaType'] ?? '').toString().trim().toLowerCase();
    _roomGiftOverlayTimer?.cancel();
    unawaited(_playGiftSound(gift));
    setState(() {
      _activeRoomGift = gift;
      _roomGiftOverlayNonce++;
    });

    // Each gift uses its saved administrator-configured duration.
    // Clamp the value defensively to keep malformed events from sticking.
    final configuredSeconds = double.tryParse((gift['durationSeconds'] ?? '5').toString()) ?? 5.0;
    final durationMilliseconds = (configuredSeconds.clamp(0.1, 60.0) * 1000).round();
    final overlayNonce = _roomGiftOverlayNonce;
    _roomGiftOverlayTimer = Timer(Duration(milliseconds: durationMilliseconds), () {
      _finishRoomGiftOverlay(overlayNonce);
    });
  }

  void _finishRoomGiftOverlay(int nonce) {
    if (!mounted || nonce != _roomGiftOverlayNonce || _activeRoomGift == null) return;
    _roomGiftOverlayTimer?.cancel();
    setState(() => _activeRoomGift = null);
  }

  Future<void> _unlockGiftAudio() async {
    if (_giftAudioUnlocked) return;
    try {
      // Browsers (especially mobile Safari) may suspend audio until a real
      // user gesture. Resume the room player on the first room interaction.
      await _giftAudioPlayer.resume();
      _giftAudioUnlocked = true;
    } catch (error) {
      debugPrint('[GiftSound] audio unlock pending: $error');
    }
  }

  Future<void> _playGiftSound(Map<String, dynamic> gift) async {
    final soundUrl = (gift['soundUrl'] ?? '').toString().trim();
    if (!soundUrl.startsWith('https://')) {
      await _giftAudioPlayer.stop();
      return;
    }
    try {
      await _giftAudioPlayer.stop();
      await _giftAudioPlayer.play(UrlSource(soundUrl));
    } catch (error) {
      debugPrint('[GiftSound] playback failed: $error');
    }
  }

  Widget _roomGiftFullscreenOverlay() {
    final gift = _activeRoomGift!;
    final overlayNonce = _roomGiftOverlayNonce;
    final mediaUrl = (gift['mediaUrl'] ?? '').toString().trim();
    final mediaType = (gift['mediaType'] ?? '').toString().toLowerCase();
    final sender = (gift['senderName'] ?? 'مستخدم').toString();
    final recipient = (gift['recipientName'] ?? 'مستخدم').toString();
    final giftName = (gift['name'] ?? 'هدية').toString();
    Widget animation;
    if (mediaUrl.startsWith('https://') && mediaType == 'svga') {
      animation = SVGAEasyPlayer(
        key: ValueKey('room-gift-svga-$_roomGiftOverlayNonce'),
        resUrl: mediaUrl,
        fit: BoxFit.contain,
        loops: true,
        volume: 0,
        muted: true,
      );
    } else if (mediaUrl.startsWith('https://') &&
        (mediaType == 'gif' || mediaType == 'apng' || mediaUrl.toLowerCase().split('?').first.endsWith('.gif'))) {
      // Use the same animated decoder as the gift picker. Image.network can
      // render an animated GIF as a still frame on some Flutter Web clients.
      animation = GifView.network(
        mediaUrl,
        key: ValueKey('room-gift-gif-$_roomGiftOverlayNonce'),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.contain,
        // Loop briefly so the animation remains visible even when the
        // decoder reports a zero/very short duration for optimized GIFs.
        frameRate: 24,
        autoPlay: true,
        loop: true,
        progressBuilder: (context) => const Center(
          child: CircularProgressIndicator(color: Color(0xFFE8C477)),
        ),
        errorBuilder: (context, error, tryAgain) => Center(
          child: Text((gift['iconEmoji'] ?? '🎁').toString(), style: const TextStyle(fontSize: 110)),
        ),
      );
    } else {
      animation = Center(
        child: Text((gift['iconEmoji'] ?? '🎁').toString(), style: const TextStyle(fontSize: 120)),
      );
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: const Color(0x44000000),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(child: SizedBox.expand(child: animation)),
              Positioned(
                left: 18,
                right: 18,
                bottom: 34,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xD9000000),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0x99E8C477)),
                    ),
                    child: Text(
                      '$sender أهدى $giftName إلى $recipient',
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openRoomGiftPicker({
    Map<String, dynamic>? targetRecipient,
    String initialCategory = 'trending',
  }) async {
    if (_roomId.isEmpty || widget.accessToken.isEmpty) {
      _showMessage('تعذر فتح الهدايا: بيانات الغرفة غير مكتملة');
      return;
    }

    try {
      final walletResponse = await http.get(
        Uri.parse('$_apiBase/wallet'),
        headers: _headers,
      ).timeout(const Duration(seconds: 8));
      final walletData = walletResponse.statusCode == 200
          ? jsonDecode(walletResponse.body)
          : null;
      if (walletResponse.statusCode != 200 ||
          walletData is! Map ||
          walletData['balance'] is! num) {
        _showMessage('تعذر تحميل رصيد المحفظة');
        return;
      }
      final walletBalance = (walletData['balance'] as num).toInt();

      final participants = <String, Map<String, dynamic>>{};
      if (targetRecipient != null) {
        final targetId = (targetRecipient['userId'] ?? targetRecipient['id'] ?? '').toString().trim();
        if (targetId.isNotEmpty) {
          participants[targetId] = <String, dynamic>{
            ...targetRecipient,
            'userId': targetId,
            'name': (targetRecipient['name'] ?? targetRecipient['displayName'] ?? 'مستخدم').toString(),
            'avatarUrl': (targetRecipient['avatarUrl'] ?? targetRecipient['avatar'] ?? '').toString(),
          };
        }
      }
      for (final user in [..._seats, ..._audienceUsers]) {
        final id = (user['userId'] ?? user['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        participants[id] = <String, dynamic>{
          ...user,
          'userId': id,
          'name': (user['name'] ?? user['displayName'] ?? 'مستخدم').toString(),
          'avatarUrl': (user['avatarUrl'] ?? user['avatar'] ?? '').toString(),
        };
      }
      // Keep the signed-in user selectable too: the API rejects self-gifting
      // with the dedicated "cannot_gift_self" response shown in the sheet.
      final currentUserId = _seatStateStore.currentUserId.trim();
      if (currentUserId.isNotEmpty) {
        final selfSeats = _seats.where((user) => user['isMe'] == true).toList();
        final selfSeat = selfSeats.isEmpty ? null : selfSeats.first;
        participants.putIfAbsent(currentUserId, () => <String, dynamic>{
          'userId': currentUserId,
          'name': (selfSeat?['name'] ?? (_ownerId == currentUserId ? _ownerName : 'أنا')).toString(),
          'avatarUrl': (selfSeat?['avatarUrl'] ?? _seatStateStore.currentAvatarUrl).toString(),
          'isMe': true,
        });
      }
      final recipients = participants.values.toList()
        ..sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));

      await showRoomGiftSheet(
        context,
        balance: walletBalance,
        avatarUrl: _seatStateStore.currentAvatarUrl,
        recipients: recipients,
        initialRecipientId: (targetRecipient?['userId'] ?? targetRecipient?['id'] ?? '').toString(),
        initialTab: initialCategory,
        loadGifts: (category) async {
          final uri = Uri.parse('$_apiBase/gifts/catalog').replace(
            queryParameters: {'tab': category},
          );
          final response = await http.get(
            uri,
            headers: category == 'country'
                ? _headers
                : const {'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 12));
          final data = jsonDecode(response.body);
          if (response.statusCode != 200 || data is! Map || data['gifts'] is! List) {
            final error = data is Map ? (data['message'] ?? data['error'])?.toString() : null;
            throw Exception(error == null || error.isEmpty
                ? 'تعذر تحميل هدايا هذا التصنيف'
                : error);
          }
          return (data['gifts'] as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        },
        onSend: (gift, quantity, recipientId) async {
          final idempotencyKey =
              'roomgift:${DateTime.now().microsecondsSinceEpoch}:${gift['id']}:$recipientId';
          final response = await http.post(
            Uri.parse('$_apiBase/rooms/${Uri.encodeComponent(_roomId)}/gifts/send'),
            headers: _headers,
            body: jsonEncode({
              'recipientUserId': recipientId,
              'giftId': gift['id'],
              'quantity': quantity,
              'idempotencyKey': idempotencyKey,
            }),
          ).timeout(const Duration(seconds: 12));
          final result = jsonDecode(response.body);
          if ((response.statusCode != 200 && response.statusCode != 201) ||
              result is! Map ||
              result['ok'] != true) {
            final error = result is Map ? result['error']?.toString() : null;
            throw Exception(switch (error) {
              'insufficient_balance' => 'رصيدك من العملات غير كافٍ',
              'recipient_not_present' || 'recipient_not_in_room' || 'recipient_not_room_member' => 'لا يمكن إرسال الهدية لهذا الحساب من هذه الغرفة',
              'cannot_gift_self' => 'لا يمكنك إرسال هدية لنفسك',
              'gift_not_available' => 'هذه الهدية غير متاحة حاليًا',
              'room_not_found' => 'الغرفة لم تعد نشطة',
              _ => 'تعذر إرسال الهدية، حاول مرة أخرى',
            });
          }
          final refreshedWallet = await http.get(
            Uri.parse('$_apiBase/wallet'),
            headers: _headers,
          ).timeout(const Duration(seconds: 8));
          final refreshedData = jsonDecode(refreshedWallet.body);
          if (refreshedWallet.statusCode != 200 ||
              refreshedData is! Map ||
              refreshedData['balance'] is! num) {
            throw Exception('تم الإرسال، لكن تعذر تحديث الرصيد');
          }
          await _refreshSeats();
          return (refreshedData['balance'] as num).toInt();
        },
        onRequestCustomGift: (name, description, bytes, fileName, mediaType, durationMs, soundBytes, soundFileName) async {
          final authResponse = await http.get(
            Uri.parse('$_apiBase/imagekit/auth'),
            headers: _headers,
          ).timeout(const Duration(seconds: 10));
          final authData = jsonDecode(authResponse.body);
          if (authResponse.statusCode != 200 || authData is! Map ||
              authData['token'] == null || authData['signature'] == null ||
              authData['expire'] == null || authData['publicKey'] == null) {
            throw Exception('تعذر تجهيز الرفع إلى ImageKit');
          }

          final uploadRequest = http.MultipartRequest(
            'POST',
            Uri.parse('https://upload.imagekit.io/api/v1/files/upload'),
          );
          uploadRequest.fields.addAll({
            'fileName': fileName,
            'publicKey': authData['publicKey'].toString(),
            'token': authData['token'].toString(),
            'expire': authData['expire'].toString(),
            'signature': authData['signature'].toString(),
            'folder': '/happy-live/custom-gifts',
            'useUniqueFileName': 'true',
          });
          uploadRequest.files.add(http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: fileName,
          ));
          final uploadStream = await uploadRequest.send().timeout(const Duration(seconds: 60));
          final uploadResponse = await http.Response.fromStream(uploadStream);
          final uploadData = jsonDecode(uploadResponse.body);
          if (uploadResponse.statusCode != 200 || uploadData is! Map ||
              uploadData['url'] == null || uploadData['fileId'] == null) {
            throw Exception('فشل رفع الملف إلى ImageKit');
          }

          String? soundUrl;
          String? soundFileId;
          if (soundBytes != null && soundFileName != null) {
            if (!soundFileName.toLowerCase().endsWith('.mp3') || soundBytes.isEmpty || soundBytes.length > 5 * 1024 * 1024) {
              throw Exception('اختر ملف MP3 لا يتجاوز 5 ميجابايت');
            }

            // ImageKit upload tokens are single-use. Request a fresh signature for
            // the second file instead of reusing the token consumed by the animation.
            final soundAuthResponse = await http.get(
              Uri.parse('$_apiBase/imagekit/auth'),
              headers: _headers,
            ).timeout(const Duration(seconds: 10));
            final soundAuthData = jsonDecode(soundAuthResponse.body);
            if (soundAuthResponse.statusCode != 200 || soundAuthData is! Map ||
                soundAuthData['token'] == null || soundAuthData['signature'] == null ||
                soundAuthData['expire'] == null || soundAuthData['publicKey'] == null) {
              throw Exception('تعذر تجهيز اعتماد مستقل لصوت الهدية (' + soundAuthResponse.statusCode.toString() + ')');
            }

            final soundRequest = http.MultipartRequest(
              'POST',
              Uri.parse('https://upload.imagekit.io/api/v1/files/upload'),
            );
            soundRequest.fields.addAll({
              'fileName': soundFileName,
              'publicKey': soundAuthData['publicKey'].toString(),
              'token': soundAuthData['token'].toString(),
              'expire': soundAuthData['expire'].toString(),
              'signature': soundAuthData['signature'].toString(),
              'folder': '/happy-live/custom-gift-sounds',
              'useUniqueFileName': 'true',
            });
            soundRequest.files.add(http.MultipartFile.fromBytes('file', soundBytes, filename: soundFileName));
            final soundStream = await soundRequest.send().timeout(const Duration(seconds: 60));
            final soundResponse = await http.Response.fromStream(soundStream);
            final soundData = jsonDecode(soundResponse.body);
            if (soundResponse.statusCode != 200 || soundData is! Map ||
                soundData['url'] == null || soundData['fileId'] == null) {
              final providerMessage = soundData is Map
                  ? (soundData['message'] ?? soundData['help'] ?? soundData['error'] ?? 'رد غير معروف من ImageKit')
                  : 'استجابة غير صالحة من ImageKit';
              throw Exception('فشل رفع صوت الهدية إلى ImageKit (' + soundResponse.statusCode.toString() + '): ' + providerMessage.toString());
            }
            soundUrl = soundData['url'].toString();
            soundFileId = soundData['fileId'].toString();
          }

          final response = await http.post(
            Uri.parse('$_apiBase/gifts/custom-requests'),
            headers: _headers,
            body: jsonEncode({
              'requestedName': name,
              'description': description,
              'mediaUrl': uploadData['url'],
              'mediaFileId': uploadData['fileId'],
              'mediaType': mediaType,
              'mediaDurationMs': durationMs,
              'soundUrl': soundUrl,
              'soundFileId': soundFileId,
            }),
          ).timeout(const Duration(seconds: 12));
          final data = jsonDecode(response.body);
          if (response.statusCode != 201 || data is! Map || data['ok'] != true) {
            final error = data is Map ? data['message'] ?? data['error'] : null;
            throw Exception(error?.toString() ?? 'تعذر إرسال اقتراح الهدية');
          }
        },
        onRecharge: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => WalletPage(
                apiBase: _apiBase,
                accessToken: widget.accessToken,
              ),
            ),
          );
        },
      );
    } catch (error) {
      _showMessage('تعذر فتح نافذة الهدايا: ${error.toString().replaceFirst('Exception: ', '')}');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    showCenteredNotification(context, 
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Map<String, dynamic>? _seatAt(int number) {
    for (final seat in _seats) {
      if (seat['seatNumber'] == number) return seat;
    }
    return null;
  }

  Future<void> _openCannonBannerRoom(String targetRoomId) async {
    final id = targetRoomId.trim();
    if (id.isEmpty || id == _roomId || widget.accessToken.trim().isEmpty) return;
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/rooms/${Uri.encodeComponent(id)}/seats'),
        headers: _headers,
      ).timeout(const Duration(seconds: 12));
      final payload = jsonDecode(response.body);
      if (response.statusCode != 200 || payload is! Map || payload['room'] is! Map) {
        _showMessage('تعذر فتح الغرفة المطلوبة من بنر المدفع');
        return;
      }
      final targetRoom = Map<String, dynamic>.from(payload['room'] as Map);
      targetRoom['id'] ??= id;
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => RoomPage(room: targetRoom, accessToken: widget.accessToken),
      ));
    } catch (_) {
      if (mounted) _showMessage('تعذر الاتصال بالغرفة المطلوبة');
    }
  }

  void _applyRoomCoverUpdate(String url) {
    final next = url.trim();
    if (next.isEmpty || !mounted) return;
    setState(() => _roomCoverUrl = next);
  }

  @override
  Widget build(BuildContext context) {
    if (_isMinimized) {
      return const Scaffold(
        backgroundColor: Color(0xFF08141C),
        body: SizedBox.expand(),
      );
    }
    return Listener(
        onPointerDown: (_) => unawaited(_unlockGiftAudio()),
        child: Stack(
      fit: StackFit.expand,
      children: [
        ChangeNotifierProvider<SeatStateStore>.value(
          value: _seatStateStore,
          child: VoiceRoomDesignPreview(
      room: {
        ...widget.room,
        'imageUrl': _roomCoverUrl,
        'coverUrl': _roomCoverUrl,
        'ownerId': _ownerId,
        'owner': {
          'id': _ownerId,
          'name': _ownerName,
          'avatarUrl': _ownerAvatarUrl,
          'countryName': _ownerCountryName,
        },
        'level': _roomLevel, 'experienceLevel': _roomExperienceLevel,
        'experienceExp': _roomExperienceExp,
        'experienceNextLevelExp': _roomExperienceNextLevelExp,
        'dailyExperienceExp': _roomDailyExperienceExp,
        'micCount': _micCount,
        'micLayoutId': _micLayoutId,
        'palaceStatus': _roomLevel >= 5 ? 'مفعّل' : 'غير مفعّل',
      },
      chatMessagesPanel: _roomMessagesPanel(),
      chatController: _messageController,
      chatFocusNode: _roomChatFocusNode,
      onSendChat: _sendRoomMessage,
      accessToken: widget.accessToken,
      currentUserCode: _seatStateStore.currentUserCode,
      seats: _seats,
      speakerLevels: _speakerLevels,
      onTapSeat: (seatNumber) {
        if (_pkVisualMode && seatNumber > 12) {
          _selectPkOverflowQueueSeat(seatNumber);
        } else {
          _selectSeat(seatNumber);
        }
      },
      onJoinSeat: (seatNumber) {
        if (_pkVisualMode && seatNumber > 12) {
          _selectPkOverflowQueueSeat(seatNumber);
        } else {
          unawaited(_selectSeat(seatNumber));
        }
      },
      isChangingSeat: _isChangingSeat,
      pendingSeatNumbers: _pendingSeatNumbers,
      audienceCount: _audienceCount,
      audienceUsers: _audienceUsers,
      ownerName: _ownerName,
      ownerAvatarUrl: _ownerAvatarUrl,
      ownerCountryName: _ownerCountryName,
      isCurrentUserRoomOwner: _isRoomOwner,
      canModerateUsers: _isRoomOwner || _amRoomModerator,
      selfMicMuted: _selfMicMuted,
      onToggleSelfMic: _toggleSelfMic,
      onModerateUser: _moderateRoomUser,
      onModerateSeat: _moderateRoomSeat,
      showRoomActions: _showRoomActions,
      onRoomActions: () => setState(() => _showRoomActions = !_showRoomActions),
      onRoomTools: _openRoomTools,
      onMinimizeRoom: _minimizeRoom,
      onCloseRoom: _closeRoom,
      onPkReset: () => unawaited(_submitRoomBattleAction('reset')),
      onPkStart: (_isRoomOwner || _amRoomModerator)
          ? () => _startRoomBattle()
          : null,
      onPkOpen: (_isRoomOwner || _amRoomModerator)
          ? () => _openRoomBattleTools(context)
          : null,
      onUpgradeRoom: upgradeRoom,
      onOpenGifts: _openRoomGiftPicker,
      onOpenCannonRoom: _openCannonBannerRoom,
      onRoomSettingsChanged: _refreshSeats,
      onRoomCoverChanged: _applyRoomCoverUpdate,
      isRoomDataReady: _roomDataReady,
      roomGiftScores: _roomGiftScores,
      isRoomGiftCounterActive: _roomCounter != null,
      pkTeamMode: _roomBattleTeamMode,
      pkActive: _roomBattleActive,
      pkVisualMode: _pkVisualMode,
      pkStarted: _pkStarted,
      pkBlueScore: _pkBlueScore,
      pkRedScore: _pkRedScore,
      pkUserScores: _pkUserScores,
      pkTimerLabel: _pkTimerLabel,
      pkStartingCountdown: _pkStartingCountdown,
      pkStartHiding: _pkStartHiding,
      pkStartHideDurationSeconds: _pkStartHideDurationSeconds,
      pkStartAnimation: _buildPkStartAnimation(),
      pkEnabled: _pkEnabled,
      pkChallengeTitle: _pkChallengeTitle,
      pkShowChallengeTitle: _pkShowChallengeTitle,
      pkShowStartText: _pkShowStartText,
      pkShowTimer: _pkShowTimer,
      pkSquareRadius: _pkSquareRadius,
      pkSquareWidthPercent: _pkSquareWidthPercent,
      pkSquareHeight: _pkSquareHeight,
      pkSquareAnimation: _buildPkSquareAnimation(),
      pkMediaOpacity: _pkMediaOpacity,
      normalMicBorderColor: _normalMicBorderColor,
      normalMicBorderWidth: _normalMicBorderWidth,
      normalMicFillColor: _normalMicFillColor,
      normalMicFillOpacity: _normalMicFillOpacity,
      pkMicBorderColor: _pkMicBorderColor,
      pkMicBorderWidth: _pkMicBorderWidth,
      pkMicFillColor: _pkMicFillColor,
      pkMicFillOpacity: _pkMicFillOpacity,
      pkBlueMicBorderColor: _pkBlueMicBorderColor,
      pkRedMicBorderColor: _pkRedMicBorderColor,
      micStyleUrl: _micStyleSvgaUrl,
      micChairStyleUrl: _micChairSvgaUrl,
      micLockStyleUrl: _micLockSvgaUrl,
      micCircleScale: _micCircleScale,
      micChairScale: _micChairScale,
      micLockScale: _micLockScale,
      micCircleClarity: _micCircleClarity,
      micChairClarity: _micChairClarity,
      micLockClarity: _micLockClarity,
      micCircleOpacity: _micCircleOpacity,
      micChairOpacity: _micChairOpacity,
      micLockOpacity: _micLockOpacity,
          ),
        ),        if (_roomCounter != null) _roomCounterBanner(),
        if (_activeRoomGift != null) _roomGiftFullscreenOverlay(),
        ],
        ),
    );
  }

  Widget _referenceRoomHeader() {
    final ownerAvatar = (_ownerAvatarUrl.trim().isNotEmpty
        ? _ownerAvatarUrl.trim()
        : (widget.room['ownerAvatar'] ?? widget.room['ownerAvatarUrl'] ?? '').toString().trim());
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 0),
      child: Row(
        children: [
          Material(
            color: const Color(0xAA06212B),
            borderRadius: BorderRadius.circular(15),
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: () => setState(() => _showRoomActions = !_showRoomActions),
              child: Container(
                width: 43, height: 43,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0x55FFFFFF)),
                ),
                child: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 25),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xB906202B),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: const Color(0x66E8C477)),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 5))],
              ),
              child: Row(
                children: [
                  HappyNetworkAvatar(
                    url: ownerAvatar,
                    size: 40,
                    backgroundColor: const Color(0xFF31515A),
                    fallback: const Icon(Icons.person_rounded, color: Colors.white70),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_roomName, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text('${_ownerName.isEmpty ? 'صاحب الغرفة' : _ownerName}  ·  ID: $_roomCode',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFFD9D2C7), fontSize: 9)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0x33E8C477),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: const Color(0x77E8C477)),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFD18A), size: 15),
                      SizedBox(width: 3),
                      Text('HOST', style: TextStyle(color: Color(0xFFFFE0A8), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: .5)),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _referenceSeatGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 11, 8, 8),
        decoration: BoxDecoration(
          color: const Color(0x55001822),
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: const Color(0x33FFFFFF)),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 18, offset: Offset(0, 7))],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isAndroid = Theme.of(context).platform == TargetPlatform.android;
            // LayoutBuilder already receives the width inside the card padding.
            // Calculate the real grid tile width so every Android phone size fits.
            final tileWidth = (constraints.maxWidth - 24) / 4;
            final micSize = isAndroid
                ? (tileWidth * .62).clamp(34.0, 52.0)
                : (tileWidth * .78).clamp(48.0, 70.0);
            Widget seatGrid(int firstSeat) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 4,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: isAndroid ? 14 : 7,
                crossAxisSpacing: 8,
                mainAxisExtent: isAndroid ? micSize + 42 : null,
                childAspectRatio: isAndroid ? 1 : .78,
              ),
              itemBuilder: (context, index) {
                final number = firstSeat - index;
                final seatCard = _premiumSeatCard(number, micSize);
                if (isAndroid && number >= 5 && number <= 8) {
                  return Transform.translate(
                    offset: const Offset(0, 20),
                    child: seatCard,
                  );
                }
                return seatCard;
              },
            );
            if (!_roomBattleTeamMode) {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 8,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: isAndroid ? 14 : 7,
                  crossAxisSpacing: 8,
                  mainAxisExtent: isAndroid ? micSize + 42 : null,
                  childAspectRatio: isAndroid ? 1 : .78,
                ),
                itemBuilder: (context, index) {
                  final number = index < 4 ? 4 - index : 8 - (index - 4);
                  final seatCard = _premiumSeatCard(number, micSize);
                  if (isAndroid && number >= 5 && number <= 8) {
                    return Transform.translate(
                      offset: const Offset(0, 20),
                      child: seatCard,
                    );
                  }
                  return seatCard;
                },
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _battleTeamLabel('الفريق الأزرق', const Color(0xFF258BFF)),
                const SizedBox(height: 7),
                seatGrid(4),
                const SizedBox(height: 10),
                _battleTeamLabel('الفريق الأحمر', const Color(0xFFFF4B5C)),
                const SizedBox(height: 7),
                seatGrid(8),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _battleTeamLabel(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
    decoration: BoxDecoration(
      color: color.withOpacity(.16),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withOpacity(.75), width: 1.2),
    ),
    child: Text(label, textAlign: TextAlign.center,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)),
  );

  Widget _premiumSeatCard(int number, double micSize) {
    final seat = _seatAt(number);
    final occupied = seat != null;
    final mine = _mySeat == number;
    final name = (seat?['name'] ?? '').toString();
    final avatar = (seat?['avatar'] ?? seat?['avatarUrl'] ?? seat?['photoUrl'] ?? '').toString();
    final locked = occupied && !mine;
    return GestureDetector(
      onTap: (!occupied || mine) && !_isChangingSeat ? () => _selectSeat(number) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                width: micSize, height: micSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xCC092A35),
                  gradient: avatar.startsWith('https://') ? null : LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: occupied
                      ? const [Color(0xFF42727A), Color(0xFF123B49)]
                      : const [Color(0xAA164552), Color(0xAA092B38)],
                  ),
                  border: Border.all(
                    color: _roomBattleTeamMode
                        ? (number <= 4 ? const Color(0xFF258BFF) : const Color(0xFFFF4B5C))
                        : mine ? Colors.transparent : occupied ? const Color(0xFF9BC6C8) : const Color(0x7797B9B8),
                    width: _roomBattleTeamMode ? 2.4 : mine ? 0 : 1.5,
                  ),
                  boxShadow: [BoxShadow(
                    color: _roomBattleTeamMode
                        ? (number <= 4 ? const Color(0x66258BFF) : const Color(0x66FF4B5C))
                        : occupied ? const Color(0x5539A2A5) : const Color(0x22000000),
                    blurRadius: _roomBattleTeamMode ? 15 : 12,
                    offset: const Offset(0, 4),
                  )],
                ),
                child: ClipOval(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (avatar.startsWith('https://') || avatar.startsWith('http://'))
                        HappyNetworkImage(avatar, fit: BoxFit.cover),
                      if (!avatar.startsWith('https://') && !avatar.startsWith('http://'))
                        Center(
                          child: occupied
                            ? Text(name.isEmpty ? '؟' : name.characters.first,
                                style: TextStyle(color: Colors.white, fontSize: micSize * .35, fontWeight: FontWeight.w900))
                            : Icon(Icons.add_rounded, color: const Color(0xFFFFD18A), size: micSize * .40),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: -1, bottom: 0,
                child: Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: occupied ? (mine ? const Color(0xFFFFD98B) : const Color(0xFF17434C)) : const Color(0xFF123B46),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0A303B), width: 2),
                  ),
                  child: Icon(
                    occupied ? (locked ? Icons.mic_off_rounded : Icons.mic_rounded) : Icons.add_rounded,
                    color: occupied && mine ? const Color(0xFF15313A) : const Color(0xFFFFE1A9), size: 11),
                ),
              ),
              if (occupied)
                Positioned(
                  top: -4, left: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFE8C477), borderRadius: BorderRadius.circular(7)),
                    child: Text(mine ? 'أنت' : 'LIVE', style: const TextStyle(color: Color(0xFF26343A), fontSize: 7, fontWeight: FontWeight.w900)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(occupied ? (mine ? 'أنت' : name) : 'مقعد $number',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: occupied ? Colors.white : const Color(0xFFD7E4E2), fontSize: 9, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(occupied ? (mine ? 'على المايك' : 'متحدث') : 'اضغط للصعود',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFB6CDCB), fontSize: 7.5)),
        ],
      ),
    );
  }

  Widget _referenceAudienceBar() {
    final occupiedCount = List<int>.generate(8, (index) => index + 1)
        .where((number) => _seatAt(number) != null).length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Container(
        height: 43,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: const Color(0xB806202B),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0x44FFFFFF)),
        ),
        child: Row(children: [
          const Icon(Icons.circle, color: Color(0xFF69E0A7), size: 7),
          const SizedBox(width: 6),
          const Text('مباشر', style: TextStyle(color: Color(0xFFD6F2E8), fontSize: 10, fontWeight: FontWeight.w900)),
          const SizedBox(width: 12),
          Container(width: 1, height: 20, color: const Color(0x44FFFFFF)),
          const SizedBox(width: 10),
          const Icon(Icons.people_alt_rounded, color: Color(0xFFFFD18A), size: 17),
          const SizedBox(width: 5),
          Text('$occupiedCount / 8', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
          const Spacer(),
          const Icon(Icons.headset_mic_rounded, color: Color(0xFFB8D8D8), size: 16),
          const SizedBox(width: 5),
          const Text('غرفة صوتية', style: TextStyle(color: Color(0xFFD7E5E4), fontSize: 9, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          InkWell(onTap: _copyRoomCode, child: const Icon(Icons.copy_rounded, color: Color(0xFFFFD18A), size: 16)),
        ]),
      ),
    );
  }

  Widget _referenceMessage(String text, IconData icon) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xCC062631),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
              border: Border.all(color: const Color(0x44D6E6E2)),
              boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Text(text, textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.4, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(width: 7),
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xCC174653),
            border: Border.all(color: const Color(0x77D8C18E))),
          child: Icon(icon, color: const Color(0xFFFFD18A), size: 17),
        ),
      ],
    );
  }

  Widget _referenceSideTile(IconData icon, String label, {VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: 56, height: 58,
          decoration: BoxDecoration(
            color: const Color(0xD9082934),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0x66D7C18D)),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4))],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: const Color(0xFFFFD18A), size: 22),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        _roundAction(
          icon: Icons.arrow_forward_ios_rounded,
          onTap: () { if (mounted) setState(() => _showRoomActions = !_showRoomActions); },
          tooltip: 'خيارات الغرفة',
        ),
        const SizedBox(width: 8),
        Expanded(child: Align(alignment: Alignment.centerRight, child: _profileHeader())),
        const SizedBox(width: 8),
        RoomLevelChip(
          data: RoomLevelData(
            level: _roomExperienceLevel,
            roomName: (widget.room['name'] ?? widget.room['roomName'] ?? '').toString(),
            roomId: (widget.room['room_code'] ?? widget.room['roomId'] ?? widget.room['id'] ?? '').toString(),
            exp: _roomExperienceExp,
            nextLevelExp: _roomExperienceNextLevelExp,
          ),
        ),
      ],
    );
  }

  void _minimizeRoom() {
    if (_isMinimized) return;
    setState(() {
      _showRoomActions = false;
      _isMinimized = true;
      _miniOffset = Offset(18, MediaQuery.of(context).padding.top + 90);
    });
    final overlay = Overlay.of(context, rootOverlay: true);
    _miniOverlayEntry = OverlayEntry(
      builder: (overlayContext) => Positioned.fill(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = MediaQuery.of(overlayContext).padding;
            const miniWidth = 156.0;
            const miniHeight = 158.0;
            final maxLeft = (constraints.maxWidth - miniWidth).clamp(0.0, constraints.maxWidth).toDouble();
            final minTop = padding.top;
            final maxTop = (constraints.maxHeight - miniHeight - padding.bottom).clamp(minTop, constraints.maxHeight).toDouble();
            final left = _miniOffset.dx.clamp(0.0, maxLeft).toDouble();
            final top = _miniOffset.dy.clamp(minTop, maxTop).toDouble();
            return Stack(children: [
              Positioned(
                left: left,
                top: top,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    _miniOffset = Offset(
                      (_miniOffset.dx + details.delta.dx).clamp(0.0, maxLeft).toDouble(),
                      (_miniOffset.dy + details.delta.dy).clamp(minTop, maxTop).toDouble(),
                    );
                    _miniOverlayEntry?.markNeedsBuild();
                  },
                  child: _miniRoomWindow(),
                ),
              ),
            ]);
          },
        ),
      ),
    );
    overlay.insert(_miniOverlayEntry!);
  }

  void _restoreRoom() {
    _miniOverlayEntry?.remove();
    _miniOverlayEntry = null;
    if (mounted) {
      final navigator = Navigator.of(context);
      final route = _roomRoute;
      if (route != null && route.isActive) {
        navigator.popUntil((candidate) => identical(candidate, route));
      }
      setState(() => _isMinimized = false);
    }
  }

  Widget _roomActionSheet() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 13),
      decoration: BoxDecoration(
        color: const Color(0xF21A1422),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
        border: Border.all(color: const Color(0x88E8C477)),
        boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 22, offset: Offset(0, 9))],
      ),
      child: Row(children: [
        Expanded(child: _roomActionButton(
          icon: Icons.picture_in_picture_alt_rounded,
          label: 'تصغير الغرفة',
          color: _purple,
          onTap: _minimizeRoom,
        )),
        const SizedBox(width: 10),
        Expanded(child: _roomActionButton(
          icon: Icons.logout_rounded,
          label: 'إغلاق الغرفة',
          color: const Color(0xFFBD5361),
          onTap: _closeRoom,
        )),
      ]),
    );
  }

  Widget _roomActionButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return Material(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: _isClosingRoom ? null : onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          height: 72,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), border: Border.all(color: color.withOpacity(0.55))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color, size: 25),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }

  Widget _miniRoomWindow() {    return Material(
      color: Colors.transparent,      child: InkWell(
        onTap: _restoreRoom,        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 156,
          height: 158,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xF2171220),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _gold, width: 1.4),
            boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 20, offset: Offset(0, 8))],
            image: _imageUrl == null ? null : DecorationImage(
              image: NetworkImage(_imageUrl!), fit: BoxFit.cover,
              colorFilter: const ColorFilter.mode(Color(0xAA09070D), BlendMode.darken),
            ),
            gradient: _imageUrl == null ? const LinearGradient(
              begin: Alignment.topRight, end: Alignment.bottomLeft,
              colors: [Color(0xFF49305D), Color(0xFF17121F)],
            ) : null,
          ),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.graphic_eq_rounded, color: _gold, size: 17),
              const SizedBox(width: 5),
              const Expanded(child: Text('الغرفة المصغرة', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800))),
              GestureDetector(
                onTap: _closeRoom,
                child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.close_rounded, color: Colors.white, size: 19)),
              ),
            ]),
            const Spacer(),
            Text(_roomName, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _gold, fontSize: 13, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('ID: $_roomCode', style: const TextStyle(color: Colors.white70, fontSize: 9)),
            const Spacer(),
            Container(
              height: 29, width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _purple, borderRadius: BorderRadius.circular(9)),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.open_in_full_rounded, size: 13, color: Colors.white),
                SizedBox(width: 5),
                Text('تكبير الغرفة', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _closeRoom() async {
    if (_isClosingRoom) return;
    setState(() { _isClosingRoom = true; _showRoomActions = false; });
    try {
      if (_mySeat != null) await _leaveSeat();
      if (mounted) {
        final route = _roomRoute;
        final navigator = Navigator.of(context);
        if (route != null && route.isActive) {
          navigator.removeRoute(route);
        } else {
          navigator.maybePop();
        }
      }
    } finally {
      if (mounted) setState(() => _isClosingRoom = false);
    }
  }

  Widget _roundAction({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    Color iconColor = Colors.white,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: iconColor, size: 23, textDirection: TextDirection.ltr),
          ),
        ),      ),
    );
  }

  Widget _profileHeader() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 110, maxWidth: 170),
      child: IntrinsicWidth(
        child: Container(
          height: 36,
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: const Color(0xCC17121F),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              bottomLeft: Radius.circular(18),
            ),
            border: Border.all(color: const Color(0x66E8C477), width: 1),
            boxShadow: const [
              BoxShadow(color: Color(0x22100A18), blurRadius: 12, offset: Offset(0, 4)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.translate(
                offset: const Offset(0, 0),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF30213D),
                    image: _imageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(_imageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _imageUrl == null
                      ? const Icon(Icons.image_outlined, color: _gold, size: 18)
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Transform.translate(
                      offset: const Offset(0, -2),
                      child: Text(
                        _roomName,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 10.5,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      'ID: $_roomCode',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.62),
                        fontSize: 8.5,
                        height: 1.1,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF21172B),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0x88E8C477)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people_alt_rounded, color: _gold, size: 14),
          const SizedBox(width: 6),
          Text(
            '$count / 8',
            style: const TextStyle(color: _gold, fontSize: 12, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _microphoneStage() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileWidth = (constraints.maxWidth - 24) / 4;
          final micSize = tileWidth.clamp(52.0, 74.0);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 8,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 12,
              crossAxisSpacing: 8,
              childAspectRatio: 0.72,
            ),
            itemBuilder: (context, index) => _micCard(index + 1, micSize),
          );
        },
      ),
    );
  }

  Widget _roomNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF17121E),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0x334E3B60)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: _gold, size: 17),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'المقاعد تتحدث تلقائيًا. الصوت المباشر لم يتم تفعيله بعد.',
              style: TextStyle(color: _muted, fontSize: 11, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomControl() {
    if (_mySeat != null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 11, 16, 13),
        decoration: const BoxDecoration(
          color: Color(0xFF15101C),
          border: Border(top: BorderSide(color: Color(0x665F4775))),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [Color(0xFFD9A93C), Color(0xFF56347A)]),
              ),
              child: const Icon(Icons.mic_rounded, color: Colors.white, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'أنت على المايك $_mySeat',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
            FilledButton(
              onPressed: _isChangingSeat ? null : _leaveSeat,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF38213F),
                foregroundColor: const Color(0xFFFFD98B),
                padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                  side: const BorderSide(color: Color(0x77E8C477)),
                ),
              ),
              child: const Text('مغادرة المايك', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _micCard(int number, double micSize) {
    final seat = _seatAt(number);
    final occupied = seat != null;
    final mine = _mySeat == number;
    final name = (seat?['name'] ?? '').toString();
    final isLocked = occupied && !mine;
    final isMuted = seat?['isMuted'] == true;
    final speakerUid = int.tryParse((seat?['userCode'] ?? '').toString());
    final voiceLevel = speakerUid == null ? 0.0 : (_speakerLevels[speakerUid] ?? 0.0);
    final isWaveVisible = occupied && !isMuted && speakerUid != null && speaking.contains(speakerUid);
    return InkWell(
      onTap: (!occupied || mine) && !_isChangingSeat ? () => _selectSeat(number) : null,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              SizedBox(
                width: micSize,
                height: micSize,
                child: OverflowBox(
                  alignment: Alignment.center,
                  minWidth: micSize * 1.7,
                  maxWidth: micSize * 1.7,
                  minHeight: micSize * 1.7,
                  maxHeight: micSize * 1.7,
                  child: SpeakingWave(
                    active: isWaveVisible,
                    size: micSize,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: micSize,
                      height: micSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: mine
                              ? const [Color(0xFFB98AF0), Color(0xFF65408E)]
                              : occupied
                                  ? const [Color(0xFF67477C), Color(0xFF30213D)]
                                  : const [Color(0x665D7D82), Color(0x553C626A)],
                        ),
                        border: Border.all(
                          color: mine ? Colors.transparent : occupied ? const Color(0xFFD9A93C) : const Color(0x665F4775),
                          width: mine ? 0 : 1.5,
                        ),
                        boxShadow: mine
                            ? const [BoxShadow(color: Color(0x559B63D9), blurRadius: 15, spreadRadius: 1)]
                            : const [],
                      ),
                      child: Center(
                        child: occupied
                            ? Text(
                                name.isEmpty ? '؟' : name.characters.first,
                                style: TextStyle(color: Colors.white, fontSize: micSize * 0.34, fontWeight: FontWeight.w900),
                              )
                            : Icon(Icons.add_rounded, color: _gold.withOpacity(0.9), size: micSize * 0.46),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -2,
                right: -3,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: mine ? _gold : occupied ? const Color(0xFFD9A93C) : const Color(0xFF29212F),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF100C15), width: 2),
                  ),
                  child: Icon(
                    occupied ? (isLocked ? Icons.mic_off_rounded : Icons.mic_rounded) : Icons.add_rounded,
                    color: mine ? const Color(0xFF21152B) : Colors.white,
                    size: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$number',
            style: TextStyle(color: mine ? _gold : Colors.white.withOpacity(0.78), fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              occupied ? (mine ? 'أنت هنا' : name) : 'متاح',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: mine ? const Color(0xFFFFD98B) : occupied ? _muted : const Color(0xFFB9A8C8),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roomHeader() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(23),
      child: SizedBox(
        height: 174,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_imageUrl != null)
              HappyNetworkImage(
                _imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF30213C)),
              )
            else
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [Color(0xFF59366E), Color(0xFF21152F), Color(0xFF120F19)],
                  ),
                ),
                child: Center(child: Icon(Icons.graphic_eq_rounded, color: Color(0x66E8C477), size: 76)),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x11000000), Color(0xEE09070D)],
                  stops: [0.15, 1],
                ),
              ),
            ),
            Positioned(
              right: 15,
              left: 15,
              bottom: 15,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      color: const Color(0xCC21172B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0x88E8C477)),
                    ),
                    child: const Icon(Icons.headphones_rounded, color: _gold, size: 25),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_roomName, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, shadows: [Shadow(color: Colors.black, blurRadius: 8)])),
                        if ((widget.room['description'] ?? '').toString().trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(widget.room['description'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFFD8CEDF), fontSize: 11, height: 1.4)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roomCodeCard() {
    return InkWell(
      onTap: _copyRoomCode,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF17121E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x554F3B60)),
        ),
        child: Row(
          children: [
            const Icon(Icons.tag_rounded, color: _gold, size: 18),
            const SizedBox(width: 8),
            const Text('رقم الغرفة', style: TextStyle(color: _muted, fontSize: 12)),
            const Spacer(),
            Text(_roomCode.length == 8 ? _roomCode : '--------',
              style: const TextStyle(color: _gold, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(width: 8),
            const Icon(Icons.copy_rounded, color: _purple, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _errorPanel() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF241820), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Expanded(child: Text('تعذر تحديث المقاعد. حاول إعادة الاتصال.', style: TextStyle(color: Colors.white, fontSize: 12))),
          TextButton(onPressed: _refreshSeats, child: const Text('إعادة المحاولة', style: TextStyle(color: _gold))),
        ],
      ),
    );
  }
}


class SpeakingWave extends StatefulWidget {
  final bool active;
  final double size; // قطر الصورة
  final Widget child;

  const SpeakingWave({
    super.key,
    required this.active,
    required this.child,
    this.size = 60,
  });

  @override
  State<SpeakingWave> createState() => _SpeakingWaveState();
}

class _SpeakingWaveState extends State<SpeakingWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  static const wavePurple = Color(0xFFD65BEA);

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant SpeakingWave old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // حلقة رفيعة: تبدأ قريبة من حافة الصورة وتكبر وتتلاشى
  Widget _ring(double delay) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = (_c.value + delay) % 1.0;
        final s = widget.size * (1.18 + t * 0.46);
        return Opacity(
          opacity: widget.active ? (1 - t) * 0.88 : 0,
          child: Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: wavePurple, width: 1.25),
              boxShadow: const [
                BoxShadow(color: Color(0x665D1C86), blurRadius: 5, spreadRadius: 0.4),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final box = widget.size * 1.8;
    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          _ring(0.0),
          _ring(0.5),
          widget.child,
        ],
      ),
    );
  }
}

class _VoiceGlowPainter extends CustomPainter {
  const _VoiceGlowPainter({required this.level});
  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final strength = level.clamp(0.0, 1.0);
    final radius = size.shortestSide * 0.49 + 2 + strength * 5;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 + strength * 1.5
      ..color = const Color(0xFFE8C477).withOpacity(0.28 + strength * 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + strength * 4);
    canvas.drawCircle(center, radius, paint);
    final second = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = const Color(0xFFB98AF0).withOpacity(0.22 + strength * 0.38);
    canvas.drawCircle(center, radius + 4 + strength * 3, second);
  }

  @override
  bool shouldRepaint(covariant _VoiceGlowPainter oldDelegate) => (oldDelegate.level - level).abs() > 0.035;
}

class _RoomMedal extends StatelessWidget {
  const _RoomMedal();
  @override
  Widget build(BuildContext context) => Container(
    width: 34, height: 34,
    decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFE7E8E8),
      border: Border.all(color: const Color(0xFFB8C6C8), width: 2)),
    child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFB9A078), size: 22),
  );
}

class _TopTopRoomBackdrop extends StatelessWidget {
  const _TopTopRoomBackdrop();
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _TopTopMountainPainter(),
    child: const SizedBox.expand(),
  );
}

class _TopTopMountainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final sky = Paint()..shader = const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFF042B36), Color(0xFF075B68), Color(0xFF078B98), Color(0xFF06212C)],
      stops: [0, 0.47, 0.68, 1],
    ).createShader(rect);
    canvas.drawRect(rect, sky);
    final stars = Paint()..color = const Color(0x99D5F3F1);
    for (var i = 0; i < 240; i++) {
      final x = (i * 73.13) % size.width;
      final y = (i * 47.71) % (size.height * 0.72);
      canvas.drawCircle(Offset(x, y), i % 11 == 0 ? 1.4 : 0.65, stars);
    }
    final glow = Paint()..shader = RadialGradient(
      colors: [const Color(0x6600D4D1), const Color(0x0000D4D1)],
    ).createShader(Rect.fromCircle(center: Offset(size.width * .83, size.height * .63), radius: size.width * .7));
    canvas.drawRect(rect, glow);
    final ridge1 = Path()
      ..moveTo(0, size.height * .78)..lineTo(size.width * .23, size.height * .72)
      ..lineTo(size.width * .42, size.height * .76)..lineTo(size.width * .58, size.height * .69)
      ..lineTo(size.width * .78, size.height * .74)..lineTo(size.width, size.height * .68)
      ..lineTo(size.width, size.height)..lineTo(0, size.height)..close();
    canvas.drawPath(ridge1, Paint()..color = const Color(0xFF092B38));
    final mountain = Path()
      ..moveTo(size.width * .30, size.height)..lineTo(size.width * .49, size.height * .72)
      ..lineTo(size.width * .56, size.height * .70)..lineTo(size.width * .64, size.height * .75)
      ..lineTo(size.width * .78, size.height)..close();
    canvas.drawPath(mountain, Paint()..color = const Color(0xFF061D2A));
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RoomAuroraBackground extends StatelessWidget {
  const _RoomAuroraBackground();

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
    const DecoratedBox(decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF052D3A), Color(0xFF08798A), Color(0xFF052B39), Color(0xFF06131F)],
        stops: [0, 0.42, 0.68, 1]),
    )),
    CustomPaint(painter: _StarsPainter()),
    Align(alignment: const Alignment(0.1, 0.92), child: Container(
      height: 190, decoration: BoxDecoration(
        gradient: RadialGradient(radius: 1.2, colors: [Color(0x6600B6C4), Colors.transparent]),
      ),
    )),
  ]);
}

class _StarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 130; i++) {
      final isGold = i % 4 == 0;
      final paint = Paint()
        ..color = isGold
            ? const Color(0xFFE6C87A).withOpacity(0.22)
            : Colors.white.withOpacity(0.18);
      final x = (i * 53.7) % size.width;
      final y = (i * 91.3) % size.height;
      canvas.drawCircle(Offset(x, y), isGold ? 1.2 : 0.8, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}