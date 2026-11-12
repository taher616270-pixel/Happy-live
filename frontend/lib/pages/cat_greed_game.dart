import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// نسخة معاينة محلية لعجلة الأطعمة.
// لا تتصل بخادم الإنتاج ولا تستخدم رصيد الحساب الحقيقي.
Future<void> showCatGreedGame(BuildContext context, {required String accessToken}) {
  return showFoodWheelGame(context, api: HttpFoodWheelApi(accessToken: accessToken));
}

class WheelSlot {
  final String emoji;
  final int mult;
  final bool veg;
  const WheelSlot(this.emoji, this.mult, this.veg);
}

const kSlots = [
  WheelSlot('🐔', 45, false),
  WheelSlot('🍅', 5, true),
  WheelSlot('🐐', 15, false),
  WheelSlot('🌶️', 5, true),
  WheelSlot('🐟', 25, false),
  WheelSlot('🥕', 5, true),
  WheelSlot('🦐', 10, false),
  WheelSlot('🌽', 5, true),
];
const kChips = [10, 500, 6000, 30000, 100000];

enum RoundPhase { betting, result }

class RoundState {
  final String roundId;
  final int dailyRoundNumber;
  final int secondsLeft, balance, myPayout;
  final bool enabled;
  final List<WheelSlot> symbols;
  final RoundPhase phase;
  final List<int> pools, myBets;
  final int? resultSlot;
  final String? special;
  final List<String> history;

  const RoundState({
    required this.roundId,
    this.dailyRoundNumber = 1,
    required this.secondsLeft,
    this.enabled = true,
    this.symbols = kSlots,
    required this.phase,
    required this.pools,
    required this.myBets,
    required this.balance,
    this.myPayout = 0,
    this.resultSlot,
    this.special,
    this.history = const [],
  });

  factory RoundState.fromJson(Map<String, dynamic> j) {
    final rawSymbols = (j['symbols'] as List?) ?? const [];
    final symbols = rawSymbols.map((e) {
      final item = Map<String, dynamic>.from(e as Map);
      return WheelSlot((item['emoji'] ?? '❔').toString(),
        (item['multiplier'] as num? ?? 1).toInt(), item['isVegetable'] == true);
    }).toList();
    final rawHistory = (j['history'] as List?) ?? const [];
    return RoundState(
      roundId: (j['roundId'] ?? '').toString(),
      dailyRoundNumber: (j['dailyRoundNumber'] as num? ?? 1).toInt(),
      secondsLeft: (j['secondsLeft'] as num? ?? 0).toInt(),
      phase: j['phase'] == 'result' ? RoundPhase.result : RoundPhase.betting,
      pools: ((j['pools'] as List?) ?? List.filled(8, 0)).map((e) => (e as num).toInt()).toList(),
      myBets: ((j['myBets'] as List?) ?? List.filled(8, 0)).map((e) => (e as num).toInt()).toList(),
      balance: (j['balance'] as num? ?? 0).toInt(),
      myPayout: (j['myPayout'] as num? ?? 0).toInt(),
      resultSlot: (j['resultSlot'] as num?)?.toInt(),
      special: j['special'] as String?,
      history: rawHistory.map((e) => '$e').toList(),
      enabled: j['enabled'] == true,
      symbols: symbols.length == 8 ? symbols : kSlots,
    );
  }
}

abstract class FoodWheelApi {
  Future<RoundState> fetchState();
  Future<RoundState> placeBet(String roundId, int slot, int amount, String idempotencyKey);
}

class MockFoodWheelApi implements FoodWheelApi {
  static const _betSecs = 30, _resSecs = 8;
  final _rnd = math.Random();
  int _balance, _round = 330554;
  DateTime _start = DateTime.now();
  late List<int> _pools;
  List<int> _bets = List.filled(8, 0);
  int? _slot;
  String? _special;
  int _payout = 0;
  bool _settled = false;
  final List<String> _hist = [];

  MockFoodWheelApi({int balance = 500000}) : _balance = balance {
    _pools = _freshPools();
  }

  List<int> _freshPools() => List.generate(8, (_) => 300000 + _rnd.nextInt(2000000));
  int get _elapsed => DateTime.now().difference(_start).inSeconds;

  void _tick() {
    final el = _elapsed;
    if (el >= _betSecs + _resSecs) {
      _round++;
      _start = DateTime.now();
      _pools = _freshPools();
      _bets = List.filled(8, 0);
      _slot = null;
      _special = null;
      _payout = 0;
      _settled = false;
    } else if (el >= _betSecs && !_settled) {
      _settle();
    } else if (el < _betSecs) {
      _pools[_rnd.nextInt(8)] += _rnd.nextInt(60000);
    }
  }

  void _settle() {
    _settled = true;
    final r = _rnd.nextDouble();
    if (r < .06) {
      _special = 'salad';
    } else if (r < .12) {
      _special = 'pizza';
    } else {
      final w = kSlots.map((s) => 1 / s.mult).toList();
      var x = _rnd.nextDouble() * w.reduce((a, b) => a + b);
      _slot = 0;
      for (var i = 0; i < 8; i++) {
        x -= w[i];
        if (x <= 0) { _slot = i; break; }
      }
    }
    final wins = _special == null
      ? [_slot!]
      : [for (var i = 0; i < 8; i++) if (kSlots[i].veg == (_special == 'salad')) i];
    _payout = wins.fold(0, (a, i) => a + _bets[i] * kSlots[i].mult);
    _balance += _payout;
    _hist.insert(0, _special == 'salad' ? '🥗' : _special == 'pizza' ? '🍕' : kSlots[_slot!].emoji);
    if (_hist.length > 9) _hist.removeLast();
  }

  RoundState _state() {
    final el = _elapsed;
    final betting = el < _betSecs;
    return RoundState(
      roundId: '$_round',
      secondsLeft: betting ? _betSecs - el : _betSecs + _resSecs - el,
      phase: betting ? RoundPhase.betting : RoundPhase.result,
      pools: List.of(_pools),
      myBets: List.of(_bets),
      balance: _balance,
      myPayout: betting ? 0 : _payout,
      resultSlot: betting ? null : _slot,
      special: betting ? null : _special,
      history: List.of(_hist),
    );
  }

  @override
  Future<RoundState> fetchState() async { _tick(); return _state(); }

  @override
  Future<RoundState> placeBet(String roundId, int slot, int amount, String idempotencyKey) async {
    _tick();
    if (roundId != '$_round' || _elapsed >= _betSecs) throw Exception('round_closed');
    if (amount > _balance) throw Exception('insufficient_balance');
    _balance -= amount;
    _bets[slot] += amount;
    _pools[slot] += amount;
    return _state();
  }
}

/// Authenticated production adapter. The Worker owns outcomes and all wallet changes.
class HttpFoodWheelApi implements FoodWheelApi {
  static const _base = 'https://happy-live-api.taher616270.workers.dev/api/v1';
  final String accessToken;
  final http.Client _client;
  HttpFoodWheelApi({required this.accessToken, http.Client? client}) : _client = client ?? http.Client();
  Map<String, String> get _headers => {'Content-Type':'application/json','Authorization':'Bearer $accessToken'};
  Future<Map<String, dynamic>> _request(String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$_base$path');
    final response = body == null ? await _client.get(uri, headers:_headers) : await _client.post(uri, headers:_headers, body:jsonEncode(body));
    Map<String, dynamic> data;
    try { final decoded = jsonDecode(response.body); if (decoded is! Map<String, dynamic>) throw const FormatException(); data = decoded; }
    catch (_) { throw Exception('استجابة الخادم غير مفهومة (${response.statusCode})'); }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code = (data['error'] ?? 'request_failed').toString();
      const messages = {'authentication_required':'انتهت جلسة الدخول، سجّل الدخول مجدداً.','game_disabled':'اللعبة متوقفة حالياً.','round_closed':'انتهى وقت الرهان؛ انتظر الجولة القادمة.','insufficient_balance':'رصيدك غير كافٍ.','player_disabled':'تم إيقاف اللعب لهذا الحساب.','bet_limit_exceeded':'وصلت إلى الحد المسموح للرهان في الجولة.','bet_rate_limited':'طلبات الرهان سريعة؛ انتظر قليلاً.','state_rate_limited':'التحديثات كثيرة؛ انتظر قليلاً.'};
      throw Exception(messages[code] ?? 'تعذر تنفيذ الطلب: $code');
    }
    return data;
  }
  @override Future<RoundState> fetchState() async => RoundState.fromJson(await _request('/games/cat-greed/state'));
  @override Future<RoundState> placeBet(String roundId, int slot, int amount, String idempotencyKey) async {
    final result = await _request('/games/cat-greed/bet', body:{'roundId':roundId,'slot':slot,'amount':amount,'idempotencyKey':idempotencyKey});
    return RoundState.fromJson(result);
  }
}

Future<void> showFoodWheelGame(BuildContext context, {required FoodWheelApi api}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SizedBox(
      height: MediaQuery.of(context).size.height * 0.92,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: FoodWheelGame(api: api),
      ),
    ),
  );
}

String _fmt(int n) => n >= 1000000
  ? '${(n / 1000000).toStringAsFixed(2)}M'
  : n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : '$n';

class FoodWheelGame extends StatefulWidget {
  final FoodWheelApi api;
  const FoodWheelGame({super.key, required this.api});
  @override
  State<FoodWheelGame> createState() => _FoodWheelGameState();
}

class _FoodWheelGameState extends State<FoodWheelGame> {
  final _rnd = math.Random();
  Timer? _poll, _msgTimer, _betDebounce;
  RoundState? _s;
  int _bal = 0, _chip = 500, _hit = -1;
  final List<int> _queuedBets = List<int>.filled(8, 0);
  final Set<int> _inFlightSlots = <int>{};
  int _inFlightAmount = 0;
  String? _queuedRoundId;
  Set<int> _win = {};
  String? _lit, _err, _msg;
  bool _spinning = false, _flushingBets = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() { _poll?.cancel(); _msgTimer?.cancel(); _betDebounce?.cancel(); super.dispose(); }

  int _reservedBetTotal() =>
      _queuedBets.fold<int>(0, (sum, value) => sum + value) + _inFlightAmount;

  String _newBetKey() {
    final bytes = List<int>.generate(16, (_) => math.Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20,32)}';
  }

  void _say(String m) {
    _msgTimer?.cancel();
    setState(() => _msg = m);
    _msgTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _msg = null);
    });
  }

  Future<void> _refresh() async {
    try {
      final s = await widget.api.fetchState();
      if (!mounted) return;
      final newRound = _s != null && _s!.roundId != s.roundId;
      if (newRound && _queuedRoundId != s.roundId) {
        for (var i = 0; i < _queuedBets.length; i++) {
          _queuedBets[i] = 0;
        }
        _queuedRoundId = null;
        _betDebounce?.cancel();
      }
      setState(() {
        _s = s;
        _err = null;
        if (!_spinning) _bal = (s.balance - _reservedBetTotal()).clamp(0, 1 << 62).toInt();
        if (newRound) { _win = {}; _hit = -1; _lit = null; _msg = null; }
      });
      if (s.phase == RoundPhase.result && s.roundId != _animatedRound) {
        _animatedRound = s.roundId;
        _spin(s);
      }
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Future<void> _spin(RoundState s) async {
    _spinning = true;
    final target = s.resultSlot ?? _rnd.nextInt(8);
    final start = _rnd.nextInt(8);
    final steps = 25 + ((target - start + 8) % 8);
    for (var k = 0; k < steps; k++) {
      if (!mounted) return;
      setState(() => _hit = (start + k) % 8);
      await Future.delayed(Duration(milliseconds: 60 + (k * k * 0.3).round()));
    }
    if (!mounted) return;
    _spinning = false;
    setState(() {
      _hit = -1;
      _bal = (s.balance - _reservedBetTotal()).clamp(0, 1 << 62).toInt();
      _lit = s.special;
      _win = s.special == null
        ? {target}
        : {for (var i = 0; i < 8; i++) if (s.symbols[i].veg == (s.special == 'salad')) i};
    });
    if (s.myPayout > 0) {
      _say('ربحت ${_fmt(s.myPayout)} 🎉');
    } else if (s.myBets.any((b) => b > 0)) {
      _say('حظ أوفر في الجولة القادمة');
    }
  }

  Future<void> _bet(int i) async {
    final s = _s;
    if (s == null || !s.enabled) { _say('اللعبة متوقفة حالياً'); return; }
    if (s.phase != RoundPhase.betting) { _say('انتظر الجولة القادمة'); return; }
    if (_queuedRoundId != null && _queuedRoundId != s.roundId) {
      _say('انتظر تأكيد رهانات الجولة السابقة');
      return;
    }

    final selected = <int>{
      for (var slot = 0; slot < 8; slot++)
        if (s.myBets[slot] > 0 || _queuedBets[slot] > 0 || _inFlightSlots.contains(slot)) slot,
    };
    if (!selected.contains(i) && selected.length >= 6) {
      _say('يمكنك اختيار 6 خانات مختلفة فقط، واضغط عليها مجدداً لزيادة الرهان');
      return;
    }
    if (_bal < _chip) { _say('رصيدك لا يكفي'); return; }

    _queuedRoundId = s.roundId;
    setState(() {
      _queuedBets[i] += _chip;
      _bal -= _chip;
    });
    _betDebounce?.cancel();
    _betDebounce = Timer(const Duration(milliseconds: 180), _flushPendingBets);
  }

  Future<void> _flushPendingBets() async {
    if (_flushingBets || !mounted) return;
    _flushingBets = true;
    try {
      while (mounted) {
        final slot = _queuedBets.indexWhere((amount) => amount > 0);
        if (slot < 0) break;
        final roundId = _queuedRoundId;
        if (roundId == null) break;
        final amount = _queuedBets[slot];
        _queuedBets[slot] = 0;
        _inFlightAmount += amount;
        _inFlightSlots.add(slot);
        if (mounted) {
          setState(() {
            _bal = ((_s?.balance ?? _bal) - _reservedBetTotal()).clamp(0, 1 << 62).toInt();
          });
        }

        try {
          final n = await widget.api.placeBet(roundId, slot, amount, _newBetKey());
          _inFlightAmount -= amount;
          _inFlightSlots.remove(slot);
          if (mounted) {
            setState(() {
              _s = n;
              _bal = (n.balance - _reservedBetTotal()).clamp(0, 1 << 62).toInt();
            });
          }
        } catch (e) {
          _inFlightAmount -= amount;
          _inFlightSlots.remove(slot);
          if (mounted) {
            setState(() {
              _bal = ((_s?.balance ?? _bal) - _reservedBetTotal()).clamp(0, 1 << 62).toInt();
            });
            _say(e.toString().replaceFirst('Exception: ', ''));
          }
          await _refresh();
        }

        // Serialize and pace requests: rapid taps are coalesced into one amount
        // per selected slot, instead of flooding the Worker with one request per tap.
        await Future.delayed(const Duration(milliseconds: 180));
      }
    } finally {
      _flushingBets = false;
      if (mounted && _queuedBets.any((amount) => amount > 0)) {
        _betDebounce?.cancel();
        _betDebounce = Timer(const Duration(milliseconds: 80), _flushPendingBets);
      } else if (!_inFlightSlots.isNotEmpty) {
        _queuedRoundId = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF4AA3FF), Color(0xFF8FD0FF), Color(0xFFBFE6FF)],
              stops: [0, 0.6, 1],
            ),
          ),
          child: SafeArea(
            top: false,
            child: s == null
              ? Center(child: _err != null ? _errorBox() : const CircularProgressIndicator(color: Colors.white))
              : SingleChildScrollView(
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: Column(children: [_topBar(s), _wheel(s)]),
                  ),
                  if (!s.enabled) const Padding(padding: EdgeInsets.all(8), child: Text('اللعبة متوقفة حالياً؛ لا يمكن وضع رهانات جديدة.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                  CustomPaint(
                    painter: _WoodPainter(),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
                      child: Column(children: [
                        _specials(),
                        const SizedBox(height: 8),
                        Text('رهانك في هذه الجولة: ${_fmt(s.myBets.fold(0, (a, b) => a + b) + _reservedBetTotal())}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                        SizedBox(height: 30, child: Center(child: Text(_msg ?? '', style: const TextStyle(color: Color(0xFFFFE36A), fontSize: 15, fontWeight: FontWeight.w800)))),
                        _chips(),
                        const SizedBox(height: 10),
                        _history(s),
                        if (_err != null) _errorBox(),
                      ]),
                    ),
                  ),
                ]),
              ),
          ),
        ),
      ),
    );
  }

  Widget _errorBox() => Column(mainAxisSize: MainAxisSize.min, children: [
    const Text('تعذر الاتصال بالخادم', style: TextStyle(color: Colors.white)),
    Text('$_err', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 10)),
    TextButton(onPressed: _refresh, child: const Text('إعادة المحاولة')),
  ]);

  Widget _pill(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: const Color(0x7314087A), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0x59FFFFFF))),
    child: child,
  );

  Widget _topBar(RoundState s) => Row(children: [
    _pill(Text('الجولة ${s.dailyRoundNumber}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
    const SizedBox(width: 6),
    IconButton(onPressed: _showRules, icon: const Icon(Icons.help_outline, color: Colors.white)),
    const Spacer(),
    _pill(Text('🪙 ${_fmt(_bal)}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
    IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close, color: Colors.white)),
  ]);

  Widget _wheel(RoundState s) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, d = w * 0.27;
      return SizedBox(width: w, height: w, child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _SpokesPainter(d))),
        for (var i = 0; i < 8; i++)
          Positioned(
            left: w / 2 + w * 0.37 * math.sin(i * math.pi / 4) - d / 2,
            top: w / 2 - w * 0.37 * math.cos(i * math.pi / 4) - d / 2,
            width: d, height: d, child: _slot(i, s, d),
          ),
        Center(child: Container(
          width: d, height: d, alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF8A4B2A), border: Border.all(color: const Color(0xFF5A2F16), width: 4)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(s.phase == RoundPhase.betting ? 'حدد الوقت' : 'النتيجة', style: TextStyle(color: Colors.white, fontSize: d * 0.13)),
            Text(s.phase == RoundPhase.betting ? '${s.secondsLeft}s' : '🎡', style: TextStyle(color: Colors.white, fontSize: d * 0.3, fontWeight: FontWeight.w900)),
          ]),
        )),
      ]));
    });
  }

  Widget _slot(int i, RoundState s, double d) {
    final slot = s.symbols[i];
    final hit = _hit == i, win = _win.contains(i);
    final mx = s.pools.reduce((a, b) => a > b ? a : b);
    final frac = mx == 0 ? 0.45 : 0.45 + 0.35 * (s.pools[i] / mx);
    const dark = Color(0xFF5A3A00);
    return GestureDetector(
      onTap: s.enabled ? () => _bet(i) : null,
      child: Stack(clipBehavior: Clip.none, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: d, height: d,
          transform: Matrix4.identity()..scale(hit ? 1.12 : 1.0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle, color: const Color(0xFFFFF3C4),
            border: Border.all(color: const Color(0xFF8A4B2A), width: 4),
            boxShadow: hit || win ? [BoxShadow(color: win ? const Color(0xFF3DFF7A) : const Color(0xFFFFD400), blurRadius: 22, spreadRadius: 4)] : null,
          ),
          child: ClipOval(child: Stack(children: [
            Positioned.fill(child: ColoredBox(color: win ? const Color(0xFFBFFFB8) : const Color(0xFFFFF3C4))),
            Align(alignment: Alignment.bottomCenter, child: FractionallySizedBox(heightFactor: frac, widthFactor: 1, child: ColoredBox(color: win ? const Color(0xFF4DE06A) : const Color(0xFFFFD84D)))),
            Align(alignment: const Alignment(0, -0.28), child: Text('${slot.mult} اضعاف', style: TextStyle(color: dark, fontSize: d * 0.14))),
            Align(alignment: const Alignment(0, 0.52), child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_fmt(s.pools[i]), style: TextStyle(color: dark, fontSize: d * 0.17, fontWeight: FontWeight.bold)),
              SizedBox(width: d * 0.04),
              Text('🪙', style: TextStyle(fontSize: d * 0.14)),
            ])),
          ])),
        ),
        Positioned(top: -d * 0.22, left: 0, right: 0, child: Center(child: Text(slot.emoji, style: TextStyle(fontSize: d * 0.38)))),
        if (mx > 0 && s.pools[i] == mx)
          Positioned(top: -d * 0.1, right: -d * 0.12, child: Transform.rotate(
            angle: -0.14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(color: const Color(0xFFE5251B), borderRadius: BorderRadius.circular(5)),
              child: Text('Hot', style: TextStyle(color: Colors.white, fontSize: d * 0.15, fontWeight: FontWeight.w900)),
            ),
          )),
        if (s.myBets[i] > 0)
          Positioned(bottom: -8, left: 0, right: 0, child: Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(color: const Color(0xFF7A22FF), borderRadius: BorderRadius.circular(9)),
            child: Text(_fmt(s.myBets[i]), style: const TextStyle(color: Colors.white, fontSize: 10)),
          ))),
      ]),
    );
  }

  Widget _specials() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_special('salad', 'السلطة'), _special('pizza', 'البيتزا')]),
  );

  Widget _special(String key, String label) {
    final on = _lit == key;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      decoration: BoxDecoration(
        color: on ? const Color(0xFFFFD400) : const Color(0x8C3C1E0A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x59FFFFFF), width: 2),
        boxShadow: on ? const [BoxShadow(color: Color(0xFFFFD400), blurRadius: 18)] : null,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(key == 'salad' ? '🥗' : '🍕', style: const TextStyle(fontSize: 34)),
        Text(label, style: TextStyle(color: on ? const Color(0xFF4A2A00) : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      ]),
    );
  }

  Widget _chips() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    for (final v in kChips)
      GestureDetector(
        onTap: () => setState(() => _chip = v),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          transform: Matrix4.translationValues(0, _chip == v ? -4 : 0, 0),
          width: 54, height: 54, alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(colors: [Color(0xFF4AA3FF), Color(0xFF1746C9)]),
            border: Border.all(color: _chip == v ? const Color(0xFFFFD400) : Colors.white, width: 3),
          ),
          child: Text(_fmt(v), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
        ),
      ),
  ]);

  Widget _history(RoundState s) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: const Color(0x8C3C1E0A), borderRadius: BorderRadius.circular(14)),
    child: Row(children: [
      const Text('النتيجة: ', style: TextStyle(color: Colors.white, fontSize: 12)),
      for (final e in s.history)
        Padding(padding: const EdgeInsets.only(left: 6), child: Text(e, style: const TextStyle(fontSize: 20))),
    ]),
  );

  void _showRules() {
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF4A3DF0),
          content: const Text(
            '1. اختر قيمة الرهان ثم اضغط على الوجبة.\n'
            '2. مدة الجولة 30 ثانية ثم تظهر النتيجة.\n'
            '3. الربح = رهانك × عدد الأضعاف.\n'
            '4. يمكنك الرهان على أكثر من وجبة.\n'
            '5. السلطة تربح كل الخضروات، والبيتزا تربح كل اللحوم.',
            style: TextStyle(color: Colors.white, height: 1.8, fontSize: 13),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسنًا'))],
        ),
      ),
    );
  }
}

class _SpokesPainter extends CustomPainter {
  final double d;
  _SpokesPainter(this.d);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.37;
    final w = size.width, bottom = size.height * 0.99;
    Path trap(double topHalf, double botHalf, double top, double bot) => Path()
      ..moveTo(c.dx - topHalf, top)..lineTo(c.dx + topHalf, top)
      ..lineTo(c.dx + botHalf, bot)..lineTo(c.dx - botHalf, bot)..close();
    final outer = trap(d * 0.5, w * 0.3, c.dy, bottom);
    canvas.drawPath(outer, Paint()..color = const Color(0xFFB8763F));
    canvas.drawPath(outer, Paint()..style = PaintingStyle.stroke..strokeWidth = d * 0.05..color = const Color(0xFF5A2F16));
    canvas.drawPath(trap(d * 0.16, w * 0.17, c.dy + d * 0.3, bottom), Paint()..color = const Color(0xFF6B3A1E));
    canvas.drawRect(Rect.fromLTRB(c.dx - w * 0.2, c.dy + w * 0.2, c.dx + w * 0.2, c.dy + w * 0.2 + d * 0.14), Paint()..color = const Color(0xFFB8763F));
    final spoke = Paint()..color = const Color(0xFF8A4B2A)..strokeWidth = d * 0.13..strokeCap = StrokeCap.round;
    final shine = Paint()..color = const Color(0xFFC08A55)..strokeWidth = d * 0.04..strokeCap = StrokeCap.round;
    final bulb = Paint()..color = Colors.white;
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final end = Offset(c.dx + r * math.sin(a), c.dy - r * math.cos(a));
      canvas.drawLine(c, end, spoke);
      canvas.drawLine(c, end, shine);
      canvas.drawCircle(Offset.lerp(c, end, 0.5)!, d * 0.035, bulb);
    }
    canvas.drawCircle(c, d * 0.56, Paint()..style = PaintingStyle.stroke..strokeWidth = d * 0.1..color = const Color(0xFFC08A55));
    for (var k = 0; k < 14; k++) {
      final a = k * 2 * math.pi / 14;
      canvas.drawCircle(Offset(c.dx + d * 0.56 * math.sin(a), c.dy - d * 0.56 * math.cos(a)), d * 0.03, bulb);
    }
  }

  @override
  bool shouldRepaint(_SpokesPainter old) => old.d != d;
}

class _WoodPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF9C5A2E));
    final line = Paint()..color = const Color(0xFF8E4F25)..strokeWidth = 2;
    for (double x = 48; x < size.width; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 8), Paint()..color = const Color(0xFF6B3A1E));
    canvas.drawRect(Rect.fromLTWH(0, 8, size.width, 3), Paint()..color = const Color(0xFFC08A55));
  }

  @override
  bool shouldRepaint(_WoodPainter old) => false;
}
