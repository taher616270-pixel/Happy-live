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
  CannonBanner? activeBanner;
  List<CannonContributor> contributors = [];
  String _contributorsLaunchId = '';
  bool contributorsUnavailable = false;

  Timer? _roomTimer;
  Timer? _bannerTimer;
  Timer? _bannerDisplayTimer;
  final List<CannonBanner> _bannerQueue = <CannonBanner>[];
  final Set<String> _seenBannerKeys = <String>{};
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
    contributors = [];
    _contributorsLaunchId = '';
    contributorsUnavailable = false;
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
    contributors = [];
    _contributorsLaunchId = '';
    contributorsUnavailable = false;
    isUnavailable = false;
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
      if (s.launchId.isNotEmpty && s.launchId != _contributorsLaunchId) {
        _loadContributors(id, s.launchId);
      }
      notifyListeners();
    } finally {
      _roomRequestInFlight = false;
    }
  }

  Future<void> _loadContributors(String roomId, String launchId) async {
    _contributorsLaunchId = launchId;
    contributors = [];
    contributorsUnavailable = false;
    final result = await CannonApi.fetchContributors(roomId, launchId);
    if (currentRoomId != roomId || state?.launchId != launchId) return;
    if (result == null) {
      contributorsUnavailable = true;
      _contributorsLaunchId = ''; // Retry on the next room refresh.
    } else {
      contributors = result;
    }
    notifyListeners();
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
    _bannerDisplayTimer?.cancel();
    _bannerDisplayTimer = null;
    _bannerQueue.clear();
    activeBanner = null;
    _seenBannerKeys.clear();
    notifyListeners();
  }

  Future<void> _refreshBanners() async {
    if (_bannerRequestInFlight) return;
    _bannerRequestInFlight = true;
    try {
      final result = await CannonApi.fetchBanners();
      if (result == null) return;
      banners = result;
      for (final banner in result) {
        if (!banner.launching && banner.percent < 80) continue;
        final key = '${banner.roomId}:${banner.cannonLevel}';
        if (_seenBannerKeys.add(key)) {
          _bannerQueue.add(banner);
        }
      }
      _showNextBanner();
    } finally {
      _bannerRequestInFlight = false;
    }
  }

  void _showNextBanner() {
    if (activeBanner != null || _bannerQueue.isEmpty) return;
    activeBanner = _bannerQueue.removeAt(0);
    notifyListeners();
    _bannerDisplayTimer?.cancel();
    _bannerDisplayTimer = Timer(const Duration(seconds: 3), () {
      activeBanner = null;
      notifyListeners();
      _showNextBanner();
    });
  }
}
