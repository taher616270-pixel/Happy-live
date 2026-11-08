import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';

class AgoraRoomBridge {
  static RtcEngine? _engine;
  static String? _activeAppId;
  static bool _joined = false;
  static bool _muted = false;

  static Future<void> join({
    required String appId,
    required String channel,
    required String token,
    required int uid,
    required bool publish,
  }) async {
    if (appId.isEmpty || channel.isEmpty || token.isEmpty || uid <= 0) {
      throw ArgumentError('Agora connection details are incomplete.');
    }

    if (publish) {
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) {
        throw StateError('Microphone permission was not granted.');
      }
    }

    await leave();

    final engine = createAgoraRtcEngine();
    _engine = engine;
    _activeAppId = appId;

    try {
      await engine.initialize(RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      ));
      await engine.enableAudio();
      await engine.setClientRole(
        role: publish
            ? ClientRoleType.clientRoleBroadcaster
            : ClientRoleType.clientRoleAudience,
      );
      await engine.joinChannel(
        token: token,
        channelId: channel,
        uid: uid,
        options: ChannelMediaOptions(
          autoSubscribeAudio: true,
          publishMicrophoneTrack: publish,
          clientRoleType: publish
              ? ClientRoleType.clientRoleBroadcaster
              : ClientRoleType.clientRoleAudience,
        ),
      );
      _joined = true;
      _muted = false;
    } catch (_) {
      try {
        await engine.release();
      } catch (_) {}
      _engine = null;
      _activeAppId = null;
      _joined = false;
      rethrow;
    }
  }

  static Future<void> leave() async {
    final engine = _engine;
    _engine = null;
    _activeAppId = null;
    _joined = false;
    _muted = false;
    if (engine == null) return;
    try {
      await engine.leaveChannel();
    } catch (_) {}
    try {
      await engine.release();
    } catch (_) {}
  }

  static Future<void> setMuted(bool muted) async {
    final engine = _engine;
    if (engine == null || !_joined) return;
    await engine.muteLocalAudioStream(muted);
    _muted = muted;
  }

  static Future<void> resumeAudio() async {
    final engine = _engine;
    if (engine == null || !_joined) return;
    await engine.enableAudio();
    await engine.adjustPlaybackSignalVolume(100);
    if (_muted) {
      await engine.muteLocalAudioStream(true);
    }
  }
}
