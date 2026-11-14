import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
      builder: (_) => _EmbeddedMobileGamePage(
        url: parsed.toString(),
        origin: parsed.origin,
        sessionToken: token,
      ),
    ),
  );
}

class _EmbeddedMobileGamePage extends StatefulWidget {
  const _EmbeddedMobileGamePage({
    required this.url,
    required this.origin,
    required this.sessionToken,
  });

  final String url;
  final String origin;
  final String sessionToken;

  @override
  State<_EmbeddedMobileGamePage> createState() => _EmbeddedMobileGamePageState();
}

class _EmbeddedMobileGamePageState extends State<_EmbeddedMobileGamePage> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) async {
            if (mounted) setState(() => _isLoading = false);
            final js = '''
window.postMessage({
  type: "happy-live-game-session",
  sessionToken: ''' + jsonEncode(widget.sessionToken) + ''',
}, ''' + jsonEncode(widget.origin) + ''');
''';
            for (var attempt = 0; attempt < 20; attempt++) {
              await Future<void>.delayed(const Duration(milliseconds: 300));
              if (!mounted) break;
              try {
                await _controller.runJavaScript(js);
              } catch (_) {}
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text("اللعبة"),
        leading: IconButton(
          tooltip: "إغلاق اللعبة",
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
        ],
      ),
    );
  }
}
