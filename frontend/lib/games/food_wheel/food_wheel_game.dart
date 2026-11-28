import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// خطأ موحّد قادم من طبقة الاتصال بالخادم
class WheelApiException implements Exception {
  final String code;
  final int? status;
  final String? body;
  const WheelApiException(this.code, {this.status, this.body});

  @override
  String toString() => wheelErrorText(this);
}

/// نص عربي واضح لأي خطأ يظهر للاعب
String wheelErrorText(Object e) {
  if (e is! WheelApiException) return 'حدث خطأ غير متوقع';
  switch (e.code) {
    case 'max_foods_per_round':
      return 'مسموح تراهن على 6 أكلات فقط';
    case 'insufficient_balance':
      return 'رصيدك لا يكفي';
    case 'round_closed':
    case 'round_changed':
      return 'انتهى وقت الرهان، انتظر الجولة القادمة';
    case 'duplicate_bet':
      return 'هذا الرهان مسجّل مسبقًا';
    case 'session_missing':
      return 'افتح اللعبة من داخل Happy Live';
    case 'session_expired':
      return 'انتهت الجلسة، أعد فتح اللعبة';
    case 'backend_not_implemented':
      return 'الخادم ما يدعم عجلة الأطعمة بعد';
    case 'settlement_disabled':
      return 'اللعب متوقف مؤقتًا حتى تفعيل التسوية من الخادم';
    case 'forbidden':
      return 'حسابك غير مسموح له باللعب';
    case 'rate_limited':
      return 'طلبات كثيرة، انتظر شوي';
    case 'timeout':
      return 'انتهت مهلة الاتصال';
    case 'network':
      return 'تعذر الاتصال بالإنترنت';
    case 'bad_response':
      return 'رد غير متوقع من الخادم';
    case 'bet_ok_state_failed':
      return 'تم تسجيل الرهان، جاري تحديث الحالة';
    default:
      return 'تعذر تنفيذ الطلب (${e.code})';
  }
}

// ======================================================================
// لعبة عجلة الأطعمة (Happy Food Wheel)
//
// هذا الملف هو اللعبة نفسها: الواجهة والقواعد والمضاعفات والرهانات والصناديق.
// الاتصال بالخادم يمر فقط عبر FoodWheelApi:
//   - HttpFoodWheelApi (ملف wheel_api_http.dart): التشغيل الحقيقي مع Happy Live
//
// الخادم هو المسؤول عن: الرصيد، قبول الرهان، نتيجة الجولة، الأرباح، التسوية.
// هذا الملف لا يحدد فائزًا ولا يعدّل رصيدًا بنفسه؛ يعرض الرهان محليًا كـ pending
// ويحتفظ به حتى يؤكد الخادم قبوله أو يرفضه صراحة.
// ======================================================================

// ---------- البيانات ----------
class WheelSlot {
  final String emoji;
  final int mult;
  final bool veg; // خضار = تربح مع السلطة، وغيرها لحوم = تربح مع البيتزا
  const WheelSlot(this.emoji, this.mult, this.veg);
}

const kSlots = [
  WheelSlot('🐔', 45, false),
  WheelSlot('🌽', 5, true),
  WheelSlot('🍅', 5, true),
  WheelSlot('🐐', 15, false),
  WheelSlot('🌶️', 5, true),
  WheelSlot('🐟', 25, false),
  WheelSlot('🥕', 5, true),
  WheelSlot('🦐', 10, false),
];
const kSlotKeys = <String>['chicken', 'corn', 'tomato', 'goat', 'chili', 'fish', 'carrot', 'shrimp'];
const kGroupBetKeys = <String>['pizza_group', 'salad_group'];
const kBetKeys = <String>[...kSlotKeys, ...kGroupBetKeys];

Map<String, int> _foodTotalsFromJson(Map<String, dynamic> json) {
  final named = json['total_bets_by_food'];
  if (named is Map) {
    return named.map((key, value) => MapEntry('$key', (value as num).toInt()));
  }
  final rawPools = json['pools'];
  if (rawPools is! List) return const <String, int>{};
  final totals = <String, int>{};
  for (var i = 0; i < kSlotKeys.length && i < rawPools.length; i++) {
    final value = rawPools[i];
    if (value is num) totals[kSlotKeys[i]] = value.toInt();
  }
  return totals;
}

int getSpinDelay(double remaining) {
  if (remaining > 4) return 650;
  if (remaining > 3) return 400;
  if (remaining > 2) return 180;
  return 80;
}

const kChips = [10, 500, 6000, 30000, 100000];

const kChipsAdv = [100000, 500000, 1000000, 5000000, 10000000]; // وضع متقدم

// نظام الصناديق: يتجمع إجمالي رهانك (بعد نهاية كل جولة)، وكل ما يوصل حدًا يفتح صندوق.
// الحدود تراكمية: 1 مليون، 2 مليون، 6 مليون، 18 مليون، 36 مليون. المكافآت أرقام تقديرية عدّلها.
const kChestThresholds = [1000000, 2000000, 6000000, 18000000, 36000000];
const kChestRewards = [20000, 50000, 150000, 500000, 1500000];

enum RoundPhase { betting, result }

/// فائز من أكبر 3 فائزين في الجولة (الخادم يرسل نفس القائمة لكل اللاعبين)
class WheelWinner {
  final String name;
  final String? avatarUrl;
  final int amount;
  final bool isMe;
  const WheelWinner(
      {required this.name, this.avatarUrl, required this.amount, this.isMe = false});

  factory WheelWinner.fromJson(Map<String, dynamic> j) => WheelWinner(
        name: '${j['name'] ?? ''}',
        avatarUrl: j['avatar'] as String?,
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        isMe: j['is_me'] == true,
      );
}

/// سجل في جدول أقوى الفائزين: أكبر ربح في رهان واحد اليوم
class WinRecord {
  final String name, food; // food = إيموجي الوجبة اللي ربح فيها
  final String? avatarUrl, flag;
  final int amount;
  final bool isMe;
  const WinRecord(
      {required this.name,
      required this.amount,
      required this.food,
      this.avatarUrl,
      this.flag,
      this.isMe = false});

  factory WinRecord.fromJson(Map<String, dynamic> j) => WinRecord(
        name: '${j['name'] ?? ''}',
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        food: '${j['food'] ?? ''}',
        avatarUrl: j['avatar'] as String?,
        flag: j['flag'] as String?,
        isMe: j['is_me'] == true,
      );
}

/// رهان لاعب (يظهر لكل اللاعبين في قائمة الرهانات المباشرة)
class BetEvent {
  final String name;
  final String? avatarUrl;
  final int slot, amount;
  final bool isMe;
  const BetEvent(
      {required this.name,
      required this.slot,
      required this.amount,
      this.avatarUrl,
      this.isMe = false});

  factory BetEvent.fromJson(Map<String, dynamic> j) => BetEvent(
        name: '${j['name'] ?? ''}',
        slot: (j['slot'] as num?)?.toInt() ?? 0,
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        avatarUrl: j['avatar'] as String?,
        isMe: j['is_me'] == true,
      );
}

/// بيانات اللاعب الحالي (من الخادم)
class WheelPlayer {
  final String id, name, status;
  final String? avatarUrl, flag; // flag: إيموجي علم أو رمز الدولة بحرفين
  const WheelPlayer(
      {required this.id,
      required this.name,
      this.status = 'active',
      this.avatarUrl,
      this.flag});

  factory WheelPlayer.fromJson(Map<String, dynamic> j) => WheelPlayer(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        status: '${j['status'] ?? 'active'}',
        avatarUrl: j['avatar'] as String?,
        flag: j['flag'] as String?,
      );
}

/// سجل جولة للاعب الحالي (شاشة "سجلي")
class MyRoundRecord {
  final int round, bet, payout;
  final String result; // إيموجي الوجبة الفائزة
  const MyRoundRecord(
      {required this.round,
      required this.bet,
      required this.payout,
      required this.result});

  factory MyRoundRecord.fromJson(Map<String, dynamic> j) {
    final special = j['special'] as String?;
    final slot = (j['result_slot'] as num?)?.toInt();
    final emoji = special == 'salad'
        ? '🥗'
        : special == 'pizza'
            ? '🍕'
            : (slot != null && slot >= 0 && slot < kSlots.length)
                ? kSlots[slot].emoji
                : '${j['result'] ?? ''}';
    return MyRoundRecord(
      round: ((j['round_id'] ?? j['round']) as num?)?.toInt() ?? 0,
      bet: ((j['bet'] ?? j['total_bet']) as num?)?.toInt() ?? 0,
      payout: (j['payout'] as num?)?.toInt() ?? 0,
      result: emoji,
    );
  }
}

class RoundState {
  final int roundId, secondsLeft, balance, myPayout;
  final int? roundEndAt, bettingEndsAt, resultChosenAt, serverTime;
  final RoundPhase phase;
  final List<int> pools;
  final Map<String, int> totalBetsByFood;
  final Map<String, int> totalBetsByGroup;
  final Map<String, int> myBetsByKey;
  final int? resultSlot; // رقم الوجبة الفائزة، أو null لو كانت سلطة/بيتزا
  final String? special; // 'salad' | 'pizza' | null
  final List<String> history;
  final int chestIndex, chestTotal, chestReward;
  final List<int> chestThresholds, chestRewards;
  final List<WheelWinner> topWinners;
  final List<BetEvent> recentBets; // آخر رهانات كل اللاعبين في هذه الجولة
  final int players; // عدد اللاعبين في الطاولة
  final String? roundUuid; // معرّف الجولة عند الخادم (للرهان)
  final WheelPlayer? player; // اللاعب الحالي

  const RoundState({
    required this.roundId,
    required this.secondsLeft,
    this.roundEndAt,
    this.bettingEndsAt,
    this.resultChosenAt,
    this.serverTime,
    required this.phase,
    required this.pools,
    required this.balance,
    this.myPayout = 0,
    this.totalBetsByFood = const <String, int>{},
    this.totalBetsByGroup = const <String, int>{},
    this.myBetsByKey = const <String, int>{},
    this.resultSlot,
    this.special,
    this.history = const [],
    this.chestIndex = 0,
    this.chestTotal = 0,
    this.chestThresholds = kChestThresholds,
    this.chestRewards = kChestRewards,
    this.chestReward = 0,
    this.topWinners = const [],
    this.recentBets = const [],
    this.players = 0,
    this.roundUuid,
    this.player,
  });

  /// شكل رد الخادم المتوقع (عدّل الأسماء لتطابق الـ API عندك)
  factory RoundState.fromJson(Map<String, dynamic> j) => RoundState(
        roundId: (j['round_id'] as num).toInt(),
        secondsLeft: (j['seconds_left'] as num).toInt(),
        roundEndAt: (j['round_end_at'] as num?)?.toInt(),
        bettingEndsAt: (j['betting_ends_at'] as num?)?.toInt(),
        resultChosenAt: (j['result_chosen_at'] as num?)?.toInt(),
        serverTime: (j['server_time'] as num?)?.toInt(),
        phase: j['phase'] == 'result' ? RoundPhase.result : RoundPhase.betting,
        pools: (j['pools'] as List).map((e) => (e as num).toInt()).toList(),
        balance: (j['balance'] as num).toInt(),
        myPayout: (j['my_payout'] as num?)?.toInt() ?? 0,
        totalBetsByFood: _foodTotalsFromJson(j),
        totalBetsByGroup: (j['total_bets_by_group'] is Map)
            ? Map<String, int>.from((j['total_bets_by_group'] as Map).map((key, value) => MapEntry('$key', (value as num).toInt())))
            : const <String, int>{},
        myBetsByKey: (j['my_bets_by_key'] is Map)
            ? Map<String, int>.from((j['my_bets_by_key'] as Map).map((key, value) => MapEntry('$key', (value as num).toInt())))
            : const <String, int>{},
        resultSlot: (j['result_slot'] as num?)?.toInt(),
        special: j['special'] as String?,
        history: ((j['history'] as List?) ?? []).map((e) => '$e').toList(),
        chestIndex: (j['chest_index'] as num?)?.toInt() ?? 0,
        chestTotal: (j['chest_total'] as num?)?.toInt() ?? 0,
        chestThresholds: j['chest_thresholds'] == null
            ? kChestThresholds
            : (j['chest_thresholds'] as List).map((e) => (e as num).toInt()).toList(),
        chestRewards: j['chest_rewards'] == null
            ? kChestRewards
            : (j['chest_rewards'] as List).map((e) => (e as num).toInt()).toList(),
        chestReward: (j['chest_reward'] as num?)?.toInt() ?? 0,
        topWinners: ((j['top_winners'] as List?) ?? [])
            .map((e) => WheelWinner.fromJson(e as Map<String, dynamic>))
            .toList(),
        recentBets: ((j['recent_bets'] as List?) ?? [])
            .map((e) => BetEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
        players: (j['players'] as num?)?.toInt() ?? 0,
        roundUuid: j['round_uuid']?.toString(),
        player: j['player'] is Map
            ? WheelPlayer.fromJson(Map<String, dynamic>.from(j['player'] as Map))
            : null,
      );
}

// ---------- واجهة الخادم ----------
// الخادم هو اللي يختار النتيجة ويخصم ويضيف الرصيد. التطبيق يعرض فقط.
abstract class FoodWheelApi {
  Future<RoundState> fetchState(); // GET  /api/v1/games/wheel/state
  Future<RoundState> placeBet(int roundId, int slot, int amount, String idempotencyKey); // POST /bet
  Future<List<WinRecord>> fetchTopWins(); // أقوى الفائزين اليوم
  Future<List<MyRoundRecord>> fetchMyHistory(); // سجل جولاتي
}

// ---------- الفتح ----------
Future<void> showFoodWheelGame(BuildContext context,
    {required FoodWheelApi api}) {
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

/// 1000000 → 1M ، 6000000 → 6M
String _mil(int n) =>
    n >= 1000000 && n % 1000000 == 0 ? '${n ~/ 1000000}M' : _fmt(n);

class _LogEntry {
  final int round, bet, payout;
  final String result;
  const _LogEntry(this.round, this.bet, this.payout, this.result);
}

String _fmt(int n) {
  if (n >= 1000000) {
    var value = (n / 1000000).toStringAsFixed(3);
    while (value.contains('.') && value.endsWith('0')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.endsWith('.')) value = value.substring(0, value.length - 1);
    return value + 'M';
  }
  if (n >= 1000) return (n / 1000).toStringAsFixed(1) + 'K';
  return n.toString();
}

// ---------- شاشة اللعبة ----------

// ---------- شاشة اللعبة ----------
class FoodWheelGame extends StatefulWidget {
  final FoodWheelApi api;
  const FoodWheelGame({super.key, required this.api});

  @override
  State<FoodWheelGame> createState() => _FoodWheelGameState();
}

enum _PendingBetStatus { queued, sending, accepted }

class _PendingWheelBet {
  final String idempotencyKey;
  final int roundId, slot, amount;
  _PendingBetStatus status;

  _PendingWheelBet({
    required this.idempotencyKey,
    required this.roundId,
    required this.slot,
    required this.amount,
    this.status = _PendingBetStatus.queued,
  });
}

class _FoodWheelGameState extends State<FoodWheelGame>
    with SingleTickerProviderStateMixin {
  int _betSequence = 0;
  Timer? _clockTimer;
  int _msgExpiresAtMs = 0, _toastExpiresAtMs = 0;
  Future<void>? _spinRun;
  int _spinTargetSlot = 0, _spinFinalizedRoundId = -1;
  bool _spinTargetKnown = false;
  double? _spinLandingStartAngle, _spinLandingStartProgress;
  double? _spinLandingArc;
  late final AnimationController _spinController;
  double _spinAngle = 0;
  bool _spinHasResult = false;
  RoundState? _s;
  int _bal = 0, _chip = 10, _animatedRound = -1, _timeLeft = 20, _popupTimeLeft = 5;
  Set<int> _win = {};
  String? _lit, _err, _msg, _roundClosedToast;
  bool _spinning = false, _panel = false;
  int _spinStartedRoundId = -1;
  bool _fetching = false; // يمنع تراكم طلبات الحالة لو الخادم بطيء
  int _lastRefreshAt = 0;
  RoundState? _popupRoundState;
  int? _popupRoundId;
  final ValueNotifier<int> _timeLeftNotifier = ValueNotifier<int>(20);
  final ValueNotifier<int> _popupTimeLeftNotifier = ValueNotifier<int>(4);
  final ValueNotifier<RoundState?> _wheelStateNotifier = ValueNotifier<RoundState?>(null);
  final Map<int, int> _roundCleanupAtMs = <int, int>{};
  int _serverClockOffsetMs = 0;
  bool _serverClockSynced = false;
  String? _clockDisplayKey, _popupDisplayKey;
  int _clockDisplaySecond = 20, _popupDisplaySecond = 4;
  final Map<int, Map<String, int>> _myBetsByRound = {};
  final Map<int, Map<String, int>> _frozenBetsByRound = {};
  final Set<int> _lockedBetRounds = {};
  final Map<int, Map<String, int>> _serverTotalsByRound = {};
  final Set<int> _finalServerTotalsRounds = {};
  final List<_PendingWheelBet> _pendingBets = [];
  int get _pendingReserved => _pendingBets
      .where((bet) => bet.status != _PendingBetStatus.accepted)
      .fold(0, (sum, bet) => sum + bet.amount);
  String _mode = 'n'; // n = عادي، a = متقدم
  bool _auto = false, _sound = true, _showBets = true;
  Map<String, int> _prevBets = <String, int>{}; // رهانات الجولة السابقة حسب اسم الطعام
  int _todayWin = 0;
  final List<_LogEntry> _log = [];
  List<int> get _chipSet {
    final base = _mode == 'a' ? kChipsAdv : kChips;
    return base.contains(_chip) ? base : [...base.take(base.length - 1), _chip];
  }

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    );
    _lastRefreshAt = 0;
    _refresh();
    // One lifecycle clock drives countdown, transient messages, and the
    // single throttled state poll. The spin itself uses the controller ticker.
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final current = _s;
      final popupId = _popupRoundId;
      final cleanupAt = popupId == null ? null : _roundCleanupAtMs[popupId];
      final popupNext = cleanupAt == null
          ? (current == null ? _popupTimeLeft : _monotonicPopupSecond(current))
          : ((cleanupAt - now) / 1000).ceil().clamp(0, 5).toInt();
      final popupExpired = popupId != null && cleanupAt != null && now >= cleanupAt;
      final clearMessage = _msg != null && now >= _msgExpiresAtMs;
      final clearToast = _roundClosedToast != null && now >= _toastExpiresAtMs;
      if (current != null) {
        final next = _monotonicPhaseSecond(current);
        if (_isResultPhase(current)) _freezeMyBets(current.roundId);
        if (_isResultPhase(current) && _spinStartedRoundId != current.roundId) {
          _startProvisionalSpin(current);
        }
        if (next != _timeLeft) {
          _timeLeft = next;
          _timeLeftNotifier.value = next;
        }
        if (popupNext != _popupTimeLeft) {
          _popupTimeLeft = popupNext;
          _popupTimeLeftNotifier.value = popupNext;
        }
      }
      if (popupExpired || clearMessage || clearToast) {
        setState(() {
          if (popupExpired && popupId != null) {
            _panel = false;
            _popupRoundState = null;
            _popupRoundId = null;
            _roundCleanupAtMs.remove(popupId);
            _myBetsByRound.remove(popupId);
            _frozenBetsByRound.remove(popupId);
            _lockedBetRounds.remove(popupId);
            _serverTotalsByRound.remove(popupId);
            _finalServerTotalsRounds.remove(popupId);
            _pendingBets.removeWhere((bet) =>
                bet.roundId == popupId && bet.status == _PendingBetStatus.accepted);
          }
          if (clearMessage) _msg = null;
          if (clearToast) _roundClosedToast = null;
        });
      }
      if (now - _lastRefreshAt >= 1000) _refresh();
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _spinController.dispose();
    _timeLeftNotifier.dispose();
    _popupTimeLeftNotifier.dispose();
    _wheelStateNotifier.dispose();
    super.dispose();
  }

  void _say(String m) {
    _msgExpiresAtMs = DateTime.now().millisecondsSinceEpoch + 3000;
    setState(() => _msg = m);
  }

  int _serverNowMs() => DateTime.now().millisecondsSinceEpoch + _serverClockOffsetMs;

  int _bettingDeadline(RoundState s) =>
      s.bettingEndsAt ?? (s.roundEndAt != null ? s.roundEndAt! - 8000 : _serverNowMs());

  bool _isResultPhase(RoundState s) =>
      s.phase == RoundPhase.result || _serverNowMs() >= _bettingDeadline(s);

  bool _bettingOpen(RoundState s) =>
      s.phase == RoundPhase.betting && _serverNowMs() < _bettingDeadline(s);

  int _resultStartAt(RoundState s) => _bettingDeadline(s);

  int _phaseSecondsLeft(RoundState s) {
    final now = _serverNowMs();
    final deadline = _bettingDeadline(s);
    if (now < deadline) {
      return ((deadline - now) / 1000).ceil().clamp(1, 20).toInt();
    }
    return ((deadline + 5000 - now) / 1000).ceil().clamp(0, 5).toInt();
  }

  int _popupSecondsLeft(RoundState s) {
    if (s.phase == RoundPhase.betting) return 4;
    final popupEndAt = s.roundEndAt ?? (_resultStartAt(s) + 10000);
    return (((popupEndAt - _serverNowMs()) / 1000).ceil())
        .clamp(1, 5)
        .toInt();
  }

  int _monotonicPhaseSecond(RoundState s) {
    final phase = _isResultPhase(s) ? 'result' : 'betting';
    final key = '${s.roundId}:$phase';
    final raw = _phaseSecondsLeft(s);
    if (_clockDisplayKey != key) {
      _clockDisplayKey = key;
      _clockDisplaySecond = raw;
      return raw;
    }
    _clockDisplaySecond = math.min(
      _clockDisplaySecond,
      math.max(raw, _clockDisplaySecond - 1),
    ).toInt();
    return _clockDisplaySecond;
  }

  int _monotonicPopupSecond(RoundState s) {
    final key = '${s.roundId}:popup';
    final raw = _popupSecondsLeft(s);
    if (_popupDisplayKey != key) {
      _popupDisplayKey = key;
      _popupDisplaySecond = raw;
      return raw;
    }
    _popupDisplaySecond = math.min(
      _popupDisplaySecond,
      math.max(raw, _popupDisplaySecond - 1),
    ).toInt();
    return _popupDisplaySecond;
  }

  Map<String, int> _myBetsForRound(int roundId) =>
      _myBetsByRound.putIfAbsent(roundId, () => <String, int>{});
  Map<String, int> _displayBetsForRound(int roundId) =>
      _frozenBetsByRound[roundId] ?? _myBetsForRound(roundId);
  int _foodBetForSlot(int roundId, int slot) =>
      slot >= 0 && slot < kSlotKeys.length
          ? (_displayBetsForRound(roundId)[kSlotKeys[slot]] ?? 0)
          : 0;
  int _groupBetForRound(int roundId, String key) =>
      _displayBetsForRound(roundId)[key] ?? 0;
  int _serverGroupTotalForRound(int roundId, String key) =>
      _serverTotalsByRound[roundId]?[key] ?? 0;
  int _myBetTotalForRound(int roundId) =>
      _displayBetsForRound(roundId).values.fold<int>(0, (sum, amount) => sum + amount);

  void _freezeMyBets(int roundId) {
    if (roundId <= 0 || _lockedBetRounds.contains(roundId)) return;
    // Snapshot the exact local, food-name-keyed amounts once at lock.
    // Polls and later rounds never replace this settlement snapshot.
    _frozenBetsByRound[roundId] =
        Map<String, int>.unmodifiable(Map<String, int>.from(_myBetsForRound(roundId)));
    _lockedBetRounds.add(roundId);
  }

  List<int> _serverTotalsForRound(int roundId) {
    final totals = _serverTotalsByRound[roundId] ?? const <String, int>{};
    return List<int>.generate(kSlotKeys.length, (i) => totals[kSlotKeys[i]] ?? 0);
  }

  void _rememberServerTotals(RoundState s) {
    // Keep accepting authoritative server totals through the final lock snapshot.
    // The local input lock can happen a fraction before the server's result poll.
    if (_finalServerTotalsRounds.contains(s.roundId)) return;
    // Freeze public totals only after the server confirms RESULT.
    // A local clock reaching zero must not freeze an earlier/stale poll.
    if (s.phase == RoundPhase.result) _finalServerTotalsRounds.add(s.roundId);
    final totals = _serverTotalsByRound.putIfAbsent(s.roundId, () => <String, int>{});
    final hasNamedTotals = s.totalBetsByFood.isNotEmpty;
    for (var i = 0; i < kSlotKeys.length; i++) {
      final key = kSlotKeys[i];
      // Prefer explicit server food-name totals. Positional pools are only
      // a compatibility fallback when the named map is wholly unavailable.
      final value = hasNamedTotals
          ? s.totalBetsByFood[key]
          : (i < s.pools.length ? s.pools[i] : null);
      if (value != null && value >= 0) {
        // Ignore stale/lower poll responses and never reset a missing food.
        totals[key] = math.max(totals[key] ?? 0, value).toInt();
      }
    }
    for (final key in kGroupBetKeys) {
      final value = s.totalBetsByGroup[key];
      if (value != null && value >= 0) {
        totals[key] = math.max(totals[key] ?? 0, value).toInt();
      }
    }
  }

  void _startOptimisticRound(RoundState s) {
    // Player bets are created and retained only in the local round-keyed map.
    _myBetsForRound(s.roundId);
    _rememberServerTotals(s);
  }

  RoundState _withOptimisticBets(RoundState s) {
    // Display bets only from the local round map (or its frozen snapshot).
    final pools = _serverTotalsForRound(s.roundId);
    return RoundState(
      roundId: s.roundId,
      secondsLeft: s.secondsLeft,
      roundEndAt: s.roundEndAt,
      bettingEndsAt: s.bettingEndsAt,
      resultChosenAt: s.resultChosenAt,
      serverTime: s.serverTime,
      phase: s.phase,
      pools: pools,
      balance: s.balance,
      myPayout: s.myPayout,
      totalBetsByFood: s.totalBetsByFood,
      totalBetsByGroup: s.totalBetsByGroup,
      myBetsByKey: s.myBetsByKey,
      resultSlot: s.resultSlot,
      special: s.special,
      history: s.history,
      chestIndex: s.chestIndex,
      chestTotal: s.chestTotal,
      chestThresholds: s.chestThresholds,
      chestRewards: s.chestRewards,
      chestReward: s.chestReward,
      topWinners: s.topWinners,
      recentBets: s.recentBets,
      players: s.players,
      roundUuid: s.roundUuid,
      player: s.player,
    );
  }

  bool _sameDisplayState(RoundState a, RoundState b) {
    // Totals, countdowns, recent bets and winner lists are refreshed in
    // their own wheel/timer paths; they must not rebuild the entire screen.
    return a.roundId == b.roundId &&
        a.phase == b.phase &&
        a.balance == b.balance &&
        a.myPayout == b.myPayout &&
        a.resultSlot == b.resultSlot &&
        a.special == b.special &&
        mapEquals(a.totalBetsByGroup, b.totalBetsByGroup) &&
        a.chestIndex == b.chestIndex &&
        a.chestTotal == b.chestTotal &&
        a.chestReward == b.chestReward &&
        a.player?.id == b.player?.id &&
        a.player?.status == b.player?.status &&
        a.player?.avatarUrl == b.player?.avatarUrl &&
        a.player?.flag == b.player?.flag;
  }

  Future<void> _refresh() async {
    if (_fetching) return;
    final pollStartedAt = DateTime.now().millisecondsSinceEpoch;
    if (_s != null && pollStartedAt - _lastRefreshAt < 1000) return;
    _lastRefreshAt = pollStartedAt;
    _fetching = true;
    try {
      final requestStartedAt = DateTime.now().millisecondsSinceEpoch;
      final s = await widget.api.fetchState();
      final responseReceivedAt = DateTime.now().millisecondsSinceEpoch;
      if (s.serverTime != null && !_serverClockSynced) {
        _serverClockOffsetMs = s.serverTime! - ((requestStartedAt + responseReceivedAt) ~/ 2);
        _serverClockSynced = true;
      }
      if (!mounted) return;
      if (_spinning && _s != null && _s!.roundId != s.roundId) return;
      final previous = _s;
      final previousTotals = previous == null ? const <int>[] : _serverTotalsForRound(previous.roundId);
      final newRound = previous != null && previous.roundId != s.roundId;
      if (newRound && previous != null) _freezeMyBets(previous.roundId);
      _rememberServerTotals(s);
      final personalBets = _myBetsForRound(s.roundId);
      for (final entry in s.myBetsByKey.entries) {
        if (entry.value > (personalBets[entry.key] ?? 0)) personalBets[entry.key] = entry.value;
      }
      final nextTotals = _serverTotalsForRound(s.roundId);
      final wheelTotalsChanged = previous == null || newRound ||
          previous.phase != s.phase ||
          previous.resultSlot != s.resultSlot ||
          previous.special != s.special ||
          !mapEquals(previous.totalBetsByGroup, s.totalBetsByGroup) ||
          !mapEquals(previous.myBetsByKey, s.myBetsByKey) ||
          previousTotals.length != nextTotals.length ||
          List<int>.generate(nextTotals.length, (i) => nextTotals[i] == previousTotals[i] ? 0 : 1).any((v) => v != 0);
      if (wheelTotalsChanged) _wheelStateNotifier.value = _withOptimisticBets(s);
      if (s.phase == RoundPhase.result || _serverNowMs() >= _bettingDeadline(s)) _freezeMyBets(s.roundId);
      final displayChanged =
          previous == null || _err != null || !_sameDisplayState(previous, s);
      if (displayChanged || newRound) {
        setState(() {
          _s = s;
          _timeLeft = _monotonicPhaseSecond(s);
          _timeLeftNotifier.value = _timeLeft;
          if (_popupRoundId == null) {
            _popupTimeLeft = _monotonicPopupSecond(s);
            _popupTimeLeftNotifier.value = _popupTimeLeft;
          }
          _err = null;
          if (!_spinning && _pendingBets.isEmpty) {
            _bal = s.balance;
          }
          if (newRound) {
            if (previous != null) {
              // Keep the previous round's local records until its popup closes.
            }
            _win = {};
            _spinController.stop();
            _spinController.value = 0;
            _spinAngle = 0;
            _spinHasResult = false;
            _spinStartedRoundId = -1;
            _spinFinalizedRoundId = -1;
            _spinTargetKnown = false;
            _spinLandingStartAngle = null;
            _spinLandingStartProgress = null;
            _spinLandingArc = null;
            _spinRun = null;
            _lit = null;
            _msg = null;
            if (_popupRoundId == null) _panel = false;
          }
        });
      } else {
        // Keep the latest small server lists without triggering a full rebuild.
        _s = s;
      }
      if (s.phase == RoundPhase.result && s.roundId != _animatedRound) {
        _animatedRound = s.roundId;
        _spin(s);
      }
    } catch (e) {
      if (mounted) {
        final message = wheelErrorText(e);
        if (_err != message) setState(() => _err = message);
      }
    } finally {
      _fetching = false;
    }
  }

  static const int _spinDurationMs = 5000;
  static const double _spinStep = math.pi * 2 / 8;
  static const double _spinBaseAngle = 3 * math.pi * 2;

  double _spinAngleForElapsed(double elapsedMs) {
    final p = (elapsedMs / _spinDurationMs).clamp(0.0, 1.0).toDouble();
    double integral;
    if (p <= 0.2) {
      integral = 1.2 * p + 2.5 * p * p;
    } else if (p <= 0.6) {
      integral = 0.34 + 2.2 * (p - 0.2) + 7.5 * (p - 0.2) * (p - 0.2);
    } else if (p <= 0.9) {
      integral = 2.42 + 8 * (p - 0.6) + 10 * (p - 0.6) * (p - 0.6);
    } else {
      integral = 5.72 + 14 * (p - 0.9);
    }
    return _spinBaseAngle + integral * 5 * _spinStep;
  }

  double _landingArcToWinner(double startAngle, int target, double remainingMs) {
    const fullTurn = math.pi * 2;
    final targetAngle = target * _spinStep;
    var arc = (targetAngle - (startAngle % fullTurn)) % fullTurn;
    if (arc < 0) arc += fullTurn;
    final minimumArc = (remainingMs / 1000.0) * 14.0 * _spinStep;
    if (arc < minimumArc) arc += ((minimumArc - arc) / fullTurn).ceil() * fullTurn;
    return arc;
  }

  double _spinAngleAtProgress(double progress) {
    if (!_spinHasResult) return _spinAngle;
    final p = progress.clamp(0.0, 1.0).toDouble();
    if (p <= 0.8) return _spinAngleForElapsed(p * _spinDurationMs);
    if (_spinLandingStartAngle != null &&
        _spinLandingStartProgress != null &&
        _spinLandingArc != null) {
      final u = ((p - _spinLandingStartProgress!) /
              (1 - _spinLandingStartProgress!))
          .clamp(0.0, 1.0)
          .toDouble();
      return _spinLandingStartAngle! + _spinLandingArc! * u;
    }
    if (!_spinTargetKnown) return _spinAngleForElapsed(p * _spinDurationMs);
    final startAngle = _spinAngleForElapsed(4000);
    final arc = _landingArcToWinner(startAngle, _spinTargetSlot, 1000);
    final u = ((p - 0.8) / 0.2).clamp(0.0, 1.0).toDouble();
    return startAngle + arc * u;
  }

  void _startProvisionalSpin(RoundState s) {
    if (_spinStartedRoundId == s.roundId) return;
    _spinStartedRoundId = s.roundId;
    _spinning = true;
    _spinController.stop();
    _spinController.duration = const Duration(milliseconds: _spinDurationMs);
    _spinTargetKnown = false;
    _spinLandingStartAngle = null;
    _spinLandingStartProgress = null;
    _spinLandingArc = null;
    _spinHasResult = true;
    final elapsedMs = (_serverNowMs() - _resultStartAt(s))
        .clamp(0, _spinDurationMs)
        .toInt();
    _spinController.value = elapsedMs / _spinDurationMs;
    if (elapsedMs < _spinDurationMs) {
      _spinRun = _spinController.forward().orCancel.catchError((_) {});
    } else {
      _spinController.value = 1;
      _spinAngle = _spinBaseAngle;
    }
  }

  Future<void> _spin(RoundState s) async {
    _freezeMyBets(s.roundId);
    if (_spinStartedRoundId != s.roundId) _startProvisionalSpin(s);
    final target = (s.resultSlot ?? 0).clamp(0, kSlots.length - 1).toInt();

    // A result received before the last second is held for landing.
    // A late result anchors at the exact current angle without a snap.
    if (!_spinTargetKnown && _spinController.value > 0.8 && _spinController.value < 1) {
      final progress = _spinController.value;
      final currentAngle = _spinAngleForElapsed(progress * _spinDurationMs);
      _spinLandingStartAngle = currentAngle;
      _spinLandingStartProgress = progress;
      _spinLandingArc = _landingArcToWinner(
        currentAngle, target, (1 - progress) * _spinDurationMs,
      );
    }
    _spinTargetSlot = target;
    _spinTargetKnown = true;

    if (_spinController.value < 1) {
      if (!_spinController.isAnimating) {
        _spinRun = _spinController.forward().orCancel.catchError((_) {});
      }
      await _spinRun;
    }
    if (!mounted || _spinFinalizedRoundId == s.roundId) return;

    final endAngle = _spinAngleAtProgress(1);
    _spinController.stop();
    _spinController.value = 1;
    _spinAngle = endAngle;
    _spinFinalizedRoundId = s.roundId;
    _spinning = false;

    // Popup and final highlighted food are committed together on the same
    // server-aligned five-second boundary.
    setState(() {
      if (_pendingBets.isEmpty) _bal = s.balance;
      // The wheel has exactly eight food outcomes. The matching group bet
      // is highlighted only in the two separate controls below the wheel.
      _lit = kSlots[target].veg ? 'pizza_group' : 'salad_group';
      _win = {target};
      _panel = true;
      _popupRoundState = s;
      _popupRoundId = s.roundId;
      _roundCleanupAtMs[s.roundId] = s.roundEndAt ?? (DateTime.now().millisecondsSinceEpoch + 5000);
      _popupTimeLeft = 5;
      _popupTimeLeftNotifier.value = 5;
    });
    final resEmoji = kSlots[target].emoji;
    final mineBets = _myBetTotalForRound(s.roundId);
    setState(() {
      _todayWin += s.myPayout;
      if (mineBets > 0) {
        _prevBets = Map<String, int>.from(_displayBetsForRound(s.roundId));
        _log.insert(0, _LogEntry(s.roundId, mineBets, s.myPayout, resEmoji));
        if (_log.length > 30) _log.removeLast();
      }
    });
    final parts = <String>[];
    if (s.myPayout > 0) {
      parts.add('ربحت ${_fmt(s.myPayout)} 🎉');
    } else if (_myBetTotalForRound(s.roundId) > 0) {
      parts.add('حظ أوفر في الجولة القادمة');
    }
    if (s.chestReward > 0) parts.add('🎁 صندوق: +${_fmt(s.chestReward)} 🪙');
    if (parts.isNotEmpty) _say(parts.join('  •  '));
  }

  String _newBetIdempotencyKey(int roundId) {
    final rawUserId = _s?.player?.id ?? 'player';
    final sanitizedUserId =
        rawUserId.replaceAll(RegExp(r'[^A-Za-z0-9.:-]'), '-');
    final safeUserId = sanitizedUserId.length <= 24
        ? sanitizedUserId
        : sanitizedUserId.substring(0, 24);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    // Avoid Random.nextInt(1 << 32): on web integer shifts can collapse the
    // bound to zero, causing RangeError before the optimistic bet is saved.
    final sequence = ++_betSequence;
    return 'fw-$safeUserId-$roundId-$stamp-$sequence';
  }

  void _showRoundClosedToast() {
    _toastExpiresAtMs = DateTime.now().millisecondsSinceEpoch + 2000;
    setState(() => _roundClosedToast = 'انتهت الجولة انتظر الجولة القادمة');
  }

  void _onGroupPointerDown(String key) {
    final slot = kBetKeys.indexOf(key);
    if (slot < kSlotKeys.length || slot < 0) return;
    final current = _s;
    if (current == null || current.roundId <= 0 || _lockedBetRounds.contains(current.roundId) || !_bettingOpen(current)) {
      if (mounted) _showRoundClosedToast();
      return;
    }
    unawaited(HapticFeedback.selectionClick().catchError((_) {}));
    if (_sound) unawaited(SystemSound.play(SystemSoundType.click).catchError((_) {}));
    unawaited(_bet(slot));
  }

  void _onFoodPointerDown(int i) {
    final current = _s;
    if (current == null || current.roundId <= 0 || _lockedBetRounds.contains(current.roundId) || !_bettingOpen(current)) {
      if (mounted) _showRoundClosedToast();
      return;
    }
    unawaited(HapticFeedback.selectionClick().catchError((_) {}));
    if (_sound) {
      unawaited(SystemSound.play(SystemSoundType.click).catchError((_) {}));
    }
    unawaited(_bet(i));
  }

  Future<void> _bet(int i) async {
    try {
      if (!mounted) return;
      final current = _s;
      if (current == null || current.roundId <= 0 || _lockedBetRounds.contains(current.roundId) || !_bettingOpen(current)) {
        _showRoundClosedToast();
        return;
      }
      final amount = _chip;
      final existingFoodCount = _myBetsForRound(current.roundId).entries
          .where((entry) => kSlotKeys.contains(entry.key) && entry.value > 0).length;
      final betKey = kBetKeys[i];
      if (i < kSlotKeys.length && (_myBetsForRound(current.roundId)[betKey] ?? 0) == 0 && existingFoodCount >= 6) {
        _say('مسموح تراهن على 6 أكلات فقط');
        return;
      }
      if (amount <= 0) return;
      final player = current.player;
      if (player != null && player.status.isNotEmpty && player.status != 'active') {
        return;
      }
      if (current.balance - _pendingReserved < amount) {
        _say('رصيدك لا يكفي');
        return;
      }

      _startOptimisticRound(current);
      final bet = _PendingWheelBet(
        idempotencyKey: _newBetIdempotencyKey(current.roundId),
        roundId: current.roundId,
        slot: i,
        amount: amount,
      );
      setState(() {
        final bets = _myBetsForRound(current.roundId);
        bets[betKey] = (bets[betKey] ?? 0) + amount;
        _pendingBets.add(bet);
        _wheelStateNotifier.value = _withOptimisticBets(current);
      });
      _queueBetSend(bet);
    } catch (error) {
      if (mounted) _say(wheelErrorText(error));
    }
  }

  bool _enqueueBet(int roundId, int slot, int amount) {
    final current = _s;
    if (current == null || roundId <= 0 || slot < 0 || slot >= kBetKeys.length || current.roundId != roundId || _lockedBetRounds.contains(roundId) || !_bettingOpen(current)) {
      _showRoundClosedToast();
      return false;
    }
    final currentFoodCount = _myBetsForRound(roundId).entries
        .where((entry) => kSlotKeys.contains(entry.key) && entry.value > 0).length;
    final betKey = kBetKeys[slot];
    if (slot < kSlotKeys.length && (_myBetsForRound(roundId)[betKey] ?? 0) == 0 && currentFoodCount >= 6) {
      _say('مسموح تراهن على 6 أكلات فقط');
      return false;
    }
    final availableBalance = _s?.balance ?? _bal;
    if (availableBalance - _pendingReserved < amount) {
      _say('رصيدك لا يكفي');
      return false;
    }
    _startOptimisticRound(current);
    final bet = _PendingWheelBet(
      idempotencyKey: _newBetIdempotencyKey(roundId),
      roundId: roundId,
      slot: slot,
      amount: amount,
    );
    setState(() {
      final bets = _myBetsForRound(roundId);
      bets[betKey] = (bets[betKey] ?? 0) + amount;
      _pendingBets.add(bet);
      _wheelStateNotifier.value = _withOptimisticBets(current);
    });
    _queueBetSend(bet);
    return true;
  }

  bool _isDefinitiveBetRejection(Object error) {
    if (error is! WheelApiException) return false;
    if (error.code == 'bet_processing' ||
        error.status == 408 ||
        error.status == 425 ||
        error.status == 429) return false;
    if (error.status != null && error.status! >= 400 && error.status! < 500) {
      return true;
    }
    return const {
      'round_closed',
      'insufficient_balance',
      'invalid_bet_data',
      'idempotency_key_reused',
      'game_not_active',
      'authentication_required',
      'permission_denied',
    }.contains(error.code);
  }

  // UI updates immediately; independent idempotent requests are sent
  // concurrently so one slow network response cannot hold later taps behind it.
  void _queueBetSend(_PendingWheelBet bet) {
    unawaited(_sendBet(bet));
  }

  Future<void> _sendBet(_PendingWheelBet bet, {Future<RoundState>? request}) async {
    if (!mounted || !_pendingBets.contains(bet) ||
        bet.status != _PendingBetStatus.queued) return;
    setState(() => bet.status = _PendingBetStatus.sending);
    try {
      final confirmed = await (request ?? widget.api.placeBet(
        bet.roundId,
        bet.slot,
        bet.amount,
        bet.idempotencyKey,
      )).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        bet.status = _PendingBetStatus.accepted;
        // Concurrent responses may arrive out of order; never restore an older,
        // higher balance over a newer lower balance.
        _bal = math.min(_bal, confirmed.balance).toInt();
        _rememberServerTotals(confirmed);
        if (_s?.roundId == confirmed.roundId) {
          _s = confirmed;
          _wheelStateNotifier.value = _withOptimisticBets(confirmed);
        }
        _pendingBets.remove(bet);
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      if (error is TimeoutException) {
        // Keep the local pending bet visible; retry with the same idempotency key.
        // No timeout diagnostic is shown; a late accepted response remains idempotent.
        setState(() => bet.status = _PendingBetStatus.queued);
        await Future<void>.delayed(const Duration(seconds: 1));
        if (mounted) await _sendBet(bet);
        return;
      }
      _say(wheelErrorText(error));
      if (_isDefinitiveBetRejection(error)) {
        setState(() {
          _pendingBets.remove(bet);
          final roundBets = _myBetsByRound[bet.roundId];
          if (roundBets != null && bet.slot >= 0 && bet.slot < kSlotKeys.length) {
            final key = kSlotKeys[bet.slot];
            final remaining = math.max(0, (roundBets[key] ?? 0) - bet.amount).toInt();
            if (remaining == 0) roundBets.remove(key); else roundBets[key] = remaining;
            final frozen = _frozenBetsByRound[bet.roundId];
            if (frozen != null) {
              // A definitive server rejection is the only event allowed to
              // subtract an unaccepted tap from the frozen settlement record.
              final revisedFrozen = Map<String, int>.from(frozen);
              final frozenRemaining =
                  math.max(0, (revisedFrozen[key] ?? 0) - bet.amount).toInt();
              if (frozenRemaining == 0) {
                revisedFrozen.remove(key);
              } else {
                revisedFrozen[key] = frozenRemaining;
              }
              _frozenBetsByRound[bet.roundId] =
                  Map<String, int>.unmodifiable(revisedFrozen);
            }
          }
          if (_s?.roundId == bet.roundId) {
            _wheelStateNotifier.value = _withOptimisticBets(_s!);
          }
        });
        unawaited(_refresh());
      } else {
        // Keep the optimistic amount and retry with the same idempotency key.
        setState(() => bet.status = _PendingBetStatus.queued);
        await Future<void>.delayed(const Duration(seconds: 1));
        if (mounted) await _sendBet(bet);
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
              colors: [
                Color(0xFF2F7DEE),
                Color(0xFF6CC4FF),
                Color(0xFFBFE6FF)
              ],
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
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: Column(children: [
                          _topBar(s),
                          SizedBox(
                            height: 40,
                            child: Row(children: [_playerBadge(s.player)]),
                          ),
                          ValueListenableBuilder<RoundState?>(
                            valueListenable: _wheelStateNotifier,
                            builder: (context, wheelState, _) => wheelState == null
                                ? const SizedBox.shrink()
                                : _wheel(wheelState),
                          ),
                        ]),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _bettingOpen(s) ? null : _showRoundClosedToast,
                        child: IgnorePointer(
                          ignoring: !_bettingOpen(s),
                          child: _platform(s),
                        ),
                      ),
                      _redFloor(s),
                    ]),
                  ),
                  _resultOverlay(_popupRoundState ?? s),
                  if (_roundClosedToast != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xDD222222),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              child: Text(
                                _roundClosedToast!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
          ),
        ),
      ),
    );
  }

  // نافذة النتيجة: تنزلق من تحت بعد كل جولة
  Widget _resultOverlay(RoundState s) => Stack(children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _panel ? 0.42 : 0,
              duration: const Duration(milliseconds: 450),
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: 0.6,
            widthFactor: 1,
            child: IgnorePointer(
              ignoring: !_panel,
              child: AnimatedSlide(
                offset: _panel ? Offset.zero : const Offset(0, 1.05),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                child: _resultPanel(s),
              ),
            ),
          ),
        ),
      ]);

  Widget _resultPanel(RoundState s) {
    final food = kSlots[(s.resultSlot ?? 0).clamp(0, kSlots.length - 1)].emoji;
    final mine = _myBetTotalForRound(s.roundId);
    final winningGroupKey = (s.resultSlot != null && const [1, 2, 4, 6].contains(s.resultSlot))
        ? 'pizza_group'
        : 'salad_group';
    final winningGroupName = winningGroupKey == 'pizza_group' ? 'البيتزا' : 'السلطة';
    final winningGroupBet = _groupBetForRound(s.roundId, winningGroupKey);
    final groupResultText = winningGroupBet > 0
        ? '$winningGroupName: رهانك ${_fmt(winningGroupBet)} × 2 = ${_fmt(winningGroupBet * 2)}'
        : (winningGroupKey == 'pizza_group'
            ? 'البيتزا تفوز مع أي خضار — ×2'
            : 'السلطة تفوز مع أي لحم — ×2');
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
      child: SingleChildScrollView(
        child: Stack(children: [
          Positioned(
            top: 0,
            left: 0,
            child: Container(
                width: 92,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: const Color(0xFF173C91),
                  border: Border.all(color: const Color(0xFFFFD45A), width: 2),
                ),
                child: ValueListenableBuilder<int>(
                  valueListenable: _popupTimeLeftNotifier,
                  builder: (context, seconds, _) => Text('(${seconds.clamp(1, 5)}) ثانية',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900)),
                ),
              ),
          ),
          Column(children: [
            SizedBox(
              height: 72,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CustomPaint(
                      size: const Size(20, 58), painter: _CutleryPainter(true)),
                  const SizedBox(width: 12),
                  Container(
                    width: 68,
                    height: 68,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFFFDF5),
                      border: Border.all(
                          color: const Color(0xFFD9E2F0), width: 5),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x550B1740),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                        BoxShadow(
                          color: Color(0xFFFFD45A),
                          blurRadius: 0,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFFE7D8B7), width: 1.5),
                      ),
                      child: Text(food, style: const TextStyle(fontSize: 42)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  CustomPaint(
                      size: const Size(20, 58), painter: _CutleryPainter(false)),
                ],
              ),
            ),
            Container(
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: const LinearGradient(
                  colors: [
                    Color(0x00FFD400),
                    Color(0xFFFFD400),
                    Color(0xFFFFD400),
                    Color(0x00FFD400)
                  ],
                  stops: [0, 0.15, 0.85, 1],
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('${s.roundId} نتيجة الجولة — $food', textAlign: TextAlign.center, style: t),
                Text('رهانك في هذه الجولة: $mine', textAlign: TextAlign.center, style: t),
                Text(groupResultText, textAlign: TextAlign.center, style: t),
                Text('الفائز في هذه الجولة: ${s.myPayout}', textAlign: TextAlign.center, style: t),
              ],
            ),
            const SizedBox(height: 4),
            const Text('الفائز الأكبر لهذه الجولة',
                style: TextStyle(
                    color: Color(0xFFFFD400),
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final i in [2, 0, 1])
                  Expanded(
                    child: i < s.topWinners.length
                        ? _podium(i, s.topWinners[i])
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _podium(int i, WheelWinner w) {
    const ring = [Color(0xFFFFD400), Color(0xFFD7DBE6), Color(0xFFE78B3C)];
    const badge = [Color(0xFFE6A100), Color(0xFF8A93A8), Color(0xFFC4661A)];
    const crown = [Color(0xFFFFFFFF), Color(0xFFBBBBBB), Color(0xFFFFB070)];
    const ribbon = [
      [Color(0xFFFFD45A), Color(0xFFF0A020)],
      [Color(0xFFF4F6FB), Color(0xFFC9CFDC)],
      [Color(0xFFFFB06A), Color(0xFFE0762A)],
    ];
    final size = i == 0 ? 74.0 : 60.0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ColorFiltered(
        colorFilter: ColorFilter.mode(crown[i], BlendMode.modulate),
        child: Transform.rotate(
            angle: -0.2, child: const Text('👑', style: TextStyle(fontSize: 26))),
      ),
      Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF7A5CFF),
            border: Border.all(color: ring[i], width: 4),
          ),
          child: ClipOval(
            child: SizedBox.expand(
              child: (w.avatarUrl ?? '').isNotEmpty
                  ? Image.network(w.avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink())
                  : const SizedBox.shrink(),
            ),
          ),
        ),
        Positioned(
          right: -6,
          bottom: -4,
          child: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: badge[i],
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Text('${i + 1}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: ribbon[i]),
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(6), bottom: Radius.circular(14)),
        ),
        child: Text(w.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Color(0xFF4A2A00),
                fontWeight: FontWeight.w800,
                fontSize: 12)),
      ),
      const SizedBox(height: 3),
      Text('${w.amount} 🪙',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
    ]);
  }

  Widget _errorBox() => Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('تعذر الاتصال بالخادم',
            style: TextStyle(color: Colors.white)),
        Text('$_err',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 10)),
        TextButton(onPressed: null, child: const Text('إعادة المحاولة')),
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
        _ib(const Icon(Icons.close, color: Colors.white, size: 28),
            () => Navigator.of(context).maybePop()),
        const SizedBox(width: 6),
        _pill(Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('جولة',
              style: TextStyle(color: Colors.white70, fontSize: 9, height: 1.1)),
          Text('${s.roundId}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.1,
                  fontWeight: FontWeight.bold)),
        ])),
        const Spacer(),
        _ib(const Icon(Icons.more_horiz, color: Colors.white, size: 24), _openMore),
        const SizedBox(width: 4),
        _trophyBtn(),
        const SizedBox(width: 4),
        _ib(const Icon(Icons.history, color: Colors.white, size: 24), _openLog),
        const SizedBox(width: 2),
        _ib(const Icon(Icons.settings, color: Colors.white, size: 24), _openSettings),
        const SizedBox(width: 4),
        _modeToggle(),
      ]);

  Widget _wheel(RoundState s) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, d = w * 0.27, ds = w * 0.22; // d = المركز، ds = الدوائر
      return AnimatedBuilder(
        animation: _spinController,
        builder: (context, _) {
          final spinAngle = _spinAngleAtProgress(_spinController.value);
          return SizedBox(
            width: w,
            height: w,
            child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _SpokesPainter(d))),
          // Exactly one evenly spaced wheel node for each playable food.
          // Group bets (pizza/salad) are rendered only in _platform below.
          for (var i = 0; i < kSlots.length; i++)
            Positioned(
              left: w / 2 + w * 0.37 * math.sin(i * math.pi * 2 / kSlots.length) - ds / 2,
              top: w / 2 - w * 0.37 * math.cos(i * math.pi * 2 / kSlots.length) - ds / 2,
              width: ds,
              height: ds,
              child: _slot(i, s, ds, spinAngle),
            ),
          Center(
            child: Container(
              width: d,
              height: d,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF8A4B2A),
                border: Border.all(color: const Color(0xFF5A2F16), width: 4),
              ),
              child: _panel
                  ? const SizedBox.shrink()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: d * 0.12, vertical: d * 0.03),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE08F1E),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFB36B0F), width: 2),
                          ),
                          child: ValueListenableBuilder<int>(
                            valueListenable: _timeLeftNotifier,
                            builder: (context, seconds, _) => Text(
                              '${seconds}s',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: d * 0.26,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: d * 0.04),
                        SizedBox(
                          width: d * 0.9,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _isResultPhase(s) ? 'النتيجة القادمة' : 'وقت الرهان',
                              maxLines: 1,
                              softWrap: false,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
            ]),
          );
        },
      );
    });
  }

  int _displayMyBet(RoundState s, int slot) {
    return _foodBetForSlot(s.roundId, slot);
  }

  double _highlightForSlot(double angle, int slot) {
    if (!_spinHasResult) return 0;
    const step = math.pi * 2 / 8;
    final activeSlot = (angle / step).floor() % kSlots.length;
    return activeSlot == slot ? 1.0 : 0.0;
  }

  Widget _slot(int i, RoundState s, double d, double spinAngle) {
    final slot = kSlots[i];
    final myBet = _displayMyBet(s, i);
    final highlight = _highlightForSlot(spinAngle, i);
    final isSpinPosition = highlight >= 0.5;
    const dark = Color(0xFF5A3A00);
    return Material(
      type: MaterialType.transparency,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _onFoodPointerDown(i),
        child: SizedBox.expand(
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFF3C4),
                border: Border.all(
                  color: isSpinPosition
                      ? const Color(0xFFFF0000)
                      : const Color(0xFF8A4B2A),
                  width: isSpinPosition ? 8 : 4,
                ),
              ),
              child: ClipOval(
                child: Stack(children: [
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0xFFFFF3C4)),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: 0.45,
                      widthFactor: 1,
                      child: ColoredBox(
                        color: isSpinPosition
                            ? const Color(0xFFFF0000)
                            : const Color(0xFFFFD84D),
                      ),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, -0.58),
                    child: Text('x${slot.mult}',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                            color: dark,
                            fontSize: d * 0.15,
                            fontWeight: FontWeight.w800)),
                  ),
                  Align(
                    alignment: const Alignment(0, 0.20),
                    child: Text('${s.pools[i]} 🪙',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                            color: isSpinPosition
                                ? Colors.white
                                : dark,
                            fontSize: d * 0.17,
                            fontWeight: FontWeight.bold)),
                  ),
                  Align(
                    alignment: const Alignment(0, 0.67),
                    child: Text('$myBet',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                            color: const Color(0xFF1458D4),
                            fontSize: d * 0.15,
                            fontWeight: FontWeight.w800)),
                  ),
                ]),
              ),
            ),
            Positioned(
              top: -d * 0.22,
              left: 0,
              right: 0,
              child: Center(
                  child: Text(slot.emoji,
                      style: TextStyle(fontSize: d * 0.38))),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _special(String key, String label, RoundState s) {
    final on = _lit == key;
    final total = _serverGroupTotalForRound(s.roundId, key);
    final mine = _groupBetForRound(s.roundId, key);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onGroupPointerDown(key),
      child: Container(
        constraints: const BoxConstraints(minWidth: 112),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFFFD400) : const Color(0xFFFFF5DE),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF6B3A1E), width: 2),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(key == 'salad_group' ? '🥗' : '🍕', style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Color(0xFF4A2A10), fontWeight: FontWeight.w800, fontSize: 14)),
          ]),
          Text('${_fmt(total)} 🪙', maxLines: 1, style: const TextStyle(color: Color(0xFF5A3A00), fontSize: 13, fontWeight: FontWeight.bold)),
          Text(_fmt(mine), maxLines: 1, style: const TextStyle(color: Color(0xFF1458D4), fontSize: 12, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  Widget _platform(RoundState s) => Stack(clipBehavior: Clip.none, children: [
        Column(children: [
          CustomPaint(
              painter: _PlatTopPainter(),
              child: const SizedBox(height: 30, width: double.infinity)),
          CustomPaint(
            painter: _PlatFacePainter(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 34, 10, 16),
              child: _platformBody(s),
            ),
          ),
        ]),
        Positioned(
          top: -46,
          left: 8,
          right: 8,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _special('pizza_group', 'البيتزا', s),
              _special('salad_group', 'السلطة', s),
            ],
          ),
        ),
      ]);

  Widget _pills(RoundState s) => Row(children: [
        Expanded(child: _plPill('فائز اليوم', '${_fmt(_todayWin)} ⭐')),
        const SizedBox(width: 8),
        Expanded(child: _plPill('سجلي', '')),
        const SizedBox(width: 8),
        Expanded(child: _plPill('العملات المتبقية', '${_fmt(math.max(0, _bal - _pendingReserved))} 🪙')),
      ]);

  Widget _plPill(String label, String value) => Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF5DE),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFF6B3A1E), width: 2),
        ),
        child: value.isEmpty
            ? Text(label,
                style: const TextStyle(
                    color: Color(0xFF4A2A10),
                    fontSize: 15,
                    fontWeight: FontWeight.bold))
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF4A2A10), fontSize: 11)),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF4A2A10),
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ]),
      );

  Widget _redFloor(RoundState s) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 34, 12, 20),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFC4755), Color(0xFFC91E31)],
            stops: [0, 0.45],
          ),
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            top: -30,
            left: 24,
            right: 24,
            child: Container(
              height: 14,
              decoration: const BoxDecoration(
                color: Color(0xFF870816),
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(14)),
              ),
            ),
          ),
          Column(children: [
            SizedBox(
              height: 13, // كان 30: رفعت الصناديق 17 بكسل
              child: Center(
                child: Text(_msg ?? '',
                    style: const TextStyle(
                        color: Color(0xFFFFE36A),
                        fontSize: 13,
                        height: 1.0,
                        fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 8),
            _pills(s),
            const SizedBox(height: 14),
            _chestBar(s),
            _history(s),
            if (_showBets) _betFeed(s),
            if (_err != null) _errorBox(),
          ]),
        ]),
      );

  Widget _chestBar(RoundState s) {
    final n = s.chestThresholds.length;
    var fill = 1.0;
    if (s.chestIndex < n) {
      final prev = s.chestIndex == 0 ? 0 : s.chestThresholds[s.chestIndex - 1];
      final next = s.chestThresholds[s.chestIndex];
      final frac = ((s.chestTotal - prev) / (next - prev)).clamp(0.0, 1.0);
      fill = (s.chestIndex + frac) / n;
    }
    return Column(children: [
      SizedBox(
        height: 56,
        child: Stack(alignment: Alignment.center, children: [
          Container(
              height: 16,
              decoration: BoxDecoration(
                  color: const Color(0xFF8A0A1E),
                  borderRadius: BorderRadius.circular(8))),
          Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: fill,
              child: Container(
                  height: 16,
                  decoration: BoxDecoration(
                      color: const Color(0xFFFFB400),
                      borderRadius: BorderRadius.circular(8))),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [for (var i = 0; i < n; i++) _chest(i, s)],
          ),
        ]),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < n; i++)
            SizedBox(
              width: 56,
              child: Text(_mil(s.chestThresholds[i]),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
            ),
        ],
      ),
      const SizedBox(height: 10),
    ]);
  }

  Widget _chest(int i, RoundState s) {
    final done = i < s.chestIndex, cur = i == s.chestIndex;
    return SizedBox(
      width: 56,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        Opacity(
          opacity: done || cur ? 1 : 0.7,
          child: Text('🧰',
              style: TextStyle(
                  fontSize: 40,
                  shadows: cur
                      ? const [Shadow(color: Color(0xFFFFD400), blurRadius: 14)]
                      : null)),
        ),
        if (done)
          Positioned(
            top: 0,
            right: 2,
            child: Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Color(0xFF2FBF5A)),
              child: const Icon(Icons.check, size: 12, color: Colors.white),
            ),
          ),
      ]),
    );
  }

  // ---- المنصة: وضع الرهان التلقائي + رقائق الرهان ----
  Widget _platformBody(RoundState s) => Column(children: [
        const SizedBox(height: 6),
        _chipTiles(s),
      ]);

  Widget _chipTiles(RoundState s) => Row(children: [
        for (var i = 0; i < _chipSet.length; i++) Expanded(child: _chipTile(i)),
      ]);

  Future<void> _showCustomChipDialog() async {
    final controller = TextEditingController(text: _chip.toString());
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مبلغ الرهان'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(hintText: 'أدخل أي مبلغ'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          TextButton(
            onPressed: () {
              final amount = int.tryParse(controller.text);
              Navigator.pop(context, amount);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || value == null) return;
    if (value <= 0 || value > _bal - _pendingReserved) {
      _say('رصيدك ما يكفي');
      return;
    }
    setState(() => _chip = value);
  }

  Widget _chipTile(int i) {
    final v = _chipSet[i], sel = _chip == v;
    return GestureDetector(
      onTap: () => setState(() => _chip = v),
      onLongPress: _showCustomChipDialog,
      child: Container(
        height: 78,
        margin: const EdgeInsets.symmetric(horizontal: 2.5),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF7A4A1E) : const Color(0xFFFBE6C2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: sel ? const Color(0xFF1EF04B) : const Color(0xFFD9B77A),
              width: sel ? 3 : 1),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          _coinStack(i + 1),
          const SizedBox(height: 4),
          _valuePill(v >= 1000000 ? _mil(v) : '$v'),
        ]),
      ),
    );
  }

  Widget _valuePill(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF5DE),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF4A2A10), width: 1.5),
        ),
        child: Text(t,
            style: const TextStyle(
                color: Color(0xFF4A2A10),
                fontWeight: FontWeight.w800,
                fontSize: 11)),
      );

  Widget _coinStack(int n) {
    const rows = {
      1: [1],
      2: [2],
      3: [2, 1],
      4: [2, 2],
      5: [3, 2],
    };
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final r in rows[n]!)
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (var k = 0; k < r; k++)
            const Text('🪙', style: TextStyle(fontSize: 17)),
        ]),
    ]);
  }

  /// "وضع رهان": يكرر رهانات الجولة السابقة مرة وحدة
  Widget _repeatTile(bool on) => GestureDetector(
        onTap: on ? _repeatBets : () => _say('ما فيه رهان سابق أو الجولة منتهية'),
        child: Opacity(
          opacity: on ? 1 : 0.55,
          child: Container(
            height: 78,
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            decoration: BoxDecoration(
              color: const Color(0xFFF1E3C8),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD9B77A)),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.replay, size: 30, color: Color(0xFF9A6A3A)),
              const SizedBox(height: 4),
              _valuePill('وضع رهان'),
            ]),
          ),
        ),
      );

  Future<void> _repeatBets() async {
    final s = _s;
    if (s == null || s.phase != RoundPhase.betting) {
      return _say('انتظر الجولة القادمة');
    }
    if (!_prevBets.values.any((b) => b > 0)) return _say('ما فيه رهان سابق');
    if (_myBetTotalForRound(s.roundId) > 0 ||
        _pendingBets.any((bet) => bet.roundId == s.roundId)) {
      return _say('رهانك موجود في هذه الجولة');
    }
    for (var i = 0; i < kSlotKeys.length; i++) {
      final amount = _prevBets[kSlotKeys[i]] ?? 0;
      if (amount <= 0) continue;
      if (!_enqueueBet(s.roundId, i, amount)) break;
    }
  }

  // ---- الشريط العلوي ----
  Widget _ib(Widget icon, VoidCallback onTap) => IconButton(
        onPressed: onTap,
        icon: icon,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      );

  Widget _trophyBtn() => GestureDetector(
        onTap: _openTopWins,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF9AD8FF),
            border: Border.all(color: const Color(0xFFF2C24B), width: 2),
          ),
          child: const Text('🏆', style: TextStyle(fontSize: 20)),
        ),
      );

  Widget _modeToggle() {
    Widget seg(String m, String label) => GestureDetector(
          onTap: () => _setMode(m),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: _mode == m ? const Color(0xFF7A22FF) : const Color(0x8014087A),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xB3FFFFFF), width: 2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('n', 'عادي'),
        seg('a', 'متقدم'),
      ]),
    );
  }

  void _setMode(String m) {
    if (m == _mode) return;
    setState(() {
      _mode = m;
      _chip = _chipSet.first;
    });
    _say(m == 'a' ? 'وضع متقدم: رهانات أكبر' : 'الوضع العادي');
  }

  void _openMore() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF4A3DF0),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.replay, color: Colors.white),
              title: const Text('تكرار الرهان السابق',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _repeatBets();
              },
            ),
            SwitchListTile(
              value: _showBets,
              secondary: const Icon(Icons.visibility, color: Colors.white),
              title: const Text('عرض رهانات اللاعبين',
                  style: TextStyle(color: Colors.white)),
              onChanged: (value) => setState(() => _showBets = value),
            ),
            SwitchListTile(
              value: _sound,
              secondary: const Icon(Icons.volume_up, color: Colors.white),
              title: const Text('تشغيل الصوت',
                  style: TextStyle(color: Colors.white)),
              onChanged: (value) => setState(() => _sound = value),
            ),
          ]),
        ),
      ),
    );
  }

  void _openSettings() {
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF4A3DF0),
            title: const Text('إعدادات', style: TextStyle(color: Colors.white)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              SwitchListTile(
                value: _sound,
                onChanged: (v) {
                  setState(() => _sound = v);
                  setD(() {});
                },
                title: const Text('تشغيل الصوت',
                    style: TextStyle(color: Colors.white)),
              ),
              SwitchListTile(
                value: _showBets,
                onChanged: (v) {
                  setState(() => _showBets = v);
                  setD(() {});
                },
                title: const Text('عرض قائمة وضع الرهان في الغرفة',
                    style: TextStyle(color: Colors.white)),
              ),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('حسنًا')),
            ],
          ),
        ),
      ),
    );
  }

  /// سجلي: من الخادم، وإذا تعذر أو كان فاضي نعرض جولات هذه الجلسة
  Future<List<MyRoundRecord>> _loadLog() async {
    try {
      final server = await widget.api.fetchMyHistory();
      if (server.isNotEmpty) return server;
    } catch (_) {}
    return [
      for (final e in _log)
        MyRoundRecord(
            round: e.round, bet: e.bet, payout: e.payout, result: e.result),
    ];
  }

  void _openLog() {
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF4A3DF0),
          title: const Text('سجلي', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: FutureBuilder<List<MyRoundRecord>>(
              future: _loadLog(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                        child: CircularProgressIndicator(color: Colors.white)),
                  );
                }
                final list = snap.data ?? const <MyRoundRecord>[];
                if (list.isEmpty) {
                  return const Text('ما فيه جولات بعد',
                      style: TextStyle(color: Colors.white70));
                }
                return ListView(shrinkWrap: true, children: [
                  for (final e in list)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                          'جولة ${e.round}  ${e.result}   رهانك ${_fmt(e.bet)}   ربحك ${_fmt(e.payout)}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ),
                ]);
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق')),
          ],
        ),
      ),
    );
  }

  /// صورة اللاعب الحالي (من الخادم) مع علم الدولة
  Widget _playerBadge(WheelPlayer? p) {
    if (p == null) return const SizedBox(width: 38, height: 38);
    final initial =
        p.name.isEmpty ? '?' : String.fromCharCode(p.name.runes.first);
    final letter = Text(initial,
        style: const TextStyle(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800));
    final flag = _flagEmoji(p.flag);
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF7A5CFF),
          border: Border.all(color: const Color(0xFFF2C24B), width: 2),
        ),
        child: ClipOval(
          child: SizedBox.expand(
            child: (p.avatarUrl ?? '').isNotEmpty
                ? Image.network(p.avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(child: letter))
                : Center(child: letter),
          ),
        ),
      ),
      if (flag != null)
        Positioned(
            right: -6,
            bottom: -4,
            child: Text(flag, style: const TextStyle(fontSize: 14))),
    ]);
  }

  /// "SA" → 🇸🇦 ، وإذا وصل إيموجي جاهز نستخدمه كما هو
  String? _flagEmoji(String? f) {
    if (f == null || f.isEmpty) return null;
    final up = f.toUpperCase();
    final isCode = up.length == 2 &&
        up.codeUnits.every((c) => c >= 0x41 && c <= 0x5A);
    if (!isCode) return f;
    return String.fromCharCodes(up.codeUnits.map((c) => 0x1F1E6 + c - 0x41));
  }

  // ---- شريط النتائج: دوائر بيضاء، وآخر نتيجة عليها NEW ----
  Widget _history(RoundState s) => Container(
        width: double.infinity,
        height: 80,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: const Color(0xFFE6515C),
            borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Text('النتيجة:',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < s.history.length; i++)
                  _histBadge(s.history[i], i == 0),
              ],
            ),
          ),
        ]),
      );

  Widget _histBadge(String e, bool isNew) => Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 6),
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: const Color(0xFFFFD9DC), width: 2),
            ),
            child: Text(e, style: const TextStyle(fontSize: 28)),
          ),
          if (isNew)
            Positioned(
              bottom: -3,
              left: 6,
              right: 6,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD400),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.black, width: 1),
                ),
                child: const Text('NEW',
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 9,
                        fontWeight: FontWeight.w900)),
              ),
            ),
        ]),
      );

  // ---- رهانات كل اللاعبين مباشرة (نفس الطاولة للكل) ----
  Widget _betFeed(RoundState s) => Container(
        margin: const EdgeInsets.only(top: 10),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
            color: const Color(0x33000000),
            borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Text('👥 ${s.players}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: s.recentBets.isEmpty
                ? const Text('رهانات اللاعبين تظهر هنا مباشرة',
                    style: TextStyle(color: Colors.white60, fontSize: 12))
                : ListView(
                    scrollDirection: Axis.horizontal,
                    children: [for (final b in s.recentBets) _betChip(b)],
                  ),
          ),
        ]),
      );

  Widget _betChip(BetEvent b) => Container(
        margin: const EdgeInsets.only(left: 6, top: 7, bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x33FFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: b.isMe
              ? Border.all(color: const Color(0xFFFFD400), width: 1.5)
              : null,
        ),
        child: Text(
            '${b.name} ${(b.slot < 0 || b.slot > 7) ? '?' : kSlots[b.slot].emoji} ${_fmt(b.amount)}',
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      );

  void _openTopWins() {
    showDialog(
      context: context,
      builder: (_) => _TopWinsDialog(api: widget.api),
    );
  }

  void _showRules() {
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF4A3DF0),
          content: const Text(
            '1. وقت الرهان 20 ثانية، ثم دوران 5 ثوانٍ، ثم نافذة النتيجة 5 ثوانٍ.\n'
            '2. يمكنك الرهان على 6 أكلات كحد أقصى، وأي مبلغ حتى رصيدك.\n'
            '3. المضاعفات: دجاج x45، ذرة x5، طماطم x5، ماعز x15، فلفل x5، سمك x25، جزر x5، روبيان x10.\n'
            '4. بيتزا 3%: تفوز كل رهانات الخضروات. سلطة 3%: تفوز كل رهانات اللحوم.\n'
            '5. أوزان النتائج العادية المنشورة (تقريبية): دجاج 2.03%، ذرة 18.27%، طماطم 18.27%، ماعز 6.09%، فلفل 18.27%، سمك 3.65%، جزر 18.27%، روبيان 9.14%.',
            style: TextStyle(color: Colors.white, height: 1.8, fontSize: 13),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('حسنًا')),
          ],
        ),
      ),
    );
  }
}

// ---------- التلال + الهيكل الخشبي A + ألواح الأعواد + حلقة المركز ----------
class _SpokesPainter extends CustomPainter {
  final double d; // قطر الدائرة
  _SpokesPainter(this.d);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final c = size.center(Offset.zero);

    // التلال
    canvas.drawOval(Rect.fromLTWH(-w * 0.35, h * 0.80, w * 1.0, h * 0.5),
        Paint()..color = const Color(0xFF7CCF63));
    canvas.drawOval(Rect.fromLTWH(w * 0.25, h * 0.84, w * 1.2, h * 0.5),
        Paint()..color = const Color(0xFF9BD465));

    // الهيكل الخشبي على شكل حرف A (بفتحة قوس وعارضة)
    final sw = w * 0.70, u = sw / 100, uy = u * 1.3; // أكبر وأطول (uy = مقياس الارتفاع)
    final ox = c.dx - sw / 2, oy = h + 4 - 64 * uy; // الأرجل تنزل 4 بكسل داخل المنصة
    Offset p(double x, double y) => Offset(ox + x * u, oy + y * uy);
    final frame = Path()..fillType = PathFillType.evenOdd;
    frame.addPolygon([p(37, 0), p(63, 0), p(100, 64), p(0, 64)], true);
    frame.moveTo(p(35, 27).dx, p(35, 27).dy);
    frame.lineTo(p(35, 19).dx, p(35, 19).dy);
    frame.quadraticBezierTo(
        p(35, 12.5).dx, p(35, 12.5).dy, p(50, 12.5).dx, p(50, 12.5).dy);
    frame.quadraticBezierTo(
        p(65, 12.5).dx, p(65, 12.5).dy, p(65, 19).dx, p(65, 19).dy);
    frame.lineTo(p(65, 27).dx, p(65, 27).dy);
    frame.close();
    frame.addPolygon([p(31, 41.7), p(69, 41.7), p(77, 64), p(23, 64)], true);
    canvas.drawPath(frame, Paint()..color = const Color(0xFFDD964A));
    canvas.save();
    canvas.clipPath(frame);
    final grain = Paint()
      ..color = const Color(0xFFC8823A)
      ..strokeWidth = u * 0.4;
    for (double x = 0; x < 100; x += 3) {
      canvas.drawLine(p(x, 0), p(x, 64), grain);
    }
    canvas.restore();
    canvas.drawPath(
        frame,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.9
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF6B3A1E));
    // بقع الظل على العارضة
    for (final sx in [25.0, 75.0]) {
      canvas.save();
      canvas.translate(p(sx, 35).dx, p(sx, 35).dy);
      canvas.rotate(sx < 50 ? 0.25 : -0.25);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: u * 5.2, height: uy * 14),
          Paint()..color = const Color(0x526B3A1E));
      canvas.restore();
    }
    // ألواح القاعدة الكريمية
    for (final fx in [-1.5, 76.5]) {
      final rr = RRect.fromRectAndRadius(
          Rect.fromLTWH(p(fx, 62).dx, p(fx, 62).dy, 25 * u, 2.6 * uy),
          Radius.circular(u * 0.8));
      canvas.drawRRect(rr, Paint()..color = const Color(0xFFEFDAA9));
      canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = u * 0.4
            ..color = const Color(0xFF6B3A1E));
    }

    // ألواح الأعواد (خشب أحمر مع مسمار)
    final plank = Paint()..color = const Color(0xFFA9553B);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF7B3524);
    final peg = Paint()..color = const Color(0xFFFFF5DE);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final pc = Offset(c.dx + w * 0.19 * math.sin(a), c.dy - w * 0.19 * math.cos(a));
      canvas.save();
      canvas.translate(pc.dx, pc.dy);
      canvas.rotate(a);
      final rr = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w * 0.038, height: w * 0.14),
          const Radius.circular(3));
      canvas.drawRRect(rr, plank);
      canvas.drawRRect(rr, edge);
      canvas.drawCircle(Offset.zero, 3.5, peg);
      canvas.restore();
    }

    // حلقة المركز مع اللمبات
    canvas.drawCircle(
        c,
        d * 0.56,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = d * 0.1
          ..color = const Color(0xFFC08A55));
    for (var k = 0; k < 14; k++) {
      final a = k * 2 * math.pi / 14;
      canvas.drawCircle(
          Offset(c.dx + d * 0.56 * math.sin(a), c.dy - d * 0.56 * math.cos(a)),
          d * 0.03,
          peg);
    }
  }

  @override
  bool shouldRepaint(_SpokesPainter old) => old.d != d;
}

// ---------- المنصة الخشبية: السطح العلوي ----------
class _PlatTopPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..addPolygon(
          [Offset(w * 0.06, 0), Offset(w * 0.94, 0), Offset(w, h), Offset(0, h)],
          true);
    canvas.drawPath(
        path,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFECC26F), Color(0xFFE0A456)],
          ).createShader(Offset.zero & size));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF6B3A1E));
  }

  @override
  bool shouldRepaint(_PlatTopPainter old) => false;
}

// ---------- المنصة الخشبية: الوجه الأمامي بخطوط مائلة ----------
class _PlatFacePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndCorners(Offset.zero & size,
        bottomLeft: const Radius.circular(24),
        bottomRight: const Radius.circular(24));
    canvas.drawRRect(r, Paint()..color = const Color(0xFFD89046));
    canvas.save();
    canvas.clipRRect(r);
    final hatch = Paint()
      ..color = const Color(0xFFCC8440)
      ..strokeWidth = 2;
    for (double x = -size.height; x < size.width; x += 11) {
      canvas.drawLine(
          Offset(x, size.height), Offset(x + size.height * 0.47, 0), hatch);
    }
    canvas.restore();
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 3),
        Paint()..color = const Color(0xFFEFC98A));
    canvas.drawRRect(
        r.deflate(1.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFF6B3A1E));
  }

  @override
  bool shouldRepaint(_PlatFacePainter old) => false;
}

// ---------- الشوكة والسكين ----------
class _CutleryPainter extends CustomPainter {
  final bool fork;
  _CutleryPainter(this.fork);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 19, size.height / 64);
    final fill = Paint()..color = const Color(0xFFE9EDF6);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF8D96AD);
    void rr(double x, double y, double w, double h, double r) {
      final b = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h), Radius.circular(r));
      canvas.drawRRect(b, fill);
      canvas.drawRRect(b, line);
    }

    if (fork) {
      rr(3, 2, 3, 20, 1.5);
      rr(8, 2, 3, 20, 1.5);
      rr(13, 2, 3, 20, 1.5);
      rr(3, 18, 13, 8, 3);
      rr(7, 24, 5, 38, 2.5);
    } else {
      final blade = Path()
        ..moveTo(5, 2)
        ..cubicTo(13, 4, 15, 16, 12, 34)
        ..lineTo(5, 34)
        ..close();
      canvas.drawPath(blade, fill);
      canvas.drawPath(blade, line);
      rr(5, 32, 7, 30, 3);
    }
  }

  @override
  bool shouldRepaint(_CutleryPainter old) => false;
}

// ======================================================================
// نافذة جدول أقوى الفائزين
// ======================================================================
class _TopWinsDialog extends StatefulWidget {
  final FoodWheelApi api;
  const _TopWinsDialog({required this.api});

  @override
  State<_TopWinsDialog> createState() => _TopWinsDialogState();
}

class _TopWinsDialogState extends State<_TopWinsDialog> {
  late Future<List<WinRecord>> _f;
  @override
  void initState() {
    super.initState();
    _f = widget.api.fetchTopWins();
  }

  /// الوقت المتبقي لتصفير الجدول (منتصف الليل بتوقيت UTC+3)
  String _left() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 3));
    final next = DateTime.utc(now.year, now.month, now.day + 1);
    final d = next.difference(now);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Widget _avatar(WinRecord r, double size, Color ring) {
    final initial =
        r.name.isEmpty ? '?' : String.fromCharCode(r.name.runes.first);
    final letter = Text(r.isMe ? '⭐' : initial,
        style: const TextStyle(
            color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800));
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF6B7CFF),
          border: Border.all(color: ring, width: size > 60 ? 5 : 2),
        ),
        child: ClipOval(
          child: SizedBox.expand(
            child: (r.avatarUrl ?? '').isNotEmpty
                ? Image.network(r.avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(child: letter))
                : Center(child: letter),
          ),
        ),
      ),
      if (r.flag != null)
        Positioned(
            right: -8,
            bottom: -4,
            child: Text(r.flag!, style: const TextStyle(fontSize: 20))),
    ]);
  }

  Widget _pill(WinRecord r) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
            color: const Color(0xFF6B7CFF),
            borderRadius: BorderRadius.circular(26)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${r.amount}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          const SizedBox(width: 6),
          Text(r.food, style: const TextStyle(fontSize: 22)),
        ]),
      );

  Widget _topCard(WinRecord r) => Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('👑', style: TextStyle(fontSize: 30)),
        _avatar(r, 88, const Color(0xFFF2C24B)),
        const SizedBox(height: 6),
        Text(r.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        _pill(r),
      ]);

  Widget _row(int rank, WinRecord r) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
            color: const Color(0xD927458A),
            borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          SizedBox(
            width: 26,
            child: Text('$rank',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          _avatar(r, 46, Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(r.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
          ),
          _pill(r),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(14),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.82),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF4A86EE), Color(0xFF5A2FE6)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFCFE0FF), width: 3),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const _TopWinsRules(),
                    ),
                    icon: const Icon(Icons.help_outline, color: Colors.white),
                  ),
                  Row(children: [
                    const Icon(Icons.timer_outlined, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(_left(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                  ]),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
              Flexible(
                child: FutureBuilder<List<WinRecord>>(
                  future: _f,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }
                    final list = snap.data ?? [];
                    if (snap.hasError || list.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(40),
                        child: Text('لا توجد بيانات بعد',
                            style: TextStyle(color: Colors.white70)),
                      );
                    }
                    return SingleChildScrollView(
                      child: Column(children: [
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 14),
                          decoration: BoxDecoration(
                              color: const Color(0xFF27458A),
                              borderRadius: BorderRadius.circular(22)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < 2 && i < list.length; i++)
                                Expanded(child: _topCard(list[i])),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (var i = 2; i < list.length; i++) _row(i + 1, list[i]),
                      ]),
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
}

// ======================================================================
// نافذة شرح جدول أقوى الفائزين (علامة الاستفهام): القواعد + جدول المكافآت
// ======================================================================
class _TopWinsRules extends StatelessWidget {
  const _TopWinsRules();

  // [المركز، مبلغ المكافأة، معها إطار؟]  (أرقام المكافآت من تصميمك، عدّلها حسب لعبتك)
  static const _rewards = [
    ['1', '3000000', '1'],
    ['2', '1500000', '1'],
    ['3', '750000', '1'],
    ['4 - 10', '375000', '0'],
    ['11 - 20', '150000', '0'],
    ['21 - 50', '75000', '0'],
    ['51 - 100', '37500', '0'],
  ];

  static const _t = TextStyle(color: Colors.white, fontSize: 14, height: 1.8);

  Widget _cell(String text, {bool head = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: head ? FontWeight.w600 : FontWeight.normal)),
        ),
      );

  Widget _badge(String emoji) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 12),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 40)),
          const SizedBox(width: 10),
          const Text('(صالح لمدة يوم واحد)',
              style: TextStyle(color: Colors.white, fontSize: 13)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(14),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2E87F6), Color(0xFF6A2FF0)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFCFE0FF), width: 3),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 28),
                    ),
                  ),
                  const Text(
                      '1. يتم ترتيب لوحة الصدارة بناءً على أعلى مبلغ فوز حققه اللاعب في مباراة واحدة خلال يوم واحد.',
                      style: _t),
                  const SizedBox(height: 10),
                  const Text(
                      '2. يتم احتساب الإحصاءات اليومية من الساعة 00:00:00 حتى 23:59:59 حسب توقيت UTC+3.',
                      style: _t),
                  const SizedBox(height: 10),
                  const Text(
                      '3. عند وضع أول رهان بمبلغ 50,000 رمز في جولة واحدة خلال اليوم، ستحصل على المكافأة المقابلة.',
                      style: _t),
                  _badge('🎖️'),
                  const Text(
                      '4. عند الحصول على مكافأة 100,000 عملة ذهبية لأول مرة في جولة واحدة خلال اليوم، ستحصل على المكافأة المقابلة.',
                      style: _t),
                  _badge('🏅'),
                  const Text('5. مكافأة لوحة الصدارة للاعبين هي كما يلي:',
                      style: _t),
                  const SizedBox(height: 8),
                  Table(
                    border: TableBorder.all(color: Colors.white, width: 1),
                    columnWidths: const {
                      0: FractionColumnWidth(0.28),
                      1: FlexColumnWidth(),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      TableRow(
                        decoration:
                            const BoxDecoration(color: Color(0x1FFFFFFF)),
                        children: [_cell('المركز', head: true), _cell('المكافأة', head: true)],
                      ),
                      for (final r in _rewards)
                        TableRow(children: [
                          _cell(r[0]),
                          _cell(r[2] == '1'
                              ? '🪙 ${r[1]}  +  🏵️ ×1 اليوم'
                              : '🪙 ${r[1]}'),
                        ]),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Center(
                    child: Text(
                        'Happy Live تحتفظ بالحق في التفسير النهائي لهذه الفعالية.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 12)),
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
/// Spin accelerates in stages and holds maximum speed through the final second.

