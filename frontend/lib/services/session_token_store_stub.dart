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

const String _sessionUserKey = 'happy_live_session_user';
const String _sessionTabKey = 'happy_live_selected_tab';

Future<String?> readSessionUser() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_sessionUserKey);
}
Future<void> writeSessionUser(String value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_sessionUserKey, value);
}
Future<int> readSessionTab() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(_sessionTabKey) ?? 0;
}
Future<void> writeSessionTab(int index) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_sessionTabKey, index);
}
