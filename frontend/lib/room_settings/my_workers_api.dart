import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'room_settings_api.dart';

class MyWorkersApi implements RoomSettingsApi {
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
  Uri get _moderationUri => Uri.parse('$_base/rooms/${Uri.encodeComponent(roomId)}/moderation');

  @override
  Future<Map<String, dynamic>> loadSettings() async {
    final response = await _client.get(_uri, headers: _headers).timeout(const Duration(seconds: 15));
    final data = _decode(response);
    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception((data['message'] ?? data['error'] ?? 'تعذر تحميل إعدادات الغرفة').toString());
    }
    return data;
  }

  @override
  Future<void> updateSetting(String key, Object value) async {
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

  @override
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

  @override
  Future<Map<String, dynamic>> loadModeration() async {
    final response = await _client.get(_moderationUri, headers: _headers).timeout(const Duration(seconds: 15));
    final data = _decode(response);
    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception((data['message'] ?? data['error'] ?? 'تعذر تحميل قوائم الغرفة').toString());
    }
    return data;
  }

  @override
  Future<void> moderationAction(String action, String targetUserId) async {
    final response = await _client.post(
      _moderationUri,
      headers: _headers,
      body: jsonEncode({'action': action, 'targetUserId': targetUserId}),
    ).timeout(const Duration(seconds: 15));
    final data = _decode(response);
    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception((data['message'] ?? data['error'] ?? 'تعذر تنفيذ الإجراء').toString());
    }
  }

  @override
  Future<String> uploadCover(Uint8List bytes, String fileName) async {
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw Exception('حجم الصورة يجب ألا يتجاوز 5 ميجابايت');
    }
    final authResponse = await _client.get(
      Uri.parse('$_base/imagekit/auth'),
      headers: {'Authorization': 'Bearer $accessToken'},
    ).timeout(const Duration(seconds: 15));
    final auth = _decode(authResponse);
    if (authResponse.statusCode != 200 ||
        auth['token'] == null || auth['signature'] == null ||
        auth['expire'] == null || auth['publicKey'] == null) {
      throw Exception((auth['message'] ?? auth['error'] ?? 'تعذر تجهيز رفع الصورة').toString());
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://upload.imagekit.io/api/v1/files/upload'),
    );
    request.fields.addAll({
      'fileName': 'room-cover-${DateTime.now().millisecondsSinceEpoch}-$fileName',
      'publicKey': auth['publicKey'].toString(),
      'token': auth['token'].toString(),
      'expire': auth['expire'].toString(),
      'signature': auth['signature'].toString(),
      'useUniqueFileName': 'true',
      'folder': '/happy-live/rooms',
    });
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    final data = _decode(response);
    final url = data['url']?.toString() ?? '';
    if (response.statusCode < 200 || response.statusCode >= 300 || !url.startsWith('https://')) {
      throw Exception((data['message'] ?? data['error'] ?? 'فشل رفع صورة الغرفة').toString());
    }
    await updateSetting('coverUrl', url);
    return url;
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {'error': 'invalid_server_response'};
  }
}
