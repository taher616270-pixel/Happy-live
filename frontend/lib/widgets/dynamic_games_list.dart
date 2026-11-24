import 'dart:convert';
import '../widgets/centered_notification.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/game_link_launcher.dart';
import '../services/session_token_store.dart';

class DynamicGamesList extends StatefulWidget {
  const DynamicGamesList({super.key, this.onGameClosed});

  final Future<void> Function()? onGameClosed;

  @override
  State<DynamicGamesList> createState() => _DynamicGamesListState();
}

class _DynamicGamesListState extends State<DynamicGamesList> {
  static const String _apiBase = const String.fromEnvironment('HAPPY_LIVE_API_BASE', defaultValue: 'https://happy-live-api.taher616270.workers.dev/api/v1');

  Future<String> _createGameSession(String gameId) async {
    final appToken = await SessionTokenStore.read();
    if (appToken == null || appToken.isEmpty) {
      throw Exception('authentication_required');
    }
    final response = await http.post(
      Uri.parse('$_apiBase/game/auth'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $appToken',
      },
      body: jsonEncode({'gameId': gameId}),
    ).timeout(const Duration(seconds: 12));
    Map<String, dynamic> data = {};
    try { data = jsonDecode(response.body) as Map<String, dynamic>; } catch (_) {}
    if (response.statusCode != 201 || data['ok'] != true || data['sessionToken'] is! String) {
      throw Exception((data['error'] ?? 'game_session_failed').toString());
    }
    return data['sessionToken'] as String;
  }
  late Future<List<Map<String, dynamic>>> _games;

  @override
  void initState() {
    super.initState();
    _games = _loadGames();
  }

  Future<List<Map<String, dynamic>>> _loadGames() async {
    final response = await http.get(
      Uri.parse('$_apiBase/games/catalog'),
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('تعذر تحميل الألعاب');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = decoded['games'];
    if (rows is! List) return [];
    return rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _games,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'تعذر تحميل الألعاب المضافة حاليًا.',
                    style: TextStyle(color: Color(0xFF8B899A), fontSize: 11),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _games = _loadGames()),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          children: snapshot.data!.map((game) {
            final name = (game['name'] ?? 'لعبة').toString();
            final description = (game['description'] ?? 'اضغط لفتح اللعبة').toString();
            final url = (game['url'] ?? '').toString();
            final gameId = (game['id'] ?? '').toString();
            final iconUrl = (game['iconUrl'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: url.isEmpty ? null : () async {
                    try {
                      await launchExternalGame(context, url, _createGameSession(gameId));
                      await widget.onGameClosed?.call();
                    } catch (_) {
                      if (context.mounted) {
                        showCenteredNotification(context, 
                          const SnackBar(content: Text('تعذر فتح اللعبة داخل التطبيق.')),
                        );
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF6E5D47), Color(0xFF503C28), Color(0xFF141414)],
                        stops: [0.0, 0.48, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE9C46A).withValues(alpha: 0.55)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 49,
                          height: 49,
                          decoration: BoxDecoration(
                            color: const Color(0xFF281414),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: iconUrl.startsWith('https://')
                              ? Image.network(iconUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.sports_esports, color: Color(0xFFD1A13A)))
                              : const Icon(Icons.sports_esports, color: Color(0xFFD1A13A)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(color: Color(0xFF1E2233), fontWeight: FontWeight.w900, fontSize: 14)),
                              const SizedBox(height: 5),
                              Text(description, maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFF8B899A), fontSize: 11, height: 1.4)),
                            ],
                          ),
                        ),
                        const Icon(Icons.open_in_new_rounded, color: Color(0xFFC5A45D), size: 21),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
