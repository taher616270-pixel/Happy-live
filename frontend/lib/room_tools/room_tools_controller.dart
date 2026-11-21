import 'package:flutter/material.dart';
import 'room_tools_api.dart';
import 'room_tools_models.dart';

typedef ToolCb = void Function(BuildContext context);

class RoomToolsActions {
  final ToolCb? counter, pk, salute, redEnvelope, games, lucky;
  final ToolCb? clearChat, settings, music, soundEffect, micMode, background;
  final ToolCb? visualEffect, store, activity;
  final void Function(bool open)? onMicToggle;
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
  bool _busy = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _load() async {
    final state = await RoomToolsApi.fetchLocked(roomId);
    if (_disposed) return;
    if (state != null) locked = state;
    loadingLock = false;
    notifyListeners();
  }

  Future<bool> toggleLock() async {
    if (_busy || !role.canManage) return false;
    _busy = true;
    notifyListeners();
    final next = !locked;
    final ok = await RoomToolsApi.setLocked(roomId, next);
    if (_disposed) return false;
    if (ok) locked = next;
    _busy = false;
    notifyListeners();
    return ok;
  }

  void toggleMic() {
    micOpen = !micOpen;
    actions.onMicToggle?.call(micOpen);
    notifyListeners();
  }
}
