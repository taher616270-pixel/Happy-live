import 'package:flutter/material.dart';

enum RoomRole { owner, admin, member }

extension RoomRoleX on RoomRole {
  bool get canManage => this != RoomRole.member;
}

enum ToolSection { interactive, admin, other, more }

class RoomTool {
  final String id;
  final String label;
  final ToolSection section;
  final Widget icon;
  final VoidCallback onTap;

  const RoomTool({
    required this.id,
    required this.label,
    required this.section,
    required this.icon,
    required this.onTap,
  });
}

class KickEntry {
  final String name;
  final String avatar;
  final String by;
  final String reason;
  final DateTime time;

  const KickEntry({
    required this.name,
    required this.avatar,
    required this.by,
    required this.reason,
    required this.time,
  });
}
