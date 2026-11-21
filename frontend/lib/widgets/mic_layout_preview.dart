import 'dart:math';
import 'package:flutter/material.dart';
import '../models/mic_layout.dart';

const kTeal = Color(0xFF17D4BE);

/// Preview follows the existing Happy Live room-seat appearance:
/// translucent avatar circles and the same empty-seat icon, not a new mic design.
class MicLayoutPreview extends StatelessWidget {
  final MicLayout layout;
  final bool selected;

  const MicLayoutPreview({super.key, required this.layout, required this.selected});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final diameter = min(28.0, width * .78 / layout.maxCols);
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? const Color(0xFFD4AF37) : Colors.transparent, width: 2.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(fit: StackFit.expand, children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0E1A3A), Color(0xFF16365A)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final row in layout.rows)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (final seat in row)
                          Expanded(
                            child: seat == null
                                ? const SizedBox(height: 1)
                                : Center(
                                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                                      Container(
                                        width: seat.big ? diameter * 1.15 : diameter,
                                        height: seat.big ? diameter * 1.15 : diameter,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: seat.big ? const Color(0x33E8C477) : Colors.white.withOpacity(.14),
                                          border: Border.all(
                                            color: seat.big ? const Color(0xFFFFD98A) : Colors.white.withOpacity(.48),
                                            width: seat.big ? 1.7 : 1,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(color: Color(0x99000000), blurRadius: 4, offset: Offset(0, 1)),
                                          ],
                                        ),
                                        child: Icon(Icons.weekend_outlined,
                                          color: Colors.white.withOpacity(.92),
                                          size: diameter * (seat.big ? .46 : .42)),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(seat.label,
                                        style: const TextStyle(color: Colors.white, fontSize: 5.5, height: 1)),
                                    ]),
                                  ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            if (selected)
              Positioned(
                top: 4, left: 4,
                child: Container(
                  width: 18, height: 18,
                  decoration: const BoxDecoration(color: Color(0xFFD4AF37), shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 13),
                ),
              ),
          ]),
        ),
      );
    });
  }
}
