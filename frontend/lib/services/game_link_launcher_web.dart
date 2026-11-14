import 'dart:html' as html;

Future<void> launchExternalGame(String url) async {
  html.window.open(url, '_blank', 'noopener,noreferrer');
}
