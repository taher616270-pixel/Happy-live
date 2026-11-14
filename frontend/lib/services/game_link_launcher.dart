import 'game_link_launcher_stub.dart'
    if (dart.library.html) 'game_link_launcher_web.dart' as platform;

Future<void> launchExternalGame(String url) => platform.launchExternalGame(url);
