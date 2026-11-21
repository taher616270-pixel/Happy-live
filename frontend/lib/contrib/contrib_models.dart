import 'package:flutter/material.dart';

enum ContribPeriod { daily, weekly, monthly }

class ContribBadge {
  const ContribBadge({
    required this.text,
    required this.color,
    required this.icon,
  });

  final String text;
  final Color color;
  final IconData icon;
}

class ContribEntry {
  const ContribEntry({
    required this.name,
    required this.avatarUrl,
    required this.amount,
    this.badges = const <ContribBadge>[],
  });

  final String name;
  final String avatarUrl;
  final int amount;
  final List<ContribBadge> badges;
}

class ContribData {
  const ContribData({
    required this.entries,
    this.me,
    this.myRank,
  });

  final List<ContribEntry> entries;
  final ContribEntry? me;
  final int? myRank;
}
