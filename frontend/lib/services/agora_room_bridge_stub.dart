class AgoraRoomBridge {
  static Future<void> join({required String appId, required String channel, required String token, required int uid, required bool publish}) async {
    throw UnsupportedError('Agora audio is not supported on this platform.');
  }
  static Future<void> leave() async {}
  static Future<void> setMuted(bool muted) async {}
  static Future<void> setPublishing(bool enabled, {String token = ''}) async {}
  static Future<Map<int, double>> getVolumeLevels() async => <int, double>{};
  static Future<void> resumeAudio() async {}
}
