import 'dart:math';

class MicSeat {
  final String label;
  final bool big;
  const MicSeat(this.label, {this.big = false});
}

class MicLayout {
  final String id;
  final int count;
  final List<List<MicSeat?>> rows;

  const MicLayout({required this.id, required this.count, required this.rows});

  int get maxCols => rows.map((row) => row.length).reduce(max);

  int seatNumber(MicSeat seat) {
    final value = int.tryParse(seat.label);
    if (value != null) return value;
    if (seat.label == 'S1') return count - 1;
    if (seat.label == 'S2') return count;
    throw StateError('Unknown microphone seat label: ${seat.label}');
  }
}

List<MicSeat?> _seats(int from, int to, {bool big = false}) =>
    [for (var i = from; i <= to; i++) MicSeat('$i', big: big)];

const _s1 = MicSeat('S1');
const _s2 = MicSeat('S2');

/// Layouts are mirrored in the live room; labels map to actual seat numbers.
final List<MicLayout> kMicLayouts = [
  MicLayout(id: 'm8', count: 8, rows: [_seats(1, 4), _seats(5, 8)]),
  MicLayout(id: 'm10', count: 10, rows: [
    [null, _s1, _s2, null], _seats(1, 4), _seats(5, 8),
  ]),
  MicLayout(id: 'm12', count: 12, rows: [_seats(1, 4), _seats(5, 8), _seats(9, 12)]),
  MicLayout(id: 'm14', count: 14, rows: [
    [null, _s1, _s2, null], _seats(1, 4), _seats(5, 8), _seats(9, 12),
  ]),
  MicLayout(id: 'm16', count: 16, rows: [
    _seats(1, 4), _seats(5, 8), _seats(9, 12), _seats(13, 16),
  ]),
  MicLayout(id: 'm20', count: 20, rows: [
    [null, null, _s1, _s2, null, null],
    _seats(1, 6), _seats(7, 12), _seats(13, 18),
  ]),
  MicLayout(id: 'm24', count: 24, rows: [
    _seats(1, 6), _seats(7, 12), _seats(13, 18), _seats(19, 24),
  ]),
  MicLayout(id: 'm10b', count: 10, rows: [
    _seats(1, 2, big: true), _seats(3, 4, big: true), _seats(5, 10),
  ]),
  MicLayout(id: 'm10c', count: 10, rows: [
    _seats(1, 2, big: true), _seats(3, 6), _seats(7, 10),
  ]),
];

MicLayout micLayoutById(String id) =>
    kMicLayouts.firstWhere((layout) => layout.id == id, orElse: () => kMicLayouts.first);
