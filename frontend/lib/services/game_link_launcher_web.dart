import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

Future<void> launchExternalGame(BuildContext context, String url, Future<String> sessionToken) async {
  final parsed = Uri.tryParse(url);
  if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty || parsed.userInfo.isNotEmpty) {
    throw ArgumentError('invalid_game_url');
  }
  final token = await sessionToken;
  if (token.isEmpty) throw StateError('empty_game_session_token');
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => _EmbeddedGamePage(
        url: parsed.toString(),
        origin: parsed.origin,
        sessionToken: token,
      ),
    ),
  );
}

class _EmbeddedGamePage extends StatefulWidget {
  const _EmbeddedGamePage({
    required this.url,
    required this.origin,
    required this.sessionToken,
  });

  final String url;
  final String origin;
  final String sessionToken;

  @override
  State<_EmbeddedGamePage> createState() => _EmbeddedGamePageState();
}

class _EmbeddedGamePageState extends State<_EmbeddedGamePage> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'happy-live-game-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final frame = html.IFrameElement()
        ..title = 'Happy Live game'
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'block';
      frame.setAttribute('allow', 'autoplay; fullscreen');
      frame.setAttribute('referrerpolicy', 'no-referrer');
      frame.onLoad.listen((_) async {
        // The short-lived token is delivered only to this exact registered origin.
        // It is never added to the URL, fragment, referrer, or browser history.
        for (var attempt = 0; attempt < 40; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          frame.contentWindow?.postMessage({
            'type': 'happy-live-game-session',
            'sessionToken': widget.sessionToken,
          }, widget.origin);
        }
      });
      frame.src = widget.url;
      return frame;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('اللعبة'),
        leading: IconButton(
          tooltip: 'إغلاق اللعبة',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SizedBox.expand(
        child: HtmlElementView(viewType: _viewType),
      ),
    );
  }
}
