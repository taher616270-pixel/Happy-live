import 'session_token_store_stub.dart'
    if (dart.library.html) 'session_token_store_web.dart' as platform;

/// Keeps the authenticated session available after a browser refresh.
class SessionTokenStore {
  static Future<String?> read() => platform.readSessionToken();
  static Future<void> write(String token) => platform.writeSessionToken(token);
  static Future<void> clear() => platform.clearSessionToken();
}
