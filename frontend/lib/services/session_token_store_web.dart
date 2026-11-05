import 'dart:html' as html;

import 'package:shared_preferences/shared_preferences.dart';

const String _sessionTokenKey = 'happy_live_session_token';

/// Browser localStorage survives page reloads and Flutter app reinitialization.
Future<String?> readSessionToken() async {
  final browserToken = html.window.localStorage[_sessionTokenKey];
  if (browserToken != null && browserToken.isNotEmpty) return browserToken;

  // Migrate sessions saved by the previous SharedPreferences-only version.
  final prefs = await SharedPreferences.getInstance();
  final legacyToken = prefs.getString(_sessionTokenKey);
  if (legacyToken != null && legacyToken.isNotEmpty) {
    html.window.localStorage[_sessionTokenKey] = legacyToken;
    return legacyToken;
  }
  return null;
}

Future<void> writeSessionToken(String token) async {
  html.window.localStorage[_sessionTokenKey] = token;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_sessionTokenKey, token);
}

Future<void> clearSessionToken() async {
  html.window.localStorage.remove(_sessionTokenKey);
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_sessionTokenKey);
}

const String _sessionUserKey = 'happy_live_session_user';
const String _sessionTabKey = 'happy_live_selected_tab';

Future<String?> readSessionUser() async =>
    html.window.localStorage[_sessionUserKey];
Future<void> writeSessionUser(String value) async {
  html.window.localStorage[_sessionUserKey] = value;
}
Future<int> readSessionTab() async {
  final value = html.window.localStorage[_sessionTabKey];
  return int.tryParse(value ?? '') ?? 0;
}
Future<void> writeSessionTab(int index) async {
  html.window.localStorage[_sessionTabKey] = index.toString();
}
