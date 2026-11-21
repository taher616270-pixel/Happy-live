import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'contrib_models.dart';
import 'contrib_sheet.dart';

class ContribConfig {
  /// رابط Worker الإنتاجي.
  static const String apiBase = 'https://happy-live-api.taher616270.workers.dev';

  /// يضبط مرة واحدة عند فتح نافذة التصنيف من الغرفة.
  static String Function() userId = () => '';
  static String Function() authToken = () => '';
}

class ContribApi {
  static String _name(ContribPeriod period) {
    switch (period) {
      case ContribPeriod.daily:
        return 'daily';
      case ContribPeriod.weekly:
        return 'weekly';
      case ContribPeriod.monthly:
        return 'monthly';
    }
  }

  static int _i(dynamic value) =>
      value is num ? value.toInt() : (int.tryParse('$value') ?? 0);

  static ContribEntry _entry(Map<String, dynamic> entry) => ContribEntry(
        name: (entry['name'] ?? '').toString(),
        avatarUrl: (entry['avatar'] ?? '').toString(),
        amount: _i(entry['amount']),
      );

  static Future<ContribData> fetch(String roomId, ContribPeriod period) async {
    final token = ContribConfig.authToken();
    final parameters = <String, String>{
      'room_id': roomId,
      'period': _name(period),
    };
    final userId = ContribConfig.userId().trim();
    if (userId.isNotEmpty) parameters['user_id'] = userId;

    final uri = Uri.parse('${ContribConfig.apiBase}/api/room/contributors')
        .replace(queryParameters: parameters);
    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception('http ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
      throw Exception('bad response');
    }

    final entries = ((decoded['entries'] as List?) ?? const [])
        .whereType<Map>()
        .map((entry) => _entry(Map<String, dynamic>.from(entry)))
        .toList();

    ContribEntry? me;
    int? rank;
    if (decoded['me'] is Map) {
      final mine = Map<String, dynamic>.from(decoded['me'] as Map);
      me = _entry(mine);
      rank = mine['rank'] == null ? null : _i(mine['rank']);
    }
    return ContribData(entries: entries, me: me, myRank: rank);
  }
}

Future<void> openContribSheet(
  BuildContext context,
  String roomId, {
  required String accessToken,
}) {
  ContribConfig.authToken = () => accessToken;
  return showContribSheet(
    context,
    loader: (period) => ContribApi.fetch(roomId, period),
  );
}
