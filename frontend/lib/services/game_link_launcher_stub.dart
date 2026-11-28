import 'package:flutter/widgets.dart';

Future<void> launchExternalGame(BuildContext context, String url, Future<String> sessionToken) async {
  throw UnsupportedError('External game embedding is currently supported on Web.');
}

Future<void> launchFixedGame(BuildContext context, String url, Future<String> sessionToken) async {
  throw UnsupportedError('Fixed-size game iframe is currently supported on Web.');
}
