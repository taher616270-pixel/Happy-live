import 'models.dart';

abstract class RoomSettingsApi {
  Future<Map<String, dynamic>> loadSettings();
  Future<void> updateSetting(String key, Object value);
  Future<void> updatePermission(String permissionId, PermissionLevel level, List<String> adminIds);
}
