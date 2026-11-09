import 'package:flutter/foundation.dart';

@immutable
class SeatState {
  const SeatState({
    required this.seatNumber,
    this.userId = '',
    this.name = '',
    this.userCode = '',
    this.avatarUrl = '',
    this.uid,
    this.isMuted = false,
    this.isLocked = false,
    this.isRoomOwner = false,
    this.isRoomModerator = false,
    this.isMe = false,
    this.isPending = false,
  });

  final int seatNumber;
  final String userId;
  final String name;
  final String userCode;
  final String avatarUrl;
  final int? uid;
  final bool isMuted;
  final bool isLocked;
  final bool isRoomOwner;
  final bool isRoomModerator;
  final bool isMe;
  final bool isPending;

  bool get occupied => userId.isNotEmpty || isMe;

  factory SeatState.empty(int number) => SeatState(seatNumber: number);

  factory SeatState.fromMap(Map<String, dynamic> map, {required bool isMe}) {
    final code = (map['userCode'] ?? '').toString();
    return SeatState(
      seatNumber: (map['seatNumber'] as num).toInt(),
      userId: (map['userId'] ?? '').toString(),
      name: (map['name'] ?? 'مستخدم').toString(),
      userCode: code,
      avatarUrl: (map['avatarUrl'] ?? map['avatar'] ?? '').toString(),
      uid: map['uid'] is num ? (map['uid'] as num).toInt() : int.tryParse(code),
      isMuted: map['isMuted'] == true,
      isLocked: map['isLocked'] == true || map['locked'] == true,
      isRoomOwner: map['isRoomOwner'] == true,
      isRoomModerator: map['isRoomModerator'] == true,
      isMe: isMe,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'seatNumber': seatNumber,
    'userId': userId,
    'name': name,
    'userCode': userCode,
    'avatarUrl': avatarUrl,
    'uid': uid,
    'isMuted': isMuted,
    'isLocked': isLocked,
    'isRoomOwner': isRoomOwner,
    'isRoomModerator': isRoomModerator,
    'isMe': isMe,
    'isPending': isPending,
  };

  SeatState copyWith({bool? isPending}) => SeatState(
    seatNumber: seatNumber,
    userId: userId,
    name: name,
    userCode: userCode,
    avatarUrl: avatarUrl,
    uid: uid,
    isMuted: isMuted,
    isLocked: isLocked,
    isRoomOwner: isRoomOwner,
    isRoomModerator: isRoomModerator,
    isMe: isMe,
    isPending: isPending ?? this.isPending,
  );
}

@immutable
class SeatMoveCommand {
  const SeatMoveCommand({required this.from, required this.to, required this.version});
  final int? from;
  final int to;
  final int version;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': 'move_seat',
    'from': from,
    'to': to,
    'version': version,
  };
}

class SeatStateStore extends ChangeNotifier {
  SeatStateStore() {
    _version = DateTime.now().microsecondsSinceEpoch;
    for (var number = 1; number <= 8; number++) {
      _seats[number] = SeatState.empty(number);
    }
  }

  final Map<int, SeatState> _seats = <int, SeatState>{};
  final Map<int, Map<int, SeatState>> _rollbackSnapshots = <int, Map<int, SeatState>>{};
  final Map<int, int> _pendingTargetByVersion = <int, int>{};
  final Set<int> _pendingTargets = <int>{};
  int _version = 0;
  int? _mySeat;
  String currentUserId = '';
  String currentUserName = 'مستخدم';
  String currentUserCode = '';
  String currentAvatarUrl = '';

  Map<int, SeatState> get seats => Map<int, SeatState>.unmodifiable(_seats);
  int? get mySeat => _mySeat;
  int get latestVersion => _version;
  bool get hasPendingMoves => _pendingTargetByVersion.isNotEmpty;
  Set<int> get pendingTargets => Set<int>.unmodifiable(_pendingTargets);
  bool isPending(int seat) => _pendingTargets.contains(seat);

  void setCurrentUser({
    required String userId,
    String name = 'مستخدم',
    String userCode = '',
    String avatarUrl = '',
  }) {
    currentUserId = userId;
    currentUserName = name;
    currentUserCode = userCode;
    currentAvatarUrl = avatarUrl;
  }

  void applySnapshot(List<dynamic> rawSeats, {int? mySeat}) {
    final next = <int, SeatState>{
      for (var number = 1; number <= 8; number++) number: SeatState.empty(number),
    };
    for (final raw in rawSeats) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final number = map['seatNumber'];
      if (number is! num || number < 1 || number > 8) continue;
      final seatNumber = number.toInt();
      final ownerId = (map['userId'] ?? '').toString();
      final isMine = mySeat == seatNumber ||
          (ownerId.isNotEmpty && ownerId == currentUserId) ||
          map['isMe'] == true;
      next[seatNumber] = SeatState.fromMap(map, isMe: isMine);
    }
    _seats
      ..clear()
      ..addAll(next);
    _mySeat = mySeat ??
        _seats.values.where((seat) => seat.isMe).map((seat) => seat.seatNumber).firstOrNull;
    notifyListeners();
  }

  SeatMoveCommand? beginOptimisticMove(int target) {
    if (target < 1 || target > 8 || _pendingTargets.contains(target)) return null;
    final destination = _seats[target]!;
    if (destination.occupied && !destination.isMe) return null;
    if (_mySeat == target) return null;

    final previous = Map<int, SeatState>.from(_seats);
    final from = _mySeat;
    final mine = from == null
        ? SeatState(
            seatNumber: target,
            userId: currentUserId,
            name: currentUserName,
            userCode: currentUserCode,
            avatarUrl: currentAvatarUrl,
            uid: int.tryParse(currentUserCode),
            isMe: true,
          )
        : _seats[from]!.copyWith(isPending: true);

    if (from != null) _seats[from] = SeatState.empty(from);
    _seats[target] = SeatState(
      seatNumber: target,
      userId: mine.userId,
      name: mine.name,
      userCode: mine.userCode,
      avatarUrl: mine.avatarUrl,
      uid: mine.uid,
      isMuted: mine.isMuted,
      isRoomOwner: mine.isRoomOwner,
      isRoomModerator: mine.isRoomModerator,
      isMe: true,
      isPending: true,
    );
    _mySeat = target;
    final version = ++_version;
    _rollbackSnapshots[version] = previous;
    _pendingTargetByVersion[version] = target;
    _pendingTargets.add(target);
    notifyListeners();
    return SeatMoveCommand(from: from, to: target, version: version);
  }

  bool isLatest(int version) => version == _version;

  void resolveMove({
    required int version,
    required bool accepted,
    required List<dynamic> serverSeats,
    int? serverMySeat,
  }) {
    final target = _pendingTargetByVersion.remove(version);
    if (target != null) _pendingTargets.remove(target);
    _rollbackSnapshots.remove(version);
    if (version == _version) {
      if (accepted) {
        applySnapshot(serverSeats, mySeat: serverMySeat);
      } else {
        applySnapshot(serverSeats, mySeat: serverMySeat);
      }
    } else {
      notifyListeners();
    }
  }

  void rollbackAfterDisconnect(int version) {
    final target = _pendingTargetByVersion.remove(version);
    if (target != null) _pendingTargets.remove(target);
    final previous = _rollbackSnapshots.remove(version);
    if (version == _version && previous != null) {
      _seats
        ..clear()
        ..addAll(previous);
      _mySeat = _seats.values.where((seat) => seat.isMe).map((seat) => seat.seatNumber).firstOrNull;
    }
    notifyListeners();
  }

  void applyRealtimeSnapshot(List<dynamic> rawSeats) {
    applySnapshot(rawSeats);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
