import 'dart:async';
import 'dart:html' as html;

Future<void> launchExternalGame(String url, Future<String> sessionToken) async {
  final parsed = Uri.tryParse(url);
  if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty || parsed.userInfo.isNotEmpty) {
    throw ArgumentError('invalid_game_url');
  }

  // Open synchronously during the user's tap so browser popup protection
  // does not block the game while the server issues its short-lived token.
  final target = html.window.open('about:blank', '_blank');
  try {
    final token = await sessionToken;
    if (token.isEmpty) throw StateError('empty_game_session_token');
    target.location.href = url;

    // The game page receives the token only through postMessage, never in
    // its URL, query string, fragment, browser history, or HTTP referrer.
    // Retry briefly because the cross-origin game may still be loading.
    for (var attempt = 0; attempt < 20; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      target.postMessage({
        'type': 'happy-live-game-session',
        'sessionToken': token,
      }, parsed.origin);
    }
  } catch (_) {
    target.close();
    rethrow;
  }
}
