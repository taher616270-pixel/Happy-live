import 'dart:async';
import 'package:flutter/foundation.dart';
import 'cannon_api.dart';
import 'cannon_config.dart';
import 'cannon_models.dart';

class CannonService extends ChangeNotifier {
  CannonService._();
  static final CannonService instance = CannonService._();

  String? currentRoomId;
  CannonState? state;
  List<CannonBanner> banners = [];

  Timer? _roomTimer;
  Timer? _bannerTimer;
  String _lastLaunchId = '';
  bool _firstLoad = true;
  bool _roomRequestInFlight = false;
  bool _bannerRequestInFlight = false;
  bool isUnavailable = false;

  final StreamController<CannonState> _launchCtrl = StreamController<CannonState>.broadcast();
  Stream<CannonState> get onLaunch => _launchCtrl.stream;

  void enterRoom(String roomId, String accessToken) {
    CannonConfig.setAuthToken(accessToken);
    if (currentRoomId == roomId && _roomTimer != null) return;
    _roomTimer?.cancel();
    currentRoomId = roomId;
    state = null;
    isUnavailable = false;
    _lastLaunchId = '';
    _firstLoad = true;
    refreshNow();
    _roomTimer = Timer.periodic(CannonConfig.roomPoll, (_) => refreshNow());
  }

  void leaveRoom() {
    _roomTimer?.cancel();
    _roomTimer = null;
    currentRoomId = null;
    state = null;
    _lastLaunchId = '';
    _firstLoad = true;
    Future.microtask(notifyListeners);
  }

  Future<void> refreshNow() async {
    final id = currentRoomId;
    if (id == null || _roomRequestInFlight) return;
    _roomRequestInFlight = true;
    try {
      final s = await CannonApi.fetchState(id);
      if (currentRoomId != id) return;
      if (s == null) {
        isUnavailable = true;
        notifyListeners();
        return;
      }
      isUnavailable = false;
      if (!_firstLoad && s.launching && s.launchId.isNotEmpty && s.launchId != _lastLaunchId) {
        _launchCtrl.add(s);
      }
      _lastLaunchId = s.launchId;
      _firstLoad = false;
      state = s;
      notifyListeners();
    } finally {
      _roomRequestInFlight = false;
    }
  }

  Future<bool> claim(CannonClaim c) async {
    if (currentRoomId == null) return false;
    final ok = await CannonApi.claim(c.id);
    await refreshNow();
    return ok;
  }

  void startBanners(String accessToken) {
    CannonConfig.setAuthToken(accessToken);
    if (_bannerTimer != null) return;
    _refreshBanners();
    _bannerTimer = Timer.periodic(CannonConfig.bannerPoll, (_) => _refreshBanners());
  }

  void stopBanners() {
    _bannerTimer?.cancel();
    _bannerTimer = null;
  }

  Future<void> _refreshBanners() async {
    if (_bannerRequestInFlight) return;
    _bannerRequestInFlight = true;
    try {
      final b = await CannonApi.fetchBanners();
      if (b == null) return;
      banners = b;
      notifyListeners();
    } finally {
      _bannerRequestInFlight = false;
    }
  }
}
