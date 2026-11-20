import 'dart:convert';
import 'package:http/http.dart' as http;
import 'cannon_config.dart';
import 'cannon_models.dart';

class CannonApi {
  static Map<String, String> get _headers {
    final token = CannonConfig.authToken();
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<CannonState?> fetchState(String roomId) async {
    try {
      final uri = Uri.parse('${CannonConfig.apiBase}/api/cannon/state')
        .replace(queryParameters: {'room_id': roomId});
      final r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (j['ok'] != true || j['disabled'] == true) return null;
      return CannonState.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  static Future<List<CannonBanner>?> fetchBanners() async {
    try {
      final uri = Uri.parse('${CannonConfig.apiBase}/api/cannon/banners');
      final r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (j['ok'] != true) return null;
      CannonConfig.bannerImageUrl = (j['bannerImageUrl'] ?? '').toString();
      CannonConfig.frameImageUrl = (j['frameImageUrl'] ?? '').toString();
      return ((j['banners'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => CannonBanner.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<List<CannonContributor>?> fetchContributors(String roomId, {String launchId = '', int? level}) async {
    try {
      final uri = Uri.parse('${CannonConfig.apiBase}/api/cannon/contributors')
        .replace(queryParameters: {
          'room_id': roomId,
          if (launchId.isNotEmpty) 'launch_id': launchId,
          if (level != null) 'level': '$level',
        });
      final r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (j['ok'] != true) return null;
      return ((j['contributors'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => CannonContributor.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<List<CannonWinner>?> fetchWinners(String roomId, int level) async {
    try {
      final uri = Uri.parse('${CannonConfig.apiBase}/api/cannon/winners')
        .replace(queryParameters: {'room_id': roomId, 'level': '$level'});
      final r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (j['ok'] != true) return null;
      return ((j['winners'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => CannonWinner.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> claim(String claimId) async {
    try {
      final uri = Uri.parse('${CannonConfig.apiBase}/api/cannon/claim');
      final r = await http.post(uri, headers: _headers, body: jsonEncode({'claim_id': claimId}))
        .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return false;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j is Map && j['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}
