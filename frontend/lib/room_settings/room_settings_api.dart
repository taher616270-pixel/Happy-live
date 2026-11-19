import 'dart:typed_data';
import 'models.dart';

abstract class RoomSettingsApi {
  Future<Map<String, dynamic>> loadSettings();
  Future<void> updateSetting(String key, Object value);
  Future<void> updatePermission(String permissionId, PermissionLevel level, List<String> adminIds);
  Future<Map<String, dynamic>> loadModeration();
  Future<void> moderationAction(String action, String targetUserId);
  Future<String> uploadCover(Uint8List bytes, String fileName);
}
