import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// لعبة عجلة الأطعمة — تستخدم خادم Happy Live ومحفظة التطبيق.
Future<void> openFoodWheelGame(BuildContext context, {required String accessToken}) {
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

enum RoundPhase { betting, spinning, result }

class FoodWheelWinner {
  final String name;
  final String userCode;
  final int payout;
  const FoodWheelWinner({required this.name, required this.userCode, required this.payout});
}

class RoundState {
  final String roundId;
  final String userCode;
  final int dailyRoundNumber;
  final int secondsLeft, balance, myPayout, myBetCount, maxBetsPerRound;
  final bool enabled;
  final List<WheelSlot> symbols;
  final RoundPhase phase;
  final List<int> pools, myBets;
  final int? resultSlot;
  final String? special;
  final List<String> history;
  final List<FoodWheelWinner> topWinners;

  const RoundState({
    required this.roundId,
    this.userCode = '',
    this.dailyRoundNumber = 1,
    required this.secondsLeft,
    this.enabled = true,
    this.symbols = kSlots,
    required this.phase,
    required this.pools,
    required this.myBets,
    required this.balance,
    this.myPayout = 0,
    this.myBetCount = 0,
    this.maxBetsPerRound = 6,
    this.resultSlot,
    this.special,
    this.history = const [],
    this.topWinners = const [],
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
      userCode: (j['userCode'] ?? '').toString(),
      dailyRoundNumber: (j['dailyRoundNumber'] as num? ?? 1).toInt(),
      secondsLeft: (j['secondsLeft'] as num? ?? 0).toInt(),
      phase: j['phase'] == 'result'
          ? RoundPhase.result
          : j['phase'] == 'spinning' ? RoundPhase.spinning : RoundPhase.betting,
      pools: ((j['pools'] as List?) ?? List.filled(8, 0)).map((e) => (e as num).toInt()).toList(),
      myBets: ((j['myBets'] as List?) ?? List.filled(8, 0)).map((e) => (e as num).toInt()).toList(),
      balance: (j['balance'] as num? ?? 0).toInt(),
      myPayout: (j['myPayout'] as num? ?? 0).toInt(),
      myBetCount: (j['myBetCount'] as num? ?? 0).toInt(),
      maxBetsPerRound: (j['maxBetsPerRound'] as num? ?? 6).toInt(),
      resultSlot: (j['resultSlot'] as num?)?.toInt(),
      special: j['special'] as String?,
      history: rawHistory.map((e) => '$e').toList(),
      topWinners: ((j['topWinners'] as List?) ?? const []).map((e) {
        final item = Map<String, dynamic>.from(e as Map);
        return FoodWheelWinner(
          name: (item['name'] ?? 'لاعب').toString(),
          userCode: (item['userCode'] ?? '').toString(),
          payout: (item['payout'] as num? ?? 0).toInt(),
        );
      }).toList(),
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
  static const _betSecs = 30, _spinSecs = 5, _resSecs = 3;
  final _rnd = math.Random();
  int _balance, _round = 330554;
  DateTime _start = DateTime.now();
  late List<int> _pools;
  List<int> _bets = List.filled(8, 0);
  int _betCount = 0;
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
    if (el >= _betSecs + _spinSecs + _resSecs) {
      _round++;
      _start = DateTime.now();
      _pools = _freshPools();
      _bets = List.filled(8, 0);
      _betCount = 0;
      _slot = null;
      _special = null;
      _payout = 0;
      _settled = false;
    } else if (el >= _betSecs + _spinSecs - 1 && !_settled) {
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
    final spinning = el >= _betSecs && el < _betSecs + _spinSecs;
    return RoundState(
      roundId: '$_round',
      secondsLeft: betting
          ? _betSecs - el
          : spinning ? _betSecs + _spinSecs - el : _betSecs + _spinSecs + _resSecs - el,
      phase: betting ? RoundPhase.betting : spinning ? RoundPhase.spinning : RoundPhase.result,
      pools: List.of(_pools),
      myBets: List.of(_bets),
      myBetCount: _betCount,
      maxBetsPerRound: 6,
      balance: _balance,
      myPayout: _settled ? _payout : 0,
      resultSlot: _settled ? _slot : null,
      special: _settled ? _special : null,
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
    if (_betCount >= 6) throw Exception('bet_count_limit');
    _betCount++;
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
  Map<String, dynamic> lastDiagnostics = <String, dynamic>{};
  int? lastStateStatus;
  int? lastWalletStatus;
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
      const messages = {'authentication_required':'انتهت جلسة الدخول، سجّل الدخول مجدداً.','game_disabled':'اللعبة متوقفة حالياً.','round_closed':'انتهى وقت الرهان؛ انتظر الجولة القادمة.','insufficient_balance':'رصيدك غير كافٍ.','player_disabled':'تم إيقاف اللعب لهذا الحساب.','bet_limit_exceeded':'وصلت إلى الحد المالي المسموح للرهان في الجولة.','bet_count_limit':'وصلت إلى الحد الأقصى: 6 رهانات في الجولة.','bet_rate_limited':'طلبات الرهان سريعة؛ انتظر قليلاً.','state_rate_limited':'التحديثات كثيرة؛ انتظر قليلاً.'};
      throw Exception(messages[code] ?? 'تعذر تنفيذ الطلب: $code');
    }
    return data;
  }
  // The application wallet endpoint is the canonical balance source.
  // Read it with the same session and verify the public account code before
  // displaying it in the game, so a stale/incorrect game-state balance cannot
  // make a funded account appear empty.
  Future<Map<String, dynamic>> _stateWithWallet(Map<String, dynamic> state) async {
    // Never silently fall back to a possibly stale/zero game balance. If the
    // canonical app-wallet request fails, surface the exact failure instead.
    final gameBalance = state['balance'];
    Map<String, dynamic> wallet;
    try {
      final response = await _client.get(Uri.parse('$_base/wallet'), headers: _headers);
      lastWalletStatus = response.statusCode;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) throw const FormatException();
        wallet = decoded;
      } catch (_) {
        lastDiagnostics = <String, dynamic>{
          'stateStatus': lastStateStatus,
          'walletStatus': response.statusCode,
          'gameCode': state['userCode'],
          'gameBalance': gameBalance,
          'walletParse': 'failed',
        };
        throw Exception('استجابة محفظة التطبيق غير مفهومة (${response.statusCode})');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = (wallet['error'] ?? 'wallet_request_failed').toString();
        lastDiagnostics = <String, dynamic>{
          'stateStatus': lastStateStatus,
          'walletStatus': response.statusCode,
          'gameCode': state['userCode'],
          'gameBalance': gameBalance,
          'walletError': code,
        };
        throw Exception('تعذر قراءة محفظة التطبيق: $code');
      }
    } catch (e) {
      if (lastDiagnostics.isEmpty) {
        lastDiagnostics = <String, dynamic>{
          'stateStatus': lastStateStatus,
          'walletStatus': lastWalletStatus,
          'gameCode': state['userCode'],
          'gameBalance': gameBalance,
          'walletRequest': e.toString(),
        };
      }
      rethrow;
    }
    final gameCode = (state['userCode'] ?? '').toString();
    final walletCode = (wallet['userCode'] ?? '').toString();
    lastDiagnostics = <String, dynamic>{
      'stateStatus': lastStateStatus,
      'walletStatus': lastWalletStatus,
      'gameCode': gameCode,
      'walletCode': walletCode,
      'gameBalance': gameBalance,
      'walletBalance': wallet['balance'],
    };
    if (gameCode.isEmpty || walletCode.isEmpty || gameCode != walletCode) {
      throw Exception('تعذر التحقق من تطابق حساب محفظة التطبيق مع حساب اللعبة');
    }
    final walletBalance = wallet['balance'];
    if (walletBalance is! num || walletBalance < 0) {
      throw Exception('استجابة محفظة التطبيق لا تحتوي على رصيد صالح');
    }
    state['balance'] = walletBalance;
    return state;
  }

  @override Future<RoundState> fetchState() async {
    final state = await _request('/games/food-wheel/state');
    lastStateStatus = 200;
    lastWalletStatus = null;
    lastDiagnostics = <String, dynamic>{
      'stateStatus': lastStateStatus,
      'gameCode': state['userCode'],
      'gameBalance': state['balance'],
    };
    return RoundState.fromJson(await _stateWithWallet(state));
  }

  @override Future<RoundState> placeBet(String roundId, int slot, int amount, String idempotencyKey) async {
    final result = await _request('/games/food-wheel/bet', body:{'roundId':roundId,'slot':slot,'amount':amount,'idempotencyKey':idempotencyKey});
    return RoundState.fromJson(await _stateWithWallet(result));
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
  Timer? _poll, _msgTimer, _clock;
  int _visibleSecondsLeft = 0;
  RoundState? _s;
  int _bal = 0, _chip = 500, _hit = -1;
  String _animatedRound = '';
  Set<int> _win = {};
  String? _lit, _err, _msg;
  int _pendingBetCount = 0, _pendingBetAmount = 0, _localRoundBetCount = 0;
  String _localBetRoundId = '';
  bool _spinning = false, _refreshing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Keep the visible countdown moving locally; server polling is only for
    // authoritative phase, bets, pools and wallet synchronization.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _visibleSecondsLeft <= 0) return;
      setState(() => _visibleSecondsLeft--);
    });
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() { _poll?.cancel(); _msgTimer?.cancel(); _clock?.cancel(); super.dispose(); }

  void _say(String m) {
    _msgTimer?.cancel();
    setState(() => _msg = m);
    _msgTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _msg = null);
    });
  }

  Future<void> _refresh() async {
    // Prevent overlapping one-second polls from applying older wallet responses
    // after a newer response has already updated the visible balance.
    if (_refreshing) return;
    _refreshing = true;
    try {
      final s = await widget.api.fetchState();
      if (!mounted) return;
      final newRound = _s != null && _s!.roundId != s.roundId;
      final api = widget.api;
      final diagnostic = api is HttpFoodWheelApi ? api.lastDiagnostics : const <String, dynamic>{};
      final zeroBalanceWarning = s.balance == 0
          ? 'الخادم أعاد رصيدًا صفرًا. تشخيص آمن: ${diagnostic.entries.map((e) => '${e.key}=${e.value}').join(' | ')}'
          : null;
      setState(() {
        _s = s;
        _visibleSecondsLeft = s.secondsLeft;
        _err = zeroBalanceWarning;
        // Keep in-flight taps reserved locally so a poll cannot briefly
        // restore their coins or make a sixth bet look available twice.
        _bal = s.balance - _pendingBetAmount;
        if (_pendingBetCount == 0) _localRoundBetCount = s.myBetCount;
        if (newRound || _localBetRoundId != s.roundId) {
          _localBetRoundId = s.roundId;
          _localRoundBetCount = s.myBetCount;
          _win = {}; _hit = -1; _lit = null; _msg = null;
        }
      });
      if (s.phase == RoundPhase.spinning && s.roundId != _animatedRound) {
        _animatedRound = s.roundId;
        _spin(s);
      } else if (s.phase == RoundPhase.result && s.roundId != _animatedRound) {
        _animatedRound = s.roundId;
        _showSettledResult(s);
      }
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      _refreshing = false;
    }
  }

  int _visualTarget(RoundState s) {
    if (s.resultSlot != null) return s.resultSlot!;
    if (s.special == 'salad') {
      final matches = [for (var i = 0; i < 8; i++) if (s.symbols[i].veg) i];
      if (matches.isNotEmpty) return matches.first;
    }
    if (s.special == 'pizza') {
      final matches = [for (var i = 0; i < 8; i++) if (!s.symbols[i].veg) i];
      if (matches.isNotEmpty) return matches.first;
    }
    return _rnd.nextInt(8);
  }

  void _applySettledState(RoundState s) {
    _spinning = false;
    setState(() {
      _hit = -1;
      _bal = s.balance;
      _lit = s.special;
      _win = s.special == null
          ? (s.resultSlot == null ? <int>{} : {s.resultSlot!})
          : {for (var i = 0; i < 8; i++) if (s.symbols[i].veg == (s.special == 'salad')) i};
    });
    if (s.myPayout > 0) {
      _say('ربحت ${_fmt(s.myPayout)} 🎉');
    } else if (s.myBets.any((b) => b > 0)) {
      _say('حظ أوفر في الجولة القادمة');
    }
  }

  void _showSettledResult(RoundState s) {
    _applySettledState(s);
  }

  Future<void> _spin(RoundState initial) async {
    _spinning = true;
    final seconds = initial.secondsLeft.clamp(1, 5).toInt();
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    final randomUntil = deadline.subtract(const Duration(seconds: 1));

    // Keep the wheel moving for the first part of the five-second phase.
    // The server reveals the committed outcome during the final second.
    while (mounted && DateTime.now().isBefore(randomUntil)) {
      setState(() => _hit = _rnd.nextInt(8));
      await Future.delayed(const Duration(milliseconds: 110));
    }

    while (mounted && DateTime.now().isBefore(deadline)) {
      final latest = _s;
      if (latest != null && latest.roundId == initial.roundId &&
          (latest.resultSlot != null || latest.special != null)) {
        break;
      }
      setState(() => _hit = _rnd.nextInt(8));
      await Future.delayed(const Duration(milliseconds: 90));
    }

    if (!mounted) return;
    final latest = _s != null && _s!.roundId == initial.roundId ? _s! : initial;
    setState(() => _hit = _visualTarget(latest));
    while (mounted && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 40));
    }
    if (!mounted) return;
    final finalState = _s != null && _s!.roundId == initial.roundId ? _s! : latest;
    _applySettledState(finalState);
  }

  String _newBetIdempotencyKey() {
    final bytes = List<int>.generate(16, (_) => math.Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20,32)}';
  }

  Future<void> _bet(int i) async {
    final s = _s;
    if (s == null || !s.enabled) { _say('اللعبة متوقفة حالياً'); return; }
    if (s.phase != RoundPhase.betting || _visibleSecondsLeft <= 0) { _say('انتهى وقت الرهان؛ انتظر الجولة القادمة'); return; }
    if (_localBetRoundId != s.roundId) {
      _localBetRoundId = s.roundId;
      _localRoundBetCount = s.myBetCount;
    }
    if (_localRoundBetCount >= s.maxBetsPerRound) {
      _say('وصلت إلى الحد الأقصى: 6 رهانات في الجولة');
      return;
    }
    if (_bal < _chip) { _say('رصيدك لا يكفي'); return; }

    // Every tap is a separate bet with its own idempotency key. Requests are
    // sent concurrently; three fast taps therefore create three independent
    // bets instead of being dropped behind a single busy flag.
    final amount = _chip;
    final roundId = s.roundId;
    final key = _newBetIdempotencyKey();
    _localRoundBetCount++;
    _pendingBetCount++;
    _pendingBetAmount += amount;
    setState(() { _bal -= amount; });
    var placed = false;
    try {
      await widget.api.placeBet(roundId, i, amount, key);
      placed = true;
    } catch (e) {
      _say(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _pendingBetCount--;
          _pendingBetAmount -= amount;
          if (!placed) _localRoundBetCount = math.max(0, _localRoundBetCount - 1);
        });
        if (_pendingBetCount == 0) await _refresh();
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
              colors: [Color(0xFF2F7DEE), Color(0xFF6CC4FF), Color(0xFFBFE6FF)],
              stops: [0, 0.45, 1],
            ),
          ),
          child: SafeArea(
            top: false,
            child: s == null
                ? Center(
                    child: _err != null
                        ? _errorBox()
                        : const CircularProgressIndicator(color: Colors.white))
                : Stack(children: [
                    SingleChildScrollView(
                      child: Column(children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                          child: Column(children: [
                            _topBar(s),
                            const SizedBox(height: 26),
                            _wheel(s),
                          ]),
                        ),
                        _platform(s),
                        _redFloor(s),
                      ]),
                    ),
                    _resultOverlay(s),
                  ]),
          ),
        ),
      ),
    );
  }

  Widget _resultOverlay(RoundState s) => Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: 0.6,
          widthFactor: 1,
          child: IgnorePointer(
            ignoring: s.phase != RoundPhase.result,
            child: AnimatedSlide(
              offset: s.phase == RoundPhase.result
                  ? Offset.zero
                  : const Offset(0, 1.05),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              child: _resultPanel(s),
            ),
          ),
        ),
      );

  Widget _topWinnersCorner(RoundState s) => Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: const Color(0xA51A155D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFD978), width: 1.2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('أفضل 3 لاعبين',
                style: TextStyle(color: Color(0xFFFFD978), fontSize: 10,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            if (s.topWinners.isEmpty)
              const Text('لا يوجد فائزون',
                  style: TextStyle(color: Colors.white70, fontSize: 9))
            else
              for (var i = 0; i < s.topWinners.length && i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Text(['🥇', '🥈', '🥉'][i],
                          style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.topWinners[i].name,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white,
                                    fontSize: 9, fontWeight: FontWeight.bold)),
                            Text(_fmt(s.topWinners[i].payout),
                                style: const TextStyle(color: Color(0xFFFFD978),
                                    fontSize: 8, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      );

  Widget _resultPanel(RoundState s) {
    final food = s.special == 'salad'
        ? '🥗'
        : s.special == 'pizza'
            ? '🍕'
            : s.symbols[s.resultSlot ?? 0].emoji;
    final mine = s.myBets.fold(0, (a, b) => a + b);
    const t = TextStyle(
        color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, height: 1.8);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3F7BFF), Color(0xFF5B2FE6)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 104),
            child: SingleChildScrollView(
              child: Column(children: [
                SizedBox(
                  height: 62,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CustomPaint(size: const Size(20, 54), painter: _CutleryPainter(true)),
                      const SizedBox(width: 10),
                      Text(food, style: const TextStyle(fontSize: 44)),
                      const SizedBox(width: 10),
                      CustomPaint(size: const Size(20, 54), painter: _CutleryPainter(false)),
                    ],
                  ),
                ),
                Container(
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: const LinearGradient(colors: [
                      Color(0x00FFD400), Color(0xFFFFD400),
                      Color(0xFFFFD400), Color(0x00FFD400)
                    ], stops: [0, 0.15, 0.85, 1]),
                  ),
                ),
                Text('نتيجة الجولة ${s.dailyRoundNumber} $food',
                    textAlign: TextAlign.center, style: t),
                Text('رهانك في هذه الجولة: ${_fmt(mine)}',
                    textAlign: TextAlign.center, style: t),
                Text('الفائز في هذه الجولة: ${_fmt(s.myPayout)}',
                    textAlign: TextAlign.center, style: t),
                const SizedBox(height: 6),
                Text(s.myPayout > 0 ? '🥳' : '😿',
                    style: const TextStyle(fontSize: 36)),
              ]),
            ),
          ),
          Positioned(left: 0, top: 0, width: 96, child: _topWinnersCorner(s)),
        ],
      ),
    );
  }

  Widget _errorBox() => Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('تعذر الاتصال بالخادم', style: TextStyle(color: Colors.white)),
        Text('$_err', maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 10)),
        TextButton(onPressed: _refresh, child: const Text('إعادة المحاولة')),
      ]);

  Widget _pill(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x7314087A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x59FFFFFF)),
        ),
        child: child,
      );

  Widget _topBar(RoundState s) => Row(children: [
        _pill(Text('جولة ${s.dailyRoundNumber}',
            style: const TextStyle(color: Colors.white, fontSize: 12,
                fontWeight: FontWeight.bold))),
        const SizedBox(width: 6),
        IconButton(onPressed: _showRules,
            icon: const Icon(Icons.help_outline, color: Colors.white)),
        IconButton(onPressed: _showTopWins,
            icon: const Text('🏆', style: TextStyle(fontSize: 20))),
        const Spacer(),
        _pill(Text('🪙 ${_fmt(_bal)}',
            style: const TextStyle(color: Colors.white, fontSize: 13,
                fontWeight: FontWeight.bold))),
        IconButton(onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close, color: Colors.white)),
      ]);

  Widget _platform(RoundState s) => Stack(clipBehavior: Clip.none, children: [
        Column(children: [
          CustomPaint(painter: _PlatTopPainter(),
              child: const SizedBox(height: 30, width: double.infinity)),
          CustomPaint(
            painter: _PlatFacePainter(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 34, 10, 16),
              child: _pills(s),
            ),
          ),
        ]),
        Positioned(
          top: -46, left: 8, right: 8,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [_special('salad', 'السلطة'), _special('pizza', 'البيتزا')]),
        ),
      ]);

  Widget _pills(RoundState s) => Row(children: [
        GestureDetector(
          onTap: _showRules,
          child: Container(
            width: 30, height: 30, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: const Color(0xFFFFD9A0),
              border: Border.all(color: const Color(0xFFB3261E), width: 2)),
            child: const Text('!', style: TextStyle(color: Color(0xFFB3261E),
                fontWeight: FontWeight.w900, fontSize: 16)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: _plPill('رهانك في هذه الجولة',
            '${_fmt(s.myBets.fold(0, (a, b) => a + b) + _pendingBetAmount)} 🪙')),
        const SizedBox(width: 8),
        Expanded(child: _plPill('رصيدي', '${_fmt(_bal)} 🪙')),
        const SizedBox(width: 8),
        Expanded(child: _plPill('الجولة', '${s.dailyRoundNumber}')),
      ]);

  Widget _plPill(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF5DE),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFF6B3A1E), width: 2),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF4A2A10), fontSize: 10)),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF4A2A10), fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ]),
      );

  Widget _redFloor(RoundState s) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 34, 12, 20),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFFFC4755), Color(0xFFC91E31)], stops: [0, 0.45]),
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            top: -30, left: 24, right: 24,
            child: Container(height: 14, decoration: const BoxDecoration(
              color: Color(0xFF870816),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)))),
          ),
          Column(children: [
            SizedBox(height: 13, child: Center(child: Text(_msg ?? '',
              style: const TextStyle(color: Color(0xFFFFE36A), fontSize: 13,
                  height: 1.0, fontWeight: FontWeight.w800)))),
            _chestBar(),
            _chips(),
            const SizedBox(height: 10),
            _history(s),
            if (_err != null) _walletWarning(),
          ]),
        ]),
      );

  Widget _chestBar() {
    const rewards = [20000, 30000, 50000, 80000, 120000, 200000, 400000];
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (var i = 0; i < rewards.length; i++)
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('🧰', style: TextStyle(fontSize: 26,
              shadows: i == 0 ? const [Shadow(color: Color(0xFFFFD400), blurRadius: 10)] : null)),
            Text(_fmt(rewards[i]),
              style: const TextStyle(color: Colors.white, fontSize: 11)),
          ]),
      ]),
      const SizedBox(height: 6),
      ClipRRect(borderRadius: BorderRadius.circular(6),
        child: const LinearProgressIndicator(value: 0, minHeight: 10,
          backgroundColor: Color(0x59000000),
          valueColor: AlwaysStoppedAnimation(Color(0xFFFFB400)))),
      const SizedBox(height: 4),
      const Text('صندوق 1 من 7 — 0 / 1M',
        style: TextStyle(color: Colors.white, fontSize: 12)),
      const SizedBox(height: 10),
    ]);
  }

  Widget _special(String key, String label) {
    final on = _lit == key;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(key == 'salad' ? '🥗' : '🍕',
          style: TextStyle(fontSize: 46,
            shadows: on ? const [Shadow(color: Color(0xFFFFD400), blurRadius: 18)] : null)),
      Transform.translate(
        offset: const Offset(0, -6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: on ? const Color(0xFFFFD400) : const Color(0xFFFFF5DE),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF6B3A1E), width: 2)),
          child: Text(label, style: const TextStyle(color: Color(0xFF4A2A10),
              fontWeight: FontWeight.w800, fontSize: 14)),
        ),
      ),
    ]);
  }

  Widget _walletWarning() => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 7, bottom: 5),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: const Color(0xCC651515),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFF9999)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'تعذر تحديث رصيد المحفظة: $_err',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: _refresh,
              child: const Text('إعادة', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

  Widget _chestProgress() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xAA5B170F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFD66B), width: 1.4),
        ),
        child: Row(
          children: [
            const Text('🎁', style: TextStyle(fontSize: 30)),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'صناديق المكافآت',
                    style: TextStyle(
                      color: Color(0xFFFFE7A0),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'بيانات التقدم والمكافآت غير متاحة من الخادم حالياً',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.lock_outline, color: Color(0xFFFFD66B)),
          ],
        ),
      );

  Widget _winnerPodium() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xAA57150E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFD66B)),
        ),
        child: Column(
          children: [
            const Text(
              '🏆 منصة الفائزين 🏆',
              style: TextStyle(
                color: Color(0xFFFFE6A0),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _podiumPlace('🥈', 'المركز الثاني', 58),
                _podiumPlace('🥇', 'المركز الأول', 78),
                _podiumPlace('🥉', 'المركز الثالث', 48),
              ],
            ),
            const SizedBox(height: 5),
            const Text(
              'سيظهر ترتيب الفائزين عند توفير بياناته من الخادم',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      );

  Widget _podiumPlace(String medal, String title, double height) => Expanded(
        child: Column(
          children: [
            Text(medal, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 3),
            Container(
              height: height,
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD978), Color(0xFF9E672A)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                border: Border.all(color: const Color(0xFFFFE6A0)),
              ),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF4A250B),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      );

  void _showTopWins() {
    showDialog<void>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0xFF4A86EE), Color(0xFF5A2FE6)]),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFCFE0FF), width: 3)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                IconButton(onPressed: _showRules,
                  icon: const Icon(Icons.help_outline, color: Colors.white)),
                const Text('🏆 أقوى الفائزين',
                  style: TextStyle(color: Colors.white,
                    fontSize: 18, fontWeight: FontWeight.w900)),
                IconButton(onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white)),
              ]),
              const Padding(
                padding: EdgeInsets.all(36),
                child: Text('لا توجد بيانات بعد',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _slot(int i, RoundState s, double size) {
    final item = s.symbols[i];
    final selected = _hit == i;
    final won = _win.contains(i);
    final amount = s.myBets[i];
    final pool = i < s.pools.length ? s.pools[i] : 0;
    final canBet = s.enabled && s.phase == RoundPhase.betting &&
        _visibleSecondsLeft > 0 && !_spinning;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canBet ? () => _bet(i) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.055),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: selected || won
                ? const [Color(0xFFFFF7B0), Color(0xFFFFC928), Color(0xFFE18A18)]
                : item.veg
                    ? const [Color(0xFFFFFDF0), Color(0xFFE6F5C8), Color(0xFFB5D982)]
                    : const [Color(0xFFFFFDF5), Color(0xFFFFE0B0), Color(0xFFE8A35D)],
          ),
          border: Border.all(
            color: selected || won ? const Color(0xFFFFD400) : const Color(0xFF6B3A1E),
            width: selected || won ? 4 : 2.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: selected ? 12 : 5,
              offset: const Offset(0, 3),
            ),
            if (selected || won)
              const BoxShadow(color: Color(0xAAFFF176), blurRadius: 15),
          ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.emoji, style: TextStyle(fontSize: size * 0.39)),
              Text('${item.mult}x', style: TextStyle(
                color: const Color(0xFF542B12),
                fontSize: size * 0.14,
                fontWeight: FontWeight.w900,
              )),
              if (amount > 0)
                Text(_fmt(amount), style: TextStyle(
                  color: const Color(0xFF1746A0),
                  fontSize: size * 0.12,
                  fontWeight: FontWeight.w900,
                )),
              Text(_fmt(pool), style: TextStyle(
                color: const Color(0xFF5A351D),
                fontSize: size * 0.105,
                fontWeight: FontWeight.w700,
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wheel(RoundState s) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, d = w * 0.27, ds = w * 0.22;
      return SizedBox(width: w, height: w, child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _SpokesPainter(d))),
        for (var i = 0; i < 8; i++)
          Positioned(
            left: w / 2 + w * 0.37 * math.sin(i * math.pi / 4) - ds / 2,
            top: w / 2 - w * 0.37 * math.cos(i * math.pi / 4) - ds / 2,
            width: ds, height: ds, child: _slot(i, s, ds),
          ),
        Center(child: Container(
          width: d, height: d, alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle,
            color: const Color(0xFF8A4B2A),
            border: Border.all(color: const Color(0xFF5A2F16), width: 4)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              s.phase == RoundPhase.betting
                  ? 'وقت الرهان'
                  : s.phase == RoundPhase.spinning ? 'تحديد الفائز' : 'النتيجة',
              style: TextStyle(color: Colors.white, fontSize: d * 0.13)),
            Text(s.phase == RoundPhase.result ? '🎡' : '${_visibleSecondsLeft}s',
              style: TextStyle(color: Colors.white, fontSize: d * 0.3,
                fontWeight: FontWeight.w900)),
          ]),
        )),
      ]));
    });
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
            '1. اختر قيمة الرهان ثم اضغط على الوجبة خلال 30 ثانية.\n'
            '2. بعد إغلاق الرهان تدور العجلة لمدة 5 ثوانٍ لتحديد الوجبة الفائزة.\n'
            '3. تظهر نافذة النتيجة لمدة 3 ثوانٍ.\n'
            '4. الربح = رهانك × عدد الأضعاف.\n'
            '5. يمكنك الرهان على أكثر من وجبة.\n'
            '6. السلطة تربح كل الخضروات، والبيتزا تربح كل اللحوم.',
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
    final w = size.width, h = size.height;
    final c = size.center(Offset.zero);

    canvas.drawOval(Rect.fromLTWH(-w * 0.35, h * 0.80, w * 1.0, h * 0.5),
        Paint()..color = const Color(0xFF7CCF63));
    canvas.drawOval(Rect.fromLTWH(w * 0.25, h * 0.84, w * 1.2, h * 0.5),
        Paint()..color = const Color(0xFF9BD465));

    final sw = w * 0.59, u = sw / 100;
    final ox = c.dx - sw / 2, oy = h * 0.985 - 64 * u;
    Offset p(double x, double y) => Offset(ox + x * u, oy + y * u);
    final frame = Path()..fillType = PathFillType.evenOdd;
    frame.addPolygon([p(37, 0), p(63, 0), p(100, 64), p(0, 64)], true);
    frame.moveTo(p(35, 27).dx, p(35, 27).dy);
    frame.lineTo(p(35, 19).dx, p(35, 19).dy);
    frame.quadraticBezierTo(p(35, 12.5).dx, p(35, 12.5).dy,
        p(50, 12.5).dx, p(50, 12.5).dy);
    frame.quadraticBezierTo(p(65, 12.5).dx, p(65, 12.5).dy,
        p(65, 19).dx, p(65, 19).dy);
    frame.lineTo(p(65, 27).dx, p(65, 27).dy);
    frame.close();
    frame.addPolygon([p(31, 41.7), p(69, 41.7), p(77, 64), p(23, 64)], true);
    canvas.drawPath(frame, Paint()..color = const Color(0xFFDD964A));
    canvas.save();
    canvas.clipPath(frame);
    final grain = Paint()..color = const Color(0xFFC8823A)..strokeWidth = u * 0.4;
    for (double x = 0; x < 100; x += 3) {
      canvas.drawLine(p(x, 0), p(x, 64), grain);
    }
    canvas.restore();
    canvas.drawPath(frame, Paint()
      ..style = PaintingStyle.stroke..strokeWidth = u * 0.9
      ..strokeJoin = StrokeJoin.round..color = const Color(0xFF6B3A1E));
    for (final sx in [25.0, 75.0]) {
      canvas.save();
      canvas.translate(p(sx, 35).dx, p(sx, 35).dy);
      canvas.rotate(sx < 50 ? 0.25 : -0.25);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero,
          width: u * 5.2, height: u * 14),
          Paint()..color = const Color(0x526B3A1E));
      canvas.restore();
    }
    for (final fx in [-1.5, 76.5]) {
      final rr = RRect.fromRectAndRadius(
          Rect.fromLTWH(p(fx, 62).dx, p(fx, 62).dy, 25 * u, 2.6 * u),
          Radius.circular(u * 0.8));
      canvas.drawRRect(rr, Paint()..color = const Color(0xFFEFDAA9));
      canvas.drawRRect(rr, Paint()..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.4..color = const Color(0xFF6B3A1E));
    }

    final plank = Paint()..color = const Color(0xFFA9553B);
    final edge = Paint()..style = PaintingStyle.stroke
      ..strokeWidth = 2..color = const Color(0xFF7B3524);
    final peg = Paint()..color = const Color(0xFFFFF5DE);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final pc = Offset(c.dx + w * 0.19 * math.sin(a),
          c.dy - w * 0.19 * math.cos(a));
      canvas.save();
      canvas.translate(pc.dx, pc.dy);
      canvas.rotate(a);
      final rr = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w * 0.038,
              height: w * 0.14), const Radius.circular(3));
      canvas.drawRRect(rr, plank);
      canvas.drawRRect(rr, edge);
      canvas.drawCircle(Offset.zero, 3.5, peg);
      canvas.restore();
    }

    canvas.drawCircle(c, d * 0.56, Paint()
      ..style = PaintingStyle.stroke..strokeWidth = d * 0.1
      ..color = const Color(0xFFC08A55));
    for (var k = 0; k < 14; k++) {
      final a = k * 2 * math.pi / 14;
      canvas.drawCircle(Offset(c.dx + d * 0.56 * math.sin(a),
          c.dy - d * 0.56 * math.cos(a)), d * 0.03, peg);
    }
  }

  @override
  bool shouldRepaint(_SpokesPainter old) => old.d != d;
}

class _PlatTopPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()..addPolygon(
      [Offset(w * 0.06, 0), Offset(w * 0.94, 0), Offset(w, h), Offset(0, h)], true);
    canvas.drawPath(path, Paint()..shader = const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFFECC26F), Color(0xFFE0A456)],
    ).createShader(Offset.zero & size));
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke
      ..strokeWidth = 2..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF6B3A1E));
  }
  @override
  bool shouldRepaint(_PlatTopPainter old) => false;
}

class _PlatFacePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndCorners(Offset.zero & size,
      bottomLeft: const Radius.circular(24), bottomRight: const Radius.circular(24));
    canvas.drawRRect(r, Paint()..color = const Color(0xFFD89046));
    canvas.save();
    canvas.clipRRect(r);
    final hatch = Paint()..color = const Color(0xFFCC8440)..strokeWidth = 2;
    for (double x = -size.height; x < size.width; x += 11) {
      canvas.drawLine(Offset(x, size.height),
          Offset(x + size.height * 0.47, 0), hatch);
    }
    canvas.restore();
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 3),
        Paint()..color = const Color(0xFFEFC98A));
    canvas.drawRRect(r.deflate(1.5), Paint()..style = PaintingStyle.stroke
      ..strokeWidth = 3..color = const Color(0xFF6B3A1E));
  }
  @override
  bool shouldRepaint(_PlatFacePainter old) => false;
}

class _CutleryPainter extends CustomPainter {
  final bool fork;
  _CutleryPainter(this.fork);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 19, size.height / 64);
    final fill = Paint()..color = const Color(0xFFE9EDF6);
    final line = Paint()..style = PaintingStyle.stroke..strokeWidth = 1
      ..color = const Color(0xFF8D96AD);
    void rr(double x, double y, double w, double h, double r) {
      final b = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r));
      canvas.drawRRect(b, fill);
      canvas.drawRRect(b, line);
    }
    if (fork) {
      rr(3, 2, 3, 20, 1.5); rr(8, 2, 3, 20, 1.5); rr(13, 2, 3, 20, 1.5);
      rr(3, 18, 13, 8, 3); rr(7, 24, 5, 38, 2.5);
    } else {
      final blade = Path()..moveTo(5, 2)..cubicTo(13, 4, 15, 16, 12, 34)
        ..lineTo(5, 34)..close();
      canvas.drawPath(blade, fill); canvas.drawPath(blade, line);
      rr(5, 32, 7, 30, 3);
    }
  }
  @override
  bool shouldRepaint(_CutleryPainter old) => false;
}
