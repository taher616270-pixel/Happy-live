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
  String _observedLaunchId = '';
  int contributorsLevel = 0;
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
    _observedLaunchId = '';
    contributorsLevel = 0;
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
    _observedLaunchId = '';
    contributorsLevel = 0;
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

      // A new Saudi day creates a fresh cannon state with an empty launch ID.
      // Clear the previous launch's contributors so the prize pool is visible
      // again for the new day in every room.
      if (s.launchId != _observedLaunchId) {
        _observedLaunchId = s.launchId;
        if (s.launchId.isEmpty) {
          contributors = [];
          _contributorsLaunchId = '';
          contributorsLevel = 0;
          contributorsUnavailable = false;
        } else {
          _loadContributors(id, s.launchId, s.level - 1);
        }
      }
      notifyListeners();
    } finally {
      _roomRequestInFlight = false;
    }
  }

  Future<void> _loadContributors(String roomId, String launchId, int level) async {
    _contributorsLaunchId = launchId;
    contributorsLevel = level;
    contributors = [];
    contributorsUnavailable = false;
    final result = await CannonApi.fetchContributors(roomId, launchId: launchId, level: level);
    if (currentRoomId != roomId || contributorsLevel != level) return;
    if (result == null) {
      contributorsUnavailable = true;
      _contributorsLaunchId = ''; // Retry on the next room refresh.
    } else {
      contributors = result;
    }
    notifyListeners();
  }

  Future<void> loadContributorsForLevel(int level) async {
    final id = currentRoomId;
    if (id == null || level < 1 || contributorsLevel == level) return;
    await _loadContributors(id, '', level);
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
