import 'package:shared_preferences/shared_preferences.dart';

const String _sessionTokenKey = 'happy_live_session_token';

Future<String?> readSessionToken() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_sessionTokenKey);
}

Future<void> writeSessionToken(String token) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_sessionTokenKey, token);
}

Future<void> clearSessionToken() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_sessionTokenKey);
}
