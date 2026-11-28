import 'package:flutter/widgets.dart';
import 'game_link_launcher_stub.dart'
    if (dart.library.html) 'game_link_launcher_web.dart' as platform;

Future<void> launchExternalGame(BuildContext context, String url, Future<String> sessionToken) =>\n    platform.launchExternalGame(context, url, sessionToken);\n\nFuture<void> launchFixedGame(BuildContext context, String url, Future<String> sessionToken) =>\n    platform.launchFixedGame(context, url, sessionToken);
