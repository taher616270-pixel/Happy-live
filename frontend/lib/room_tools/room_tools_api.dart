import 'dart:convert';
import 'package:http/http.dart' as http;
import 'room_tools_models.dart';

class RoomToolsConfig {
  static const String apiBase = 'https://happy-live-api.taher616270.workers.dev';
  static const String shareBase = 'https://happy-live.pages.dev';
  static String Function() userId = () => '';
  static String Function() authToken = () => '';
}

class RoomToolsApi {
  static Map<String, String> get _headers {
    final token = RoomToolsConfig.authToken();
    return {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<bool?> fetchLocked(String roomId) async {
    try {
      final uri = Uri.parse('${RoomToolsConfig.apiBase}/api/room/tools-state')
          .replace(queryParameters: {'room_id': roomId});
      final response = await http.get(uri, headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final payload = jsonDecode(utf8.decode(response.bodyBytes));
      if (payload is! Map || payload['ok'] != true) return null;
      return payload['locked'] == true;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> setLocked(String roomId, bool locked) async {
    try {
      final uri = Uri.parse('${RoomToolsConfig.apiBase}/api/room/lock');
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({'room_id': roomId, 'locked': locked}),
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return false;
      final payload = jsonDecode(utf8.decode(response.bodyBytes));
      return payload is Map && payload['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<KickEntry>> fetchKicks(String roomId) async {
    final uri = Uri.parse('${RoomToolsConfig.apiBase}/api/room/kicks')
        .replace(queryParameters: {'room_id': roomId});
    final response = await http.get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('تعذر تحميل سجل الطرد (${response.statusCode})');
    }
    final payload = jsonDecode(utf8.decode(response.bodyBytes));
    if (payload is! Map || payload['ok'] != true) {
      throw Exception('تعذر تحميل سجل الطرد');
    }
    final rows = payload['kicks'];
    if (rows is! List) return <KickEntry>[];
    return rows.whereType<Map>().map((row) {
      final item = Map<String, dynamic>.from(row);
      final rawTime = item['time'];
      final parsedTime = rawTime is num
          ? DateTime.fromMillisecondsSinceEpoch(rawTime.toInt() * 1000)
          : DateTime.tryParse((rawTime ?? '').toString()) ?? DateTime.now();
      return KickEntry(
        name: (item['name'] ?? 'مستخدم').toString(),
        avatar: (item['avatar'] ?? '').toString(),
        by: (item['by'] ?? 'مشرف').toString(),
        reason: (item['reason'] ?? '').toString(),
        time: parsedTime,
      );
    }).toList();
  }
}
