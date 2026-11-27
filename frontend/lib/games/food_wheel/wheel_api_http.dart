import 'dart:convert';

import 'package:http/http.dart' as http;

import 'food_wheel_game.dart';

/// Read-only connection for the first integration stage.
/// No wallet mutation endpoint is called from this client.
class WheelApiConfig {
  static const gameId = 'ed1490b4-c868-46bc-be7e-1448d5bdf498';
  static const base = 'https://happy-live-api.taher616270.workers.dev/api/v1';
}

class HttpFoodWheelApi implements FoodWheelApi {
  HttpFoodWheelApi({required this.accessToken, http.Client? client})
      : _client = client ?? http.Client();

  final String accessToken;
  final http.Client _client;

  Uri _uri(String path) => Uri.parse('${WheelApiConfig.base}$path');

  Future<dynamic> _get(String path) async {
    if (accessToken.isEmpty) {
      throw const WheelApiException('session_missing');
    }
    http.Response response;
    try {
      response = await _client.get(
        _uri(path),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(const Duration(seconds: 10));
    } on Exception {
      throw const WheelApiException('network');
    }

    dynamic data;
    try {
      data = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    } catch (_) {
      throw const WheelApiException('bad_response');
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    final code = data is Map
        ? (data['error'] ?? data['code'] ?? '').toString()
        : '';
    if (response.statusCode == 404 ||
        response.statusCode == 405 ||
        response.statusCode == 501) {
      throw WheelApiException('backend_not_implemented', status: response.statusCode);
    }
    if (response.statusCode == 401) {
      throw WheelApiException('session_expired', status: response.statusCode);
    }
    if (response.statusCode == 403) {
      throw WheelApiException('forbidden', status: response.statusCode);
    }
    throw WheelApiException(
      code.isEmpty ? 'server_error' : code,
      status: response.statusCode,
    );
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const WheelApiException('bad_response');
  }

  List<dynamic> _list(dynamic value, List<String> keys) {
    if (value is List) return value;
    if (value is Map) {
      for (final key in keys) {
        if (value[key] is List) return value[key] as List;
      }
    }
    throw const WheelApiException('bad_response');
  }

  @override
  Future<RoundState> fetchState() async {
    final data = _map(await _get('/game/food-wheel/state'));
    try {
      return RoundState.fromJson(data);
    } catch (_) {
      throw const WheelApiException('bad_response');
    }
  }

  /// Stage 1 is strictly read-only. Never send a bet or wallet mutation request.
  @override
  Future<RoundState> placeBet(int roundId, int slot, int amount) async {
    throw const WheelApiException('settlement_disabled');
  }

  @override
  Future<List<WinRecord>> fetchTopWins() async {
    final rows = _list(await _get('/game/food-wheel/top-wins'), ['wins', 'items']);
    try {
      return rows
          .map((row) => WinRecord.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (_) {
      throw const WheelApiException('bad_response');
    }
  }

  @override
  Future<List<MyRoundRecord>> fetchMyHistory() async {
    final rows = _list(
      await _get('/game/food-wheel/history?limit=20'),
      ['rounds', 'items', 'history'],
    );
    try {
      return rows
          .map((row) => MyRoundRecord.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (_) {
      throw const WheelApiException('bad_response');
    }
  }
}
