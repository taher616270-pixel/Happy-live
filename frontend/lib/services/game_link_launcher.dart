import 'package:flutter/widgets.dart';
import 'game_link_launcher_stub.dart'
    if (dart.library.html) 'game_link_launcher_web.dart'
    if (dart.library.io) 'game_link_launcher_mobile.dart' as platform;

Future<void> launchExternalGame(BuildContext context, String url, Future<String> sessionToken) =>
    platform.launchExternalGame(context, url, sessionToken);
