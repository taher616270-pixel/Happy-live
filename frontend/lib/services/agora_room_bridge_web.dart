import 'dart:convert';
import 'dart:js_interop';

@JS('window.happyLiveAgora.join')
external JSPromise<JSAny?> _agoraJoin(JSString appId, JSString channel, JSString token, JSNumber uid, JSBoolean publish);
@JS('window.happyLiveAgora.leave')
external JSPromise<JSAny?> _agoraLeave();
@JS('window.happyLiveAgora.setMuted')
external JSPromise<JSAny?> _agoraSetMuted(JSBoolean muted);
@JS('window.happyLiveAgora.setPublishing')
external JSPromise<JSAny?> _agoraSetPublishing(JSBoolean enabled, JSString token);
@JS('window.happyLiveAgora.resumeAudio')
external JSPromise<JSAny?> _agoraResumeAudio();
@JS('window.happyLiveAgora.getVolumeLevels')
external JSString _agoraGetVolumeLevels();

class AgoraRoomBridge {
  static Future<void> join({required String appId, required String channel, required String token, required int uid, required bool publish}) async {
    await _agoraJoin(appId.toJS, channel.toJS, token.toJS, uid.toDouble().toJS, publish.toJS).toDart;
  }
  static Future<void> leave() async { try { await _agoraLeave().toDart; } catch (_) {} }
  static Future<void> setMuted(bool muted) async { try { await _agoraSetMuted(muted.toJS).toDart; } catch (_) {} }
  static Future<void> setPublishing(bool enabled, {String token = ''}) async {
    await _agoraSetPublishing(enabled.toJS, token.toJS).toDart;
  }
  static Future<Map<int, double>> getVolumeLevels() async {
    try {
      final decoded = jsonDecode(_agoraGetVolumeLevels().toDart);
      if (decoded is! Map) return <int, double>{};
      final result = <int, double>{};
      decoded.forEach((key, value) {
        final uid = int.tryParse(key.toString());
        if (uid != null && uid > 0 && value is num) result[uid] = value.toDouble().clamp(0.0, 1.0).toDouble();
      });
      return result;
    } catch (_) { return <int, double>{}; }
  }
  static Future<void> resumeAudio() async { try { await _agoraResumeAudio().toDart; } catch (_) {} }
}
