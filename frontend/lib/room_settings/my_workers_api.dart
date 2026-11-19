import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class MyWorkersApi {
  MyWorkersApi({required this.roomId, required this.accessToken, http.Client? client})
      : _client = client ?? http.Client();

  static const String _base = 'https://happy-live-api.taher616270.workers.dev/api/v1';
  final String roomId;
  final String accessToken;
  final http.Client _client;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      };

  Uri get _uri => Uri.parse('$_base/rooms/${Uri.encodeComponent(roomId)}/settings');

  Future<Map<String, dynamic>> loadSettings() async {
    final response = await _client.get(_uri, headers: _headers).timeout(const Duration(seconds: 15));
    final data = _decode(response);
    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception((data['message'] ?? data['error'] ?? 'تعذر تحميل إعدادات الغرفة').toString());
    }
    return data;
  }

  @override
  Future<void> updateSetting(String key, Object? value) async {
    final response = await _client.patch(
      _uri,
      headers: _headers,
      body: jsonEncode({'key': key, 'value': value}),
    ).timeout(const Duration(seconds: 15));
    final data = _decode(response);
    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception((data['message'] ?? data['error'] ?? 'تعذر حفظ الإعداد').toString());
    }
  }

  Future<void> updatePermission(String permissionId, PermissionLevel level, List<String> adminIds) async {
    final response = await _client.patch(
      _uri,
      headers: _headers,
      body: jsonEncode({
        'permissionId': permissionId,
        'level': level.name,
        'adminIds': adminIds,
      }),
    ).timeout(const Duration(seconds: 15));
    final data = _decode(response);
    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception((data['message'] ?? data['error'] ?? 'تعذر حفظ صلاحية المشرف').toString());
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {'error': 'invalid_server_response'};
  }
}
