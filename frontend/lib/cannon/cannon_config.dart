class CannonConfig {
  static const String apiBase = 'https://happy-live-api.taher616270.workers.dev';
  static const Duration roomPoll = Duration(seconds: 4);
  static const Duration bannerPoll = Duration(seconds: 10);

  static String _token = '';
  static String authToken() => _token;
  static void setAuthToken(String value) => _token = value.trim();

  // Optional per-level artwork URLs; the built-in painter is used when empty.
  static final Map<int, String> cannonImages = <int, String>{};
}
