import 'package:flutter/widgets.dart';
import 'chicken_road_launcher_stub.dart' if (dart.library.html) 'chicken_road_launcher_web.dart' as platform;
Future<void> showChickenRoadGame(BuildContext context, {required Future<String> sessionToken}) => platform.showChickenRoadGame(context, sessionToken: sessionToken);
