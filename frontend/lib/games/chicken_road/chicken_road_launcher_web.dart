import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

Future<void> showChickenRoadGame(BuildContext context, {required Future<String> sessionToken}) async {
  final token = await sessionToken;
  if (token.isEmpty) throw StateError('empty_game_session_token');
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => _ChickenRoadScreen(token: token)));
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
        ..title = 'عبور الدجاجة'
        ..src = '/games/chicken-road/client/index.html'
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'block';
      frame.setAttribute('allow', 'autoplay');
      frame.setAttribute('referrerpolicy', 'same-origin');
      frame.onLoad.listen((_) {
        frame.contentWindow?.postMessage({'type':'happy-live-game-session','sessionToken':widget.token}, html.window.location.origin);
      });
      return frame;
    });
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF09080D),
    body: SafeArea(child: Stack(children:[
      const Positioned.fill(child: ColoredBox(color: Color(0xFF09080D))),
      Positioned.fill(child: HtmlElementView(viewType:_viewType)),
      Positioned(top:8,left:8,child:Material(color:Colors.black54,borderRadius:BorderRadius.circular(22),child:IconButton(onPressed:()=>Navigator.of(context).pop(),icon:const Icon(Icons.close,color:Color(0xFFE9C46A)),tooltip:'إغلاق اللعبة'))),
    ])),
  );
}
