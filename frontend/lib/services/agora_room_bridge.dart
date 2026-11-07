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
}
