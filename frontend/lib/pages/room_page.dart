import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

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
  DateTime _lastHeartbeat = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isLoading = true;
  bool _isRefreshing = false;
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
  void initState() {
    super.initState();
    _refreshSeats();
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _refreshSeats();
      if (_mySeat != null && DateTime.now().difference(_lastHeartbeat).inSeconds >= 15) {
        _sendHeartbeat();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
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
      final rawSeats = data['seats'];
      final seats = rawSeats is List
          ? rawSeats.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _seats = seats;
        _mySeat = data['mySeat'] is num ? (data['mySeat'] as num).toInt() : null;
        final owner = data['owner'];
        if (owner is Map && owner['name'] != null) _ownerName = owner['name'].toString();
        _isLoading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      if (_isLoading) setState(() { _isLoading = false; _loadError = 'تعذر الاتصال بالغرفة، تحقق من الإنترنت'; });
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _sendHeartbeat() async {
    _lastHeartbeat = DateTime.now();
    try {
      await http.post(_seatsUri, headers: _headers, body: jsonEncode({'heartbeat': true}))
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
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
      if (response.statusCode == 409) {
        _showMessage('هذا المايك مشغول، اختر مايكًا آخر');
      } else if (response.statusCode != 200 || data is! Map || data['ok'] != true) {
        _showMessage('تعذر تغيير المايك، حاول مرة أخرى');
      }
      await _refreshSeats();
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
      if (response.statusCode != 200) _showMessage('تعذر مغادرة المايك');
      await _refreshSeats();
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
        backgroundColor: _background,
        body: Stack(
          children: [
            const Positioned.fill(child: _StarBackground()),
            Positioned.fill(
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
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      children: [
                        _topBar(),
                        const SizedBox(height: 26),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 5),
                                  Text(
                                    'اختر المايك المناسب وشاركنا الحديث',
                                    style: TextStyle(color: _muted, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            if (_isLoading || _isChangingSeat) ...[
                              const SizedBox(width: 9),
                              const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.7,
                                  color: _gold,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 17),
                        if (_loadError != null && _seats.isEmpty) _errorPanel(),
                        _microphoneStage(),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _countBadge(occupiedCount),
                        ),
                        const SizedBox(height: 20),
                        _hostPanel(),
                        const SizedBox(height: 13),
                        _roomNotice(),
                      ],
                    ),
                  ),
                  _bottomControl(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _profileHeader(),
            const SizedBox(width: 8),
            _roundAction(
              icon: Icons.arrow_forward_ios_rounded,
              onTap: () => Navigator.of(context).maybePop(),
              tooltip: 'رجوع',
            ),
          ],
        ),
      ),
    );
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
            child: Icon(icon, color: iconColor, size: 20, textDirection: TextDirection.ltr),
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
                offset: const Offset(5, 0),
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

  Widget _hostPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF30213A), Color(0xFF19131F)],
        ),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0x88E8C477)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [Color(0xFFE8C477), Color(0xFF9D7137)]),
            ),
            child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFF2A1D24), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _ownerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                const Text('مضيف الغرفة', style: TextStyle(color: _gold, fontSize: 10, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const Icon(Icons.verified_rounded, color: _gold, size: 20),
        ],
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 13, 18, 14),
      decoration: const BoxDecoration(
        color: Color(0xFF15101C),
        border: Border(top: BorderSide(color: Color(0x334E3B60))),
      ),
      child: const Text(
        'اضغط على أحد المقاعد الفارغة للانضمام إلى الحديث',
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
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

  Widget _ownerCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2A1D34), Color(0xFF1B1423)]),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0x88E8C477)),
      ),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [Color(0xFFE8C477), Color(0xFF9D7137)]),
            ),
            child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFF2A1D24), size: 23),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_ownerName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                const Text('مضيف الغرفة', style: TextStyle(color: _gold, fontSize: 10, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const Icon(Icons.verified_rounded, color: _gold, size: 19),
        ],
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
