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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          backgroundColor: _surface,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(_roomName, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _gold, fontWeight: FontWeight.w900)),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  children: [
                    _roomHeader(),
                    const SizedBox(height: 13),
                    _roomCodeCard(),
                    const SizedBox(height: 23),
                    Row(
                      children: [
                        const Text('المايكات', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                        const Spacer(),
                        Text('${_seats.length} / 6 مستخدمين', style: const TextStyle(color: _muted, fontSize: 12)),
                        const SizedBox(width: 8),
                        if (_isLoading || _isChangingSeat)
                          const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.5, color: _gold)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    const Text('اضغط على المايك الفارغ للدخول، واضغط على مايكك لمغادرته',
                      style: TextStyle(color: _muted, fontSize: 11, height: 1.5)),
                    const SizedBox(height: 14),
                    if (_loadError != null && _seats.isEmpty) _errorPanel(),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 6,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.92,
                      ),
                      itemBuilder: (context, index) => _micCard(index + 1),
                    ),
                    const SizedBox(height: 17),
                    _ownerCard(),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: const Color(0xFF120E19),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: const Color(0x554B3A5C)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: _gold, size: 17),
                          SizedBox(width: 8),
                          Expanded(child: Text('المقاعد متزامنة بين المستخدمين. الاتصال الصوتي المباشر لم يُربط بعد.',
                            style: TextStyle(color: _muted, fontSize: 11, height: 1.5))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_mySeat != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  decoration: const BoxDecoration(
                    color: _surface,
                    border: Border(top: BorderSide(color: Color(0x665F4775))),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.mic_rounded, color: _gold, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text('أنت على المايك $_mySeat', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12))),
                      TextButton(
                        onPressed: _isChangingSeat ? null : _leaveSeat,
                        child: const Text('مغادرة المايك', style: TextStyle(color: _gold, fontSize: 12)),
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

  Widget _roomHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x665F4775)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: SizedBox(
              width: 60,
              height: 60,
              child: _imageUrl == null
                  ? const ColoredBox(color: Color(0xFF241A32), child: Icon(Icons.groups_rounded, color: _gold, size: 29))
                  : Image.network(_imageUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF241A32), child: Icon(Icons.groups_rounded, color: _gold, size: 29))),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_roomName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                if ((widget.room['description'] ?? '').toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(widget.room['description'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12, height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roomCodeCard() {
    return InkWell(
      onTap: _copyRoomCode,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF120E19),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x665F4775)),
        ),
        child: Row(
          children: [
            const Icon(Icons.tag_rounded, color: _gold, size: 19),
            const SizedBox(width: 8),
            const Text('رقم الغرفة', style: TextStyle(color: _muted, fontSize: 13)),
            const Spacer(),
            Text(_roomCode.length == 8 ? _roomCode : '--------',
              style: const TextStyle(color: _gold, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(width: 8),
            const Icon(Icons.copy_rounded, color: _purple, size: 17),
          ],
        ),
      ),
    );
  }

  Widget _micCard(int number) {
    final seat = _seatAt(number);
    final occupied = seat != null;
    final mine = seat?['isMe'] == true;
    final name = (seat?['name'] ?? '').toString();
    final canTap = !occupied || mine;
    return InkWell(
      onTap: !canTap || _isChangingSeat ? null : () => _selectSeat(number),
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFF2A1B3C) : _surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: mine ? _gold : occupied ? _purple.withOpacity(0.75) : const Color(0x665F4775),
            width: mine ? 1.6 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: mine ? _purple.withOpacity(0.25) : const Color(0xFF241A32),
                border: Border.all(color: mine ? _gold : occupied ? _purple : const Color(0x665F4775)),
              ),
              child: Center(
                child: occupied
                    ? Text(name.isEmpty ? '؟' : name.characters.first,
                        style: const TextStyle(color: _gold, fontSize: 20, fontWeight: FontWeight.w900))
                    : const Icon(Icons.add_rounded, color: _gold, size: 31),
              ),
            ),
            const SizedBox(height: 8),
            Text('مايك $number', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(occupied ? (mine ? 'أنت هنا' : name) : 'فارغ',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: mine ? _gold : occupied ? _muted : _gold.withOpacity(0.8), fontSize: 10)),
            ),
            if (occupied && !mine)
              const Padding(padding: EdgeInsets.only(top: 3), child: Icon(Icons.lock_rounded, color: _muted, size: 11)),
          ],
        ),
      ),
    );
  }

  Widget _ownerCard() {
    final isOwner = widget.room['ownerId'] != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF211A31),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x88E8C477)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF352541)),
            child: const Icon(Icons.workspace_premium_rounded, color: _gold, size: 24),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_ownerName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(isOwner ? 'صاحب الغرفة • مكانه أسفل المايكات' : 'صاحب الغرفة',
                  style: const TextStyle(color: _muted, fontSize: 11)),
              ],
            ),
          ),
          if (widget.room['ownerId']?.toString() == _seats.firstWhere(
            (seat) => seat['isMe'] == true, orElse: () => <String, dynamic>{})['userId']?.toString())
            const Text('أنت المالك', style: TextStyle(color: _gold, fontSize: 10, fontWeight: FontWeight.w800)),
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
