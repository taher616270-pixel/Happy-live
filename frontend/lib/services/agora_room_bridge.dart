import 'dart:js_interop';

@JS('window.happyLiveAgora.join')
external JSPromise<JSAny?> _agoraJoin(
  JSString appId,
  JSString channel,
  JSString token,
  JSNumber uid,
  JSBoolean publish,
);

@JS('window.happyLiveAgora.leave')
external JSPromise<JSAny?> _agoraLeave();

@JS('window.happyLiveAgora.setMuted')
external JSPromise<JSAny?> _agoraSetMuted(JSBoolean muted);

@JS('window.happyLiveAgora.resumeAudio')
external JSPromise<JSAny?> _agoraResumeAudio();

class AgoraRoomBridge {
  static Future<void> join({
    required String appId,
    required String channel,
    required String token,
    required int uid,
    required bool publish,
  }) async {
    await _agoraJoin(
      appId.toJS,
      channel.toJS,
      token.toJS,
      uid.toDouble().toJS,
      publish.toJS,
    ).toDart;
  }

  static Future<void> leave() async {
    try {
      await _agoraLeave().toDart;
    } catch (_) {
      // The room may close before the browser SDK has initialized.
    }
  }

  static Future<bool> setMuted(bool muted) async {
    try {
      final result = await _agoraSetMuted(muted.toJS).toDart;
      return result?.dartify() == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> resumeAudio() async {
    try {
      await _agoraResumeAudio().toDart;
    } catch (_) {
      // The user can retry audio recovery with the browser's recovery prompt.
    }
  }
}
