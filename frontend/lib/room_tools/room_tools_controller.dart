import 'package:flutter/material.dart';
import 'room_tools_api.dart';
import 'room_tools_models.dart';

typedef ToolCb = void Function(BuildContext context);
typedef RoomMicToggle = Future<bool> Function(bool open);

class RoomToolsActions {
  final ToolCb? counter, pk, salute, redEnvelope, games, lucky;
  final ToolCb? clearChat, settings, music, soundEffect, micMode, background;
  final ToolCb? visualEffect, store, activity;
  final RoomMicToggle? onMicToggle;
  final VoidCallback? onOpenGifts;

  const RoomToolsActions({
    this.counter,
    this.pk,
    this.salute,
    this.redEnvelope,
    this.games,
    this.lucky,
    this.clearChat,
    this.settings,
    this.music,
    this.soundEffect,
    this.micMode,
    this.background,
    this.visualEffect,
    this.store,
    this.activity,
    this.onMicToggle,
    this.onOpenGifts,
  });
}

class RoomToolsController extends ChangeNotifier {
  RoomToolsController({
    required this.roomId,
    required this.role,
    this.actions = const RoomToolsActions(),
    this.micOpen = true,
  }) {
    _load();
  }

  final String roomId;
  final RoomRole role;
  final RoomToolsActions actions;

  bool locked = false;
  bool micOpen;
  bool loadingLock = true;
  bool lockReady = false;
  bool lockBusy = false;
  bool micBusy = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _load() async {
    final state = await RoomToolsApi.fetchLocked(roomId);
    if (_disposed) return;
    if (state != null) {
      locked = state;
      lockReady = true;
    }
    loadingLock = false;
    notifyListeners();
  }

  Future<void> refreshLock() async {
    if (loadingLock || lockBusy) return;
    loadingLock = true;
    notifyListeners();
    final state = await RoomToolsApi.fetchLocked(roomId);
    if (_disposed) return;
    if (state != null) {
      locked = state;
      lockReady = true;
    }
    loadingLock = false;
    notifyListeners();
  }

  Future<bool> toggleLock() async {
    if (lockBusy || !lockReady || !role.canManage) return false;
    lockBusy = true;
    notifyListeners();
    final next = !locked;
    var ok = false;
    try {
      ok = await RoomToolsApi.setLocked(roomId, next);
    } catch (_) {
      ok = false;
    }
    if (_disposed) return false;
    if (ok) locked = next;
    lockBusy = false;
    notifyListeners();
    return ok;
  }

  Future<bool> toggleMic() async {
    if (micBusy) return false;
    micBusy = true;
    notifyListeners();
    final next = !micOpen;
    var ok = true;
    try {
      final callback = actions.onMicToggle;
      if (callback != null) ok = await callback(next);
    } catch (_) {
      ok = false;
    }
    if (_disposed) return false;
    if (ok) micOpen = next;
    micBusy = false;
    notifyListeners();
    return ok;
  }
}
