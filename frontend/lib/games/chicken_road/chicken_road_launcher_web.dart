import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

Future<void> showChickenRoadGame(BuildContext context, {required Future<String> sessionToken}) async {
  final token = await sessionToken;
  if (token.isEmpty) throw StateError('empty_game_session_token');
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.of(sheetContext).size.height * 0.92,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: _ChickenRoadScreen(token: token),
      ),
    ),
  );
}

class _ChickenRoadScreen extends StatefulWidget {
  const _ChickenRoadScreen({required this.token});
  final String token;

  @override
  State<_ChickenRoadScreen> createState() => _ChickenRoadScreenState();
}

class _ChickenRoadScreenState extends State<_ChickenRoadScreen> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'happy-live-chicken-road-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int id) {
      final frame = html.IFrameElement()
        ..title = 'Chicken Road'
        ..src = '/games/chicken-road/client/index.html'
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'block';
      frame.setAttribute('allow', 'autoplay');
      frame.setAttribute('referrerpolicy', 'same-origin');
      frame.onLoad.listen((_) {
        frame.contentWindow?.postMessage(
          {'type': 'happy-live-game-session', 'sessionToken': widget.token},
          html.window.location.origin,
        );
      });
      return frame;
    });
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF09080D),
    child: Stack(
      fit: StackFit.expand,
      children: [
        HtmlElementView(viewType: _viewType),
        Positioned(
          top: 8,
          left: 8,
          child: Material(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(22),
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Color(0xFFE9C46A)),
              tooltip: 'إغلاق اللعبة',
            ),
          ),
        ),
      ],
    ),
  );
}
