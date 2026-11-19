enum Audience { everyone, membersOnly, ownerAndAdmins }

String audienceLabel(Audience a) {
  switch (a) {
    case Audience.everyone: return 'الجميع';
    case Audience.membersOnly: return 'الاعضاء فقط';
    case Audience.ownerAndAdmins: return 'المالك/ المشرف فقط';
  }
}

Audience audienceFromValue(Object? value, Audience fallback) {
  for (final item in Audience.values) {
    if (item.name == value?.toString()) return item;
  }
  return fallback;
}

enum PermissionLevel { ownerOnly, allAdmins, selectedAdmins }

String levelLabel(PermissionLevel l) {
  switch (l) {
    case PermissionLevel.ownerOnly: return 'المالك فقط';
    case PermissionLevel.allAdmins: return 'جميع المشرفين';
    case PermissionLevel.selectedAdmins: return 'المشرفين المحددين';
  }
}

PermissionLevel permissionLevelFromValue(Object? value) {
  for (final item in PermissionLevel.values) {
    if (item.name == value?.toString()) return item;
  }
  return PermissionLevel.allAdmins;
}

class RoomUser {
  final String id;
  final String name;
  final String? avatarUrl;
  final int level;
  final String numericId;
  const RoomUser({required this.id, required this.name, this.avatarUrl, this.level = 1, this.numericId = ''});
}

class AdminPermission {
  final String id;
  final String title;
  final String hint;
  final int group;
  PermissionLevel level;
  List<String> adminIds;

  AdminPermission({
    required this.id,
    required this.title,
    required this.hint,
    required this.group,
    this.level = PermissionLevel.allAdmins,
    List<String>? adminIds,
  }) : adminIds = adminIds ?? [];

  String get subtitle {
    switch (level) {
      case PermissionLevel.ownerOnly: return 'المالك فقط';
      case PermissionLevel.allAdmins: return 'جميع المشرفين';
      case PermissionLevel.selectedAdmins: return '${adminIds.length} حدد مشرفين';
    }
  }
}

class AdminLogEntry {
  final RoomUser user;
  final String text;
  final String time;
  final String category;
  const AdminLogEntry({required this.user, required this.text, required this.time, required this.category});
}

class SeatOption {
  final int count;
  final bool locked;
  final bool vip;
  const SeatOption(this.count, {this.locked = false, this.vip = false});
}
