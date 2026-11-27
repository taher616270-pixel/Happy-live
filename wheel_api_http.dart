import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'food_wheel_game.dart';
import 'session_bridge.dart';

// ======================================================================
// الاتصال الحقيقي بخادم Happy Live (للمتصفح والتطبيق).
//
// الأمان:
//  - يستخدم توكن جلسة اللعبة المؤقت فقط (15 دقيقة)، ويستقبله من التطبيق
//    الرئيسي عبر postMessage (انظر session_bridge_web.dart).
//  - توكن الدخول الأصلي لـ Happy Live ما يمر باللعبة ولا بالرابط.
//  - مفتاح الخادم (التسوية settle) ما له مكان هنا أبدًا: هو سرّ في الخادم فقط.
//  - اللعبة ما تحدد نتيجة ولا تعدّل رصيدًا: كل شي يجي من الخادم.
//
// تنبيه مهم عن المسارات:
//  المسارات تحت (game/food-wheel/...) "مقترحة" وغير مؤكدة التنفيذ في الخادم الحالي.
//  هذا الملف ما يفترض نجاحها: لو الخادم ما يدعمها يرجع الخطأ
//  backend_not_implemented ويظهر للاعب بوضوح، ولا يتحول لبيانات تجريبية أبدًا.
//
// شكل رد الحالة المتوقع (GET state) هو نفس RoundState.fromJson في ملف اللعبة، مع:
//   round_id (رقم الجولة للعرض)، round_uuid (معرّف الجولة للرهان)،
//   player { id, name, avatar, flag, status }، balance (رصيد المحفظة الحقيقي).
// ترتيب الخانات 0 إلى 7 هو نفس kSlots في ملف اللعبة.
// ======================================================================

class WheelApiConfig {
  static const gameId = 'ed1490b4-c868-46bc-be7e-1448d5bdf498'; // عام، مو سرّي
  static const base = 'https://happy-live-api.taher616270.workers.dev/api/v1';
}

class _Paths {
  static const state = '/game/food-wheel/state';
  static String bet(String roundUuid) =>
      '/game/food-wheel/rounds/${Uri.encodeComponent(roundUuid)}/bets';
  static const history = '/game/food-wheel/history?limit=20';
  static const topWins = '/game/food-wheel/top-wins';
}

class HttpFoodWheelApi implements FoodWheelApi {
  static const _timeout = Duration(seconds: 10);
  static const _sessionTtl = Duration(minutes: 15);
  static const _refreshAfter = Duration(minutes: 12);

  final GameSessionBridge bridge;
  final http.Client _c;

  /// رقم الجولة (للعرض) ← معرّف الجولة عند الخادم
  final Map<int, String> _uuidByRound = {};
  DateTime? _askedAt;

  HttpFoodWheelApi({required this.bridge, http.Client? client})
      : _c = client ?? http.Client();

  // ---------------------------------------------------------------
  // الجلسة: تُستقبل من التطبيق الرئيسي وتُجدَّد قبل انتهائها
  // ---------------------------------------------------------------
  bool _canAsk() =>
      _askedAt == null ||
      DateTime.now().difference(_askedAt!) > const Duration(seconds: 30);

  Future<String> _token({bool forceFresh = false}) async {
    final before = bridge.receivedAt;
    final token = await bridge.waitForSession();
    final age = DateTime.now().difference(bridge.receivedAt ?? DateTime.now());

    // نطلب جلسة جديدة لو قاربت على الانتهاء، أو لو الخادم رفض الحالية
    if ((forceFresh || age >= _refreshAfter) && _canAsk()) {
      _askedAt = DateTime.now();
      bridge.requestRefresh();
      final next = await bridge.waitForNext(const Duration(seconds: 8));
      if (next != null) return next;
    }

    final cur = bridge.latest ?? token;
    final curAge =
        DateTime.now().difference(bridge.receivedAt ?? DateTime.now());
    // الخادم رفض الجلسة وما وصلت جلسة جديدة: لا نعيد استخدام نفس الجلسة المرفوضة
    if (forceFresh && cur == token && bridge.receivedAt == before) {
      throw const WheelApiException('session_expired');
    }
    if (curAge >= _sessionTtl) throw const WheelApiException('session_expired');
    return cur;
  }

  // ---------------------------------------------------------------
  // طلب عام: ترويسة الجلسة، مهلة، تجديد عند 401، وإعادة آمنة عند انقطاع الشبكة
  // ---------------------------------------------------------------
  Future<dynamic> _request(String method, String path,
      {Map<String, dynamic>? body, String? idempotencyKey}) async {
    final uri = Uri.parse('${WheelApiConfig.base}$path');
    final retryable = method == 'GET' || idempotencyKey != null;
    var attempts = 0;
    var forceFresh = false;
    while (true) {
      attempts++;
      final token = await _token(forceFresh: forceFresh);
      final headers = <String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (method == 'POST') 'Content-Type': 'application/json',
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      };
      http.Response r;
      try {
        final future = method == 'GET'
            ? _c.get(uri, headers: headers)
            : _c.post(uri,
                headers: headers, body: jsonEncode(body ?? <String, dynamic>{}));
        r = await future.timeout(_timeout);
      } on TimeoutException {
        if (attempts < 3 && retryable) continue;
        throw const WheelApiException('timeout');
      } on http.ClientException {
        if (attempts < 3 && retryable) continue;
        throw const WheelApiException('network');
      }
      if (r.statusCode == 401) {
        if (!forceFresh) {
          forceFresh = true;
          continue;
        }
        throw const WheelApiException('session_expired', status: 401);
      }
      return _decode(r);
    }
  }

  dynamic _decode(http.Response r) {
    final ok = r.statusCode >= 200 && r.statusCode < 300;
    dynamic body;
    if (r.bodyBytes.isNotEmpty) {
      try {
        body = jsonDecode(utf8.decode(r.bodyBytes));
      } catch (_) {
        body = null;
      }
    }
    if (ok) return body ?? <String, dynamic>{};
    var code = '';
    if (body is Map) code = '${body['error'] ?? body['code'] ?? ''}';
    if (code.isEmpty || (code == 'not_found' && r.statusCode == 404)) {
      switch (r.statusCode) {
        case 404:
        case 405:
        case 501:
          code = 'backend_not_implemented';
          break;
        case 403:
          code = 'forbidden';
          break;
        case 429:
          code = 'rate_limited';
          break;
        default:
          code = r.statusCode >= 500 ? 'server_error' : 'http_${r.statusCode}';
      }
    }
    throw WheelApiException(code, status: r.statusCode);
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    throw const WheelApiException('bad_response');
  }

  List<dynamic> _asList(dynamic v, List<String> keys) {
    if (v is List) return v;
    if (v is Map) {
      for (final k in keys) {
        final x = v[k];
        if (x is List) return x;
      }
    }
    throw const WheelApiException('bad_response');
  }

  // ---------------------------------------------------------------
  // واجهة اللعبة (FoodWheelApi)
  // ---------------------------------------------------------------
  @override
  Future<RoundState> fetchState() async {
    final j = _asMap(await _request('GET', _Paths.state));
    final RoundState s;
    try {
      s = RoundState.fromJson(j);
    } catch (_) {
      throw const WheelApiException('bad_response');
    }
    final uuid = j['round_uuid']?.toString();
    if (uuid != null && uuid.isNotEmpty) {
      _uuidByRound[s.roundId] = uuid;
      if (_uuidByRound.length > 6) {
        _uuidByRound.remove(_uuidByRound.keys.first);
      }
    }
    return s;
  }

  /// يرسل الرهان للخادم، ولا يرجع نجاحًا إلا بعد تأكيد الخادم،
  /// ثم يقرأ الحالة الفعلية (الرصيد ورهاناتك) من الخادم.
  @override
  Future<RoundState> placeBet(int roundId, int slot, int amount) async {
    final uuid = _uuidByRound[roundId];
    if (uuid == null) throw const WheelApiException('round_changed');
    await _request('POST', _Paths.bet(uuid),
        body: {'slot': slot, 'amount': amount}, idempotencyKey: _newKey());
    try {
      return await fetchState();
    } on WheelApiException {
      throw const WheelApiException('bet_ok_state_failed');
    }
  }

  @override
  Future<List<WinRecord>> fetchTopWins() async {
    final list = _asList(await _request('GET', _Paths.topWins), ['wins', 'items']);
    return list
        .map((e) => WinRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<List<MyRoundRecord>> fetchMyHistory() async {
    final list =
        _asList(await _request('GET', _Paths.history), ['rounds', 'items', 'history']);
    return list
        .map((e) => MyRoundRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// مفتاح idempotency عشوائي (UUID v4): نفس الرهان لو أُعيد إرساله ما يتكرر عند الخادم
  String _newKey() {
    final r = math.Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-'
        '${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }
}
