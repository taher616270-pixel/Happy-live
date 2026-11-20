int _i(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
String _s(dynamic v) => v?.toString() ?? '';

class CannonPrize {
  final String key, name, type, icon;
  final bool top1;
  const CannonPrize({required this.key, required this.name, required this.type, required this.icon, required this.top1});
  factory CannonPrize.fromJson(Map<String, dynamic> j) => CannonPrize(
    key: _s(j['key']), name: _s(j['name']), type: _s(j['type']),
    icon: _s(j['icon']), top1: j['top1'] == true,
  );
}

class CannonLevel {
  final int level, need;
  final String title;
  final List<CannonPrize> prizes;
  const CannonLevel({required this.level, required this.need, required this.title, required this.prizes});
  factory CannonLevel.fromJson(Map<String, dynamic> j) => CannonLevel(
    level: _i(j['level']),
    need: _i(j['need']),
    title: _s(j['title']).isEmpty ? 'Level ${_i(j['level'])}' : _s(j['title']),
    prizes: ((j['prizes'] as List?) ?? [])
      .whereType<Map>()
      .map((e) => CannonPrize.fromJson(Map<String, dynamic>.from(e)))
      .toList(),
  );
}

class CannonClaim {
  final String id, type, value, name;
  const CannonClaim({required this.id, required this.type, required this.value, required this.name});
  factory CannonClaim.fromJson(Map<String, dynamic> j) => CannonClaim(
    id: _s(j['id']), type: _s(j['reward_type']),
    value: _s(j['reward_value']), name: _s(j['reward_name']),
  );
}

class CannonState {
  final String roomId, launchId;
  final int level, progress, need, myContribution;
  final bool launching;
  final List<CannonLevel> levels;
  final List<CannonClaim> pending;

  const CannonState({
    required this.roomId, required this.launchId, required this.level,
    required this.progress, required this.need, required this.myContribution,
    required this.launching, required this.levels, required this.pending,
  });

  double get ratio => need <= 0 ? 0 : (progress / need).clamp(0.0, 1.0).toDouble();

  CannonLevel? levelCfg(int l) {
    for (final x in levels) {
      if (x.level == l) return x;
    }
    return null;
  }

  factory CannonState.fromJson(Map<String, dynamic> j) {
    final room = j['room'] is Map ? Map<String, dynamic>.from(j['room'] as Map) : <String, dynamic>{};
    final my = j['my'] is Map ? Map<String, dynamic>.from(j['my'] as Map) : <String, dynamic>{};
    return CannonState(
      roomId: _s(room['room_id']),
      launchId: _s(room['launch_id']),
      level: _i(room['level']),
      progress: _i(room['progress']),
      need: _i(room['need']),
      launching: room['launching'] == true,
      myContribution: _i(my['contribution']),
      levels: ((j['levels'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => CannonLevel.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
      pending: ((my['pending'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => CannonClaim.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    );
  }
}

class CannonBanner {
  final String roomId, title, avatar, text;
  final int ownerLevel, cannonLevel, percent;
  final bool launching;
  const CannonBanner({
    required this.roomId, required this.title, required this.avatar,
    required this.text, required this.ownerLevel, required this.cannonLevel,
    required this.percent, required this.launching,
  });
  factory CannonBanner.fromJson(Map<String, dynamic> j) => CannonBanner(
    roomId: _s(j['room_id']), title: _s(j['title']),
    avatar: _s(j['avatar']), text: _s(j['text']),
    ownerLevel: _i(j['owner_level']), cannonLevel: _i(j['cannon_level']),
    percent: _i(j['percent']), launching: j['launching'] == true,
  );
}


class CannonContributor {
  final String userId, userName, avatarUrl, publicId;
  final int contribution;
  const CannonContributor({
    required this.userId,
    required this.userName,
    required this.avatarUrl,
    required this.publicId,
    required this.contribution,
  });

  factory CannonContributor.fromJson(Map<String, dynamic> j) => CannonContributor(
    userId: _s(j['user_id']),
    userName: _s(j['user_name']).isEmpty ? 'مساهم' : _s(j['user_name']),
    avatarUrl: _s(j['avatar_url']),
    publicId: _s(j['public_id']),
    contribution: _i(j['contribution']),
  );
}
