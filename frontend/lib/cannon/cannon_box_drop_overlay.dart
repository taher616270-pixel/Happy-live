import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'cannon_api.dart';

class CannonBoxDropOverlay extends StatefulWidget {
  const CannonBoxDropOverlay({
    super.key,
    required this.roundId,
    this.demoMode = false,
    required this.onFinished,
  });

  final String roundId;
  final bool demoMode;
  final ValueChanged<List<Map<String, dynamic>>> onFinished;

  @override
  State<CannonBoxDropOverlay> createState() => _CannonBoxDropOverlayState();
}

class _CannonBoxDropOverlayState extends State<CannonBoxDropOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final Set<int> _opened = <int>{};
  final Set<int> _busy = <int>{};
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 19900),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finish();
      });
    _controller.forward();
  }

  Future<void> _open(int index) async {
    if (_finishing || _opened.contains(index) || !_busy.add(index)) return;
    setState(() {});
    final success = widget.demoMode
        ? true
        : await CannonApi.openBox(widget.roundId, index);
    if (!mounted) return;
    _busy.remove(index);
    if (success) _opened.add(index);
    setState(() {});
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    if (widget.demoMode) {
      if (mounted) widget.onFinished(<Map<String, dynamic>>[]);
      return;
    }
    List<Map<String, dynamic>>? results;
    for (var attempt = 0; attempt < 4 && results == null; attempt++) {
      if (attempt > 0) await Future<void>.delayed(const Duration(milliseconds: 250));
      results = await CannonApi.fetchBoxResults(widget.roundId);
    }
    if (!mounted) return;
    widget.onFinished(results ?? <Map<String, dynamic>>[]);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Keep the existing 19.9-second effect duration unchanged.
  static const int _totalDropMs = 19900;

  // Stagger every gift independently so the boxes overlap like continuous rain.
  // The deterministic per-index timing keeps every viewer's animation consistent.
  int _startMs(int index) {
    final random = math.Random(index * 104729 + 31);
    final interval = 245 + random.nextInt(41);
    return index * interval;
  }

  int _fallDurationMs(int index) {
    final random = math.Random(index * 15485863 + 47);
    return 4300 + random.nextInt(1201);
  }

  double _fraction(int index) {
    final elapsedMs = _controller.value * _totalDropMs;
    return ((elapsedMs - _startMs(index)) / _fallDurationMs(index))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return SizedBox.expand(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Stack(
          clipBehavior: Clip.none,
          children: [
            for (var index = 0; index < 50; index++)
              if (!_opened.contains(index) &&
                  _controller.value * _totalDropMs >= _startMs(index) &&
                  _fraction(index) < 1.0)
                _fallingBox(index, size),
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 22,
              child: Center(
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xE90A1742),
                    border: Border.all(color: const Color(0xFFFFD76A), width: 2),
                    boxShadow: const [
                      BoxShadow(color: Color(0x88FFD76A), blurRadius: 14),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${_opened.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallingBox(int index, Size screen) {
    final progress = _fraction(index);
    final random = math.Random(index * 7919 + 17);
    final boxSize = 38.0 + random.nextDouble() * 19.0;
    final maxLeft = math.max(0.0, screen.width - boxSize - 8.0).toDouble();
    final startLeft = 4.0 + random.nextDouble() * maxLeft;
    final drift = (random.nextDouble() - .5) * screen.width * .22;
    final sway = math.sin(progress * math.pi * 3.2 + index * .7) * 17;
    final left = (startLeft + drift * progress + sway)
        .clamp(0.0, maxLeft)
        .toDouble();
    final top = -boxSize - 20 + progress * (screen.height + boxSize + 50);
    final rotation = math.sin(progress * math.pi * 2.4 + index) * .16;
    final isBusy = _busy.contains(index);

    return Positioned(
      left: left,
      top: top,
      child: Transform.rotate(
        angle: rotation,
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isBusy ? null : () => _open(index),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: isBusy ? .55 : 1,
          child: Container(
            width: boxSize,
            height: boxSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: index.isEven
                    ? const [Color(0xFFFFD66B), Color(0xFFB86A16)]
                    : const [Color(0xFFFF75A8), Color(0xFF9F174F)],
              ),
              border: Border.all(color: const Color(0xFFFFF0BC), width: 1.4),
              boxShadow: const [
                BoxShadow(color: Color(0x88000000), blurRadius: 8, offset: Offset(0, 3)),
              ],
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    isBusy ? Icons.hourglass_top_rounded : Icons.card_giftcard_rounded,
                    color: Colors.white,
                    size: boxSize * .64,
                    shadows: const [Shadow(color: Colors.black45, blurRadius: 4)],
                  ),
                ),
                Positioned(
                  left: boxSize * .42,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 4, color: const Color(0xFFFFF0BC).withOpacity(.9)),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: boxSize * .42,
                  child: Container(height: 4, color: const Color(0xFFFFF0BC).withOpacity(.9)),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
