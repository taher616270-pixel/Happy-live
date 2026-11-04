import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

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
  static const _purple = Color(0xFF9B63D9);
  static const _gold = Color(0xFFE8C477);
  static const _muted = Color(0xFFAAA2B5);
  static const String _apiBase = 'https://happy-live-api.taher616270.workers.dev/api/v1';

  Timer? _refreshTimer;
  Timer? _chatRefreshTimer;
  final TextEditingController _messageController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final List<Map<String, dynamic>> _messages = [];
  Uint8List? _pendingChatImage;
  String _pendingChatImageName = 'room-chat.jpg';
  bool _chatLoading = true;
  bool _chatSending = false;
  bool _chatRefreshing = false;
  DateTime _lastHeartbeat = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isMinimized = false;
  bool _showRoomActions = false;
  bool _isClosingRoom = false;
  Offset _miniOffset = const Offset(18, 170);
  OverlayEntry? _miniOverlayEntry;
  Route<dynamic>? _roomRoute;
  bool _isChangingSeat = false;
  String? _loadError;
  int? _mySeat;
  String _ownerName = 'صاحب الغرفة';
  List<Map<String, dynamic>> _seats = [];

  String get _roomId => (widget.room['id'] ?? '').toString();
  String get _roomName => (widget.room['name'] ?? 'غرفة صوتية').toString();
  String get _roomCode => (widget.room['roomCode'] ?? '').toString();
  String? get _imageUrl {
    final value = widget.room['imageUrl']?.toString();
    return value != null && value.startsWith('https://') ? value : null;
  }

  Uri get _seatsUri => Uri.parse('$_apiBase/rooms/${Uri.encodeComponent(_roomId)}/seats');
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
    _refreshSeats();
    _startChatSession();
    // Refresh shared seats twice per second so other members appear almost immediately.
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _refreshSeats();
      if (_mySeat != null && DateTime.now().difference(_lastHeartbeat).inSeconds >= 15) {
        _sendHeartbeat();
      }
    });
  }

  @override
  void dispose() {
    _miniOverlayEntry?.remove();
    _miniOverlayEntry = null;
    _refreshTimer?.cancel();
    _chatRefreshTimer?.cancel();
    _messageController.dispose();
    _leaveChatSession();
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
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      final response = await http.get(_seatsUri, headers: _headers).timeout(const Duration(seconds: 8));
      final data = jsonDecode(response.body);
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
    }
  }

  void _applySeatData(Map<String, dynamic> data) {
    final rawSeats = data['seats'];
    final seats = rawSeats is List
        ? rawSeats.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
        : <Map<String, dynamic>>[];
    final nextMySeat = data['mySeat'] is num ? (data['mySeat'] as num).toInt() : null;
    final owner = data['owner'];
    final nextOwnerName = owner is Map && owner['name'] != null
        ? owner['name'].toString()
        : _ownerName;
    final changed = jsonEncode(_seats) != jsonEncode(seats) ||
        _mySeat != nextMySeat ||
        _ownerName != nextOwnerName ||
        _isLoading ||
        _loadError != null;
    if (!mounted || !changed) return;
    setState(() {
      _seats = seats;
      _mySeat = nextMySeat;
      _ownerName = nextOwnerName;
      _isLoading = false;
      _loadError = null;
    });
  }

  Future<void> _sendHeartbeat() async {
    _lastHeartbeat = DateTime.now();
    try {
      await http.post(_seatsUri, headers: _headers, body: jsonEncode({'heartbeat': true}))
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Uri get _messagesUri => Uri.parse('$_apiBase/rooms/${Uri.encodeComponent(_roomId)}/messages');
  Uri get _chatSessionUri => Uri.parse('$_apiBase/rooms/${Uri.encodeComponent(_roomId)}/chat-session');
  bool _chatSessionReady = false;

  Future<void> _startChatSession() async {
    if (_roomId.isEmpty || widget.accessToken.isEmpty) return;
    try {
      final response = await http.post(
        _chatSessionUri,
        headers: _headers,
        body: jsonEncode({'action': 'join'}),
      ).timeout(const Duration(seconds: 8));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data is! Map || data['ok'] != true) {
        if (mounted) setState(() => _chatLoading = false);
        return;
      }
      _chatSessionReady = true;
      await _refreshMessages();
      if (mounted) {
        _chatRefreshTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshMessages());
      }
    } catch (_) {
      if (mounted) setState(() => _chatLoading = false);
    }
  }

  Future<void> _leaveChatSession() async {
    if (!_chatSessionReady) return;
    _chatSessionReady = false;
    try {
      await http.post(
        _chatSessionUri,
        headers: _headers,
        body: jsonEncode({'action': 'leave'}),
      ).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> _refreshMessages() async {
    if (!_chatSessionReady || _chatRefreshing || _roomId.isEmpty || widget.accessToken.isEmpty) return;
    _chatRefreshing = true;
    try {
      final response = await http.get(_messagesUri, headers: _headers).timeout(const Duration(seconds: 8));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map && data['ok'] == true && data['messages'] is List) {
        final next = (data['messages'] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        if (mounted && jsonEncode(_messages) != jsonEncode(next)) {
          setState(() {
            _messages
              ..clear()
              ..addAll(next);
            _chatLoading = false;
          });
        } else if (mounted && _chatLoading) {
          setState(() => _chatLoading = false);
        }
      } else if (mounted && _chatLoading) {
        setState(() => _chatLoading = false);
      }
    } catch (_) {
      if (mounted && _chatLoading) setState(() => _chatLoading = false);
    } finally {
      _chatRefreshing = false;
    }
  }

  Future<void> _pickChatImage() async {
    if (_chatSending) return;
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 86,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        _showMessage('حجم الصورة يجب ألا يتجاوز 5 ميجابايت');
        return;
      }
      if (!mounted) return;
      setState(() {
        _pendingChatImage = bytes;
        _pendingChatImageName = picked.name.isEmpty ? 'room-chat.jpg' : picked.name;
      });
    } catch (_) {
      _showMessage('تعذر اختيار الصورة');
    }
  }

  Future<String> _uploadChatImage() async {
    final bytes = _pendingChatImage;
    if (bytes == null) return '';
    final authResponse = await http.get(
      Uri.parse('$_apiBase/imagekit/auth'),
      headers: {'Authorization': 'Bearer ${widget.accessToken}'},
    ).timeout(const Duration(seconds: 15));
    if (authResponse.statusCode != 200) throw Exception('image_auth_failed');
    final auth = jsonDecode(authResponse.body) as Map<String, dynamic>;
    final upload = http.MultipartRequest(
      'POST',
      Uri.parse('https://upload.imagekit.io/api/v1/files/upload'),
    );
    upload.fields.addAll({
      'fileName': 'room-chat-${DateTime.now().millisecondsSinceEpoch}-$_pendingChatImageName',
      'publicKey': auth['publicKey'].toString(),
      'token': auth['token'].toString(),
      'expire': auth['expire'].toString(),
      'signature': auth['signature'].toString(),
      'useUniqueFileName': 'true',
      'folder': '/happy-live/room-chat',
    });
    upload.files.add(http.MultipartFile.fromBytes('file', bytes, filename: _pendingChatImageName));
    final streamed = await upload.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('image_upload_failed');
    final result = jsonDecode(response.body) as Map<String, dynamic>;
    final url = result['url']?.toString() ?? '';
    if (!url.startsWith('https://')) throw Exception('invalid_image_url');
    return url;
  }

  Future<void> _sendRoomMessage() async {
    if (_chatSending || !_chatSessionReady) return;
    final message = _messageController.text.trim();
    if (message.isEmpty && _pendingChatImage == null) return;
    if (message.length > 1000) {
      _showMessage('الرسالة طويلة جدًا');
      return;
    }
    setState(() => _chatSending = true);
    try {
      final imageUrl = await _uploadChatImage();
      final response = await http.post(
        _messagesUri,
        headers: _headers,
        body: jsonEncode({'message': message, 'imageUrl': imageUrl}),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map && data['ok'] == true) {
        _messageController.clear();
        if (mounted) setState(() => _pendingChatImage = null);
        await _refreshMessages();
      } else {
        _showMessage(response.statusCode == 401 ? 'انتهت جلسة الدخول' : 'تعذر إرسال الرسالة');
      }
    } catch (_) {
      _showMessage('تعذر إرسال الرسالة أو الصورة، تحقق من الإنترنت');
    } finally {
      if (mounted) setState(() => _chatSending = false);
    }
  }

  Widget _roomMessagesBehindMics() {
    if (_messages.isEmpty) {
      return const SizedBox.shrink();
    }
    final visibleCount = _messages.length > 8 ? 8 : _messages.length;
    return IgnorePointer(
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
          stops: [0.0, 0.18, 0.82, 1.0],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          reverse: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
          itemCount: visibleCount,
          itemBuilder: (context, index) {
            final item = _messages[_messages.length - 1 - index];
            final mine = item['isMe'] == true;
            final imageUrl = item['imageUrl']?.toString() ?? '';
            final message = item['message']?.toString() ?? '';
            return Align(
              alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 190),
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: (mine ? const Color(0xFF67477C) : const Color(0xFF292131)).withOpacity(0.48),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: const Color(0x55E8C477)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item['name']?.toString() ?? 'مستخدم',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _gold, fontSize: 9, fontWeight: FontWeight.w800),
                    ),
                    if (message.isNotEmpty)
                      Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 10, height: 1.25),
                      ),
                    if (imageUrl.startsWith('https://'))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            imageUrl,
                            width: 82,
                            height: 42,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _roomChatComposer() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_pendingChatImage != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(_pendingChatImage!, width: 58, height: 58, fit: BoxFit.cover),
                ),
                const SizedBox(width: 8),
                const Expanded(child: Text('الصورة جاهزة للإرسال', style: TextStyle(color: _muted, fontSize: 11))),
                IconButton(
                  tooltip: 'إزالة الصورة',
                  onPressed: _chatSending ? null : () => setState(() => _pendingChatImage = null),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                ),
              ],
            ),
          ],
          Row(
            children: [
              IconButton(
                tooltip: 'إرفاق صورة',
                onPressed: _chatSending ? null : _pickChatImage,
                icon: const Icon(Icons.image_outlined, color: _gold),
              ),
              Expanded(
                child: TextField(
                  controller: _messageController,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 1000,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'اكتب رسالة...',
                    hintStyle: const TextStyle(color: _muted, fontSize: 11),
                    counterText: '',
                    filled: true,
                    fillColor: const Color(0xFF17121E),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: Color(0x445F4775))),
                  ),
                  onSubmitted: (_) => _sendRoomMessage(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'إرسال',
                onPressed: _chatSending ? null : _sendRoomMessage,
                icon: _chatSending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _gold))
                    : const Icon(Icons.send_rounded, color: _gold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _microphoneStageWithMessages() {
    return Stack(
      children: [
        Positioned.fill(child: _roomMessagesBehindMics()),
        _microphoneStage(),
      ],
    );
  }

  Future<void> _copyRoomCode() async {
    if (_roomCode.length != 8) return;
    await Clipboard.setData(ClipboardData(text: _roomCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ رقم الغرفة'), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _selectSeat(int seatNumber) async {
    if (_isChangingSeat) return;
    final current = _seatAt(seatNumber);
    final occupiedByOther = current != null && current['isMe'] != true;
    if (occupiedByOther) return;

    setState(() => _isChangingSeat = true);
    try {
      final target = _mySeat == seatNumber ? null : seatNumber;
      final response = await http.post(
        _seatsUri,
        headers: _headers,
        body: jsonEncode({'seatNumber': target}),
      ).timeout(const Duration(seconds: 8));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map && data['ok'] == true) {
        // The POST response already contains the authoritative seat list.
        // Apply it immediately instead of waiting for an additional GET.
        _applySeatData(Map<String, dynamic>.from(data));
      } else {
        if (response.statusCode == 409) {
          _showMessage('هذا المايك مشغول، اختر مايكًا آخر');
        } else {
          _showMessage('تعذر تغيير المايك، حاول مرة أخرى');
        }
        await _refreshSeats();
      }
    } catch (_) {
      _showMessage('تعذر الاتصال بالخادم، لم يتم تغيير المايك');
    } finally {
      if (mounted) setState(() => _isChangingSeat = false);
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Map<String, dynamic>? _seatAt(int number) {
    for (final seat in _seats) {
      if (seat['seatNumber'] == number) return seat;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final occupiedCount = _seats.length;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _isMinimized ? Colors.transparent : _background,
        body: Stack(
          children: [
            if (!_isMinimized) const Positioned.fill(child: _StarBackground()),
            if (!_isMinimized) Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF171020).withOpacity(0.92),
                      const Color(0xFF0A0910).withOpacity(0.97),
                      _background,
                    ],
                  ),
                ),
              ),
            ),
            if (!_isMinimized) SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      children: [
                        _topBar(),
                        const SizedBox(height: 26),
                        if (_isLoading || _isChangingSeat)
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.7,
                                color: _gold,
                              ),
                            ),
                          ),
                        const SizedBox(height: 17),
                        if (_loadError != null && _seats.isEmpty) _errorPanel(),
                        _microphoneStageWithMessages(),
                        const SizedBox(height: 10),
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _countBadge(occupiedCount),
                        ),
                        const SizedBox(height: 13),
                        _roomNotice(),
                      ],
                    ),
                  ),
                  if (!_isMinimized) _roomChatComposer(),
                  _bottomControl(),
                ],
              ),
            ),
            if (!_isMinimized && _showRoomActions)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (!mounted) return;
                    setState(() => _showRoomActions = false);
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            if (!_isMinimized)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: AnimatedSlide(
                    offset: _showRoomActions ? Offset.zero : const Offset(0, -1.2),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: IgnorePointer(
                      ignoring: !_showRoomActions,
                      child: _roomActionSheet(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Transform.translate(
              offset: const Offset(5, 0),
              child: _roundAction(
                icon: Icons.arrow_forward_ios_rounded,
                onTap: () {
                  if (!mounted) return;
                  setState(() => _showRoomActions = !_showRoomActions);
                },
                tooltip: 'خيارات الغرفة',
              ),
            ),
            Transform.translate(
              offset: const Offset(93, 0),
              child: _profileHeader(),
            ),
          ],
        ),
      ),
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

  Widget _miniRoomWindow() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _restoreRoom,
        borderRadius: BorderRadius.circular(20),
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
      await _leaveChatSession();
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
        ),
      ),
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
      padding: const EdgeInsets.fromLTRB(8, 17, 8, 17),
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
              mainAxisSpacing: 17,
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
                gradient: LinearGradient(colors: [Color(0xFF9B63D9), Color(0xFF56347A)]),
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
    final mine = seat?['isMe'] == true;
    final name = (seat?['name'] ?? '').toString();
    final isLocked = occupied && !mine;
    return InkWell(
      onTap: (!occupied || mine) && !_isChangingSeat ? () => _selectSeat(number) : null,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
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
                            : const [Color(0xFF302638), Color(0xFF19141F)],
                  ),
                  border: Border.all(
                    color: mine ? _gold : occupied ? const Color(0xFF9B63D9) : const Color(0x665F4775),
                    width: mine ? 2.2 : 1.5,
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
              Positioned(
                bottom: -2,
                right: -3,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: mine ? _gold : occupied ? const Color(0xFF9B63D9) : const Color(0xFF29212F),
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
              Image.network(
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


class _StarBackground extends StatelessWidget {
  const _StarBackground();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _StarsPainter());
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
