import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';

class AgoraRoomBridge {
  static RtcEngine? _engine;
  static String? _activeAppId;
  static bool _joined = false;
  static bool _muted = false;
  static final Map<int, double> _volumeLevels = <int, double>{};
  static final Map<int, DateTime> _volumeSeenAt = <int, DateTime>{};

  static Future<void> join({required String appId, required String channel, required String token, required int uid, required bool publish}) async {
    if (appId.isEmpty || channel.isEmpty || token.isEmpty || uid <= 0) throw ArgumentError('Agora connection details are incomplete.');
    if (publish) {
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) throw StateError('Microphone permission was not granted.');
    }
    await leave();
    final engine = createAgoraRtcEngine();
    _engine = engine;
    _activeAppId = appId;
    try {
      await engine.initialize(RtcEngineContext(appId: appId, channelProfile: ChannelProfileType.channelProfileLiveBroadcasting));
      engine.registerEventHandler(RtcEngineEventHandler(
        onAudioVolumeIndication: (connection, speakers, speakerNumber, totalVolume) {
          final now = DateTime.now();
          for (final speaker in speakers) {
            if (speaker.uid <= 0) continue;
            final level = (speaker.volume / 255.0).clamp(0.0, 1.0).toDouble();
            if (level >= 0.035) {
              _volumeLevels[speaker.uid] = level;
              _volumeSeenAt[speaker.uid] = now;
            } else {
              _volumeLevels.remove(speaker.uid);
              _volumeSeenAt.remove(speaker.uid);
            }
          }
        },
      ));
      await engine.enableAudio();
      await engine.enableAudioVolumeIndication(interval: 180, smooth: 3, reportVad: true);
      await engine.setClientRole(role: publish ? ClientRoleType.clientRoleBroadcaster : ClientRoleType.clientRoleAudience);
      await engine.joinChannel(
        token: token, channelId: channel, uid: uid,
        options: ChannelMediaOptions(
          autoSubscribeAudio: true,
          publishMicrophoneTrack: publish,
          clientRoleType: publish ? ClientRoleType.clientRoleBroadcaster : ClientRoleType.clientRoleAudience,
        ),
      );
      _joined = true;
      _muted = false;
    } catch (_) {
      try { await engine.release(); } catch (_) {}
      _engine = null; _activeAppId = null; _joined = false; _volumeLevels.clear();
      _volumeSeenAt.clear();
      rethrow;
    }
  }

  static Future<void> leave() async {
    final engine = _engine;
    _engine = null; _activeAppId = null; _joined = false; _muted = false; _volumeLevels.clear(); _volumeSeenAt.clear();
    if (engine == null) return;
    try { await engine.leaveChannel(); } catch (_) {}
    try { await engine.release(); } catch (_) {}
  }

  static Future<void> setMuted(bool muted) async {
    final engine = _engine;
    if (engine == null || !_joined) return;
    await engine.muteLocalAudioStream(muted);
    _muted = muted;
    if (muted) { _volumeLevels.clear(); _volumeSeenAt.clear(); }
  }

  static Future<Map<int, double>> getVolumeLevels() async {
    final cutoff = DateTime.now().subtract(const Duration(milliseconds: 650));
    _volumeSeenAt.removeWhere((uid, seenAt) {
      if (seenAt.isBefore(cutoff)) {
        _volumeLevels.remove(uid);
        return true;
      }
      return false;
    });
    return Map<int, double>.from(_volumeLevels);
  }

  static Future<void> resumeAudio() async {
    final engine = _engine;
    if (engine == null || !_joined) return;
    await engine.enableAudio();
    await engine.adjustPlaybackSignalVolume(100);
    if (_muted) await engine.muteLocalAudioStream(true);
  }
}
