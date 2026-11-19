import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'models.dart';
import 'room_settings_api.dart';

class MockRoomSettingsApi implements RoomSettingsApi {
  @override
  Future<Map<String, dynamic>> loadSettings() async => {};
  @override
  Future<void> updateSetting(String key, Object value) async {}
  @override
  Future<void> updatePermission(String permissionId, PermissionLevel level, List<String> adminIds) async {}
  @override
  Future<Map<String, dynamic>> loadModeration() async => {'bans': [], 'kicks': [], 'muted': [], 'logs': []};
  @override
  Future<void> moderationAction(String action, String targetUserId) async {}
  @override
  Future<String> uploadCover(Uint8List bytes, String fileName) async => '';
}

class RoomSettingsController extends ChangeNotifier {
  RoomSettingsController({RoomSettingsApi? api}) : api = api ?? MockRoomSettingsApi();
  final RoomSettingsApi api;

  String name = '';
  String announcement = '';
  String? coverUrl;
  int seats = 8;
  String micRequestMode = 'إغلاق';
  bool autoGames = true;
  Audience whoEnter = Audience.everyone;
  Audience whoMic = Audience.membersOnly;
  Audience whoChat = Audience.everyone;
  Audience whoLuck = Audience.everyone;
  bool loading = false;
  bool moderationLoading = false;
  String? error;
  String? moderationError;

  List<RoomUser> admins = [];
  List<Map<String, dynamic>> bans = [];
  List<Map<String, dynamic>> kicks = [];
  List<Map<String, dynamic>> muted = [];
  List<AdminLogEntry> logs = [];

  late final List<AdminPermission> permissions = [
    AdminPermission(id: 'bg', group: 0, title: 'تغيير الخلفية/إعلان الغرفة', hint: 'من يمكنه تغيير الخلفية/إعلان الغرفة', level: PermissionLevel.selectedAdmins),
    AdminPermission(id: 'chat_delete', group: 0, title: 'حذف الدردشة', hint: 'من يمكنه حذف الدردشة'),
    AdminPermission(id: 'room_lock', group: 0, title: 'قفل/فتح الغرفة', hint: 'من يمكنه قفل/فتح الغرفة', level: PermissionLevel.selectedAdmins),
    AdminPermission(id: 'seat_count', group: 1, title: 'ضبط عدد المقاعد', hint: 'من يمكنه ضبط عدد المقاعد', level: PermissionLevel.selectedAdmins),
    AdminPermission(id: 'mic_lock', group: 1, title: 'فتح/قفل المايك', hint: 'من يمكنه فتح/قفل المايك'),
    AdminPermission(id: 'others_mic', group: 1, title: 'تشغيل/إيقاف ميكروفون الاخرين', hint: 'من يمكنه تشغيل/إيقاف ميكروفون الاخرين'),
    AdminPermission(id: 'invite_seat', group: 1, title: 'دعوة شخص للمقعد/ ازالة شخص من المقعد', hint: 'من يمكنه دعوة شخص للمقعد/ إزالته'),
    AdminPermission(id: 'mic_requests', group: 1, title: 'إدارة تقدم طلبات المستخدمين لأخذ المايك', hint: 'من يمكنه إدارة طلبات أخذ المايك'),
    AdminPermission(id: 'features', group: 2, title: 'تشغيل/إيقاف الألعاب والميزات', hint: 'من يمكنه فتح/قفل الألعاب والميزات'),
    AdminPermission(id: 'events', group: 2, title: 'إنشاء فعالية', hint: 'من يمكنه إنشاء الفعاليات'),
    AdminPermission(id: 'fireworks', group: 2, title: 'إطلاق الألعاب النارية', hint: 'من يمكنه إطلاق الألعاب النارية'),
    AdminPermission(id: 'mute', group: 3, title: 'كتم الصوت/الغاء كتم الصوت للاخرين', hint: 'من يمكنه كتم الصوت/الغاء كتم الصوت للاخرين'),
    AdminPermission(id: 'kick', group: 3, title: 'طرد شخص ما من الغرفة', hint: 'من يمكنه طرد شخص ما من الغرفة'),
    AdminPermission(id: 'blacklist', group: 3, title: 'ادارة القائمة السوداء للغرفة', hint: 'من يمكنه ادارة القائمة السوداء للغرفة'),
    AdminPermission(id: 'members', group: 3, title: 'إدارة الأعضاء', hint: 'من يمكنه إدارة الأعضاء'),
    AdminPermission(id: 'super', group: 3, title: 'المشرف السوبر', hint: 'من يمكنه إغلاق مايك المشرفين وطردهم', level: PermissionLevel.selectedAdmins),
  ];

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await api.loadSettings();
      final s = data['settings'] is Map ? Map<String, dynamic>.from(data['settings'] as Map) : <String, dynamic>{};
      name = (s['name'] ?? name).toString();
      announcement = (s['announcement'] ?? announcement).toString();
      coverUrl = s['coverUrl']?.toString();
      seats = int.tryParse((s['seats'] ?? seats).toString()) ?? seats;
      micRequestMode = (s['micRequestMode'] ?? micRequestMode).toString();
      autoGames = s['autoGames'] is bool ? s['autoGames'] as bool : autoGames;
      whoEnter = audienceFromValue(s['whoEnter'], whoEnter);
      whoMic = audienceFromValue(s['whoMic'], whoMic);
      whoChat = audienceFromValue(s['whoChat'], whoChat);
      whoLuck = audienceFromValue(s['whoLuck'], whoLuck);
      admins = (data['admins'] is List ? data['admins'] as List : const [])
          .whereType<Map>()
          .map((row) => RoomUser(
                id: (row['user_id'] ?? row['id'] ?? '').toString(),
                name: (row['display_name'] ?? row['name'] ?? 'مشرف').toString(),
                numericId: (row['public_id'] ?? row['numericId'] ?? '').toString(),
              ))
          .where((user) => user.id.isNotEmpty)
          .toList();
      final savedPermissions = data['permissions'] is Map
          ? Map<String, dynamic>.from(data['permissions'] as Map)
          : <String, dynamic>{};
      for (final permission in permissions) {
        final value = savedPermissions[permission.id];
        if (value is Map) {
          permission.level = permissionLevelFromValue(value['level']);
          permission.adminIds = value['adminIds'] is List
              ? (value['adminIds'] as List).map((id) => id.toString()).toList()
              : [];
        }
      }
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      loading = false;
      notifyListeners();
    }
    await refreshModeration();
  }

  Future<void> refreshModeration() async {
    moderationLoading = true;
    moderationError = null;
    notifyListeners();
    try {
      final data = await api.loadModeration();
      bans = _mapRows(data['bans']);
      kicks = _mapRows(data['kicks']);
      muted = _mapRows(data['muted']);
      final rows = _mapRows(data['logs']);
      logs = rows.map((row) {
        final action = (row['action'] ?? '').toString();
        final actor = (row['actor_name'] ?? 'مشرف').toString();
        final target = (row['target_name'] ?? 'مستخدم').toString();
        final category = switch (action) {
          'kick' || 'unkick' || 'ban' || 'unban' => 'طرد',
          'mute' || 'unmute' => 'كتم',
          'assign_moderator' || 'remove_moderator' => 'تعيين الأدوار',
          _ => 'عمليات أخرى',
        };
        final text = switch (action) {
          'kick' => 'تم طرد $target مؤقتًا',
          'unkick' => 'تم إلغاء الطرد المؤقت عن $target',
          'ban' => 'تم حظر $target من الغرفة',
          'unban' => 'تم رفع الحظر عن $target',
          'mute' => 'تم كتم $target',
          'unmute' => 'تم إلغاء كتم $target',
          'assign_moderator' => 'تم تعيين $target مشرفًا',
          'remove_moderator' => 'تمت إزالة $target من المشرفين',
          _ => 'إجراء على $target',
        };
        final date = DateTime.tryParse((row['created_at'] ?? '').toString())?.toLocal();
        final time = date == null ? '' : '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
        return AdminLogEntry(
          user: RoomUser(id: '', name: actor, numericId: ''),
          text: text,
          time: time,
          category: category,
        );
      }).toList();
    } catch (e) {
      moderationError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      moderationLoading = false;
      notifyListeners();
    }
  }

  List<Map<String, dynamic>> _mapRows(Object? value) => value is List
      ? value.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
      : <Map<String, dynamic>>[];

  Future<void> moderate(String action, String userId) async {
    await api.moderationAction(action, userId);
    await refreshModeration();
  }

  Future<void> setCoverBytes(Uint8List bytes, String fileName) async {
    final uploaded = await api.uploadCover(bytes, fileName);
    coverUrl = uploaded;
    error = null;
    notifyListeners();
  }

  Future<void> _set(String key, Object value, VoidCallback apply) async {
    apply();
    error = null;
    notifyListeners();
    try {
      await api.updateSetting(key, value);
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setName(String v) => _set('name', v, () => name = v);
  Future<void> setAnnouncement(String v) => _set('announcement', v, () => announcement = v);
  Future<void> setSeats(int v) => _set('seats', v, () => seats = v);
  Future<void> setMicRequestMode(String v) => _set('micRequestMode', v, () => micRequestMode = v);
  Future<void> setAutoGames(bool v) => _set('autoGames', v, () => autoGames = v);
  Future<void> setWhoEnter(Audience v) => _set('whoEnter', v.name, () => whoEnter = v);
  Future<void> setWhoMic(Audience v) => _set('whoMic', v.name, () => whoMic = v);
  Future<void> setWhoChat(Audience v) => _set('whoChat', v.name, () => whoChat = v);
  Future<void> setWhoLuck(Audience v) => _set('whoLuck', v.name, () => whoLuck = v);

  Future<void> savePermission(AdminPermission p, PermissionLevel level, List<String> ids) async {
    final oldLevel = p.level;
    final oldIds = List<String>.of(p.adminIds);
    p.level = level;
    p.adminIds = List.of(ids);
    error = null;
    notifyListeners();
    try {
      await api.updatePermission(p.id, level, p.adminIds);
    } catch (e) {
      p.level = oldLevel;
      p.adminIds = oldIds;
      error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }
}
