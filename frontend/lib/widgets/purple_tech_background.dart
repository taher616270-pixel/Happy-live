import 'package:flutter/material.dart';

/// Restored original Happy Live dark background with soft ambient color glows.
class PurpleTechBackground extends StatelessWidget {
  const PurpleTechBackground({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF07050F)),
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.85, -0.9),
                radius: 1.05,
                colors: [Color(0x1A7C3AED), Color(0x007C3AED)],
                stops: [0.0, 1.0],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.9, -0.75),
                radius: 1.0,
                colors: [Color(0x16EC4899), Color(0x00EC4899)],
                stops: [0.0, 1.0],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, 1.0),
                radius: 1.0,
                colors: [Color(0x0CF59E0B), Color(0x00F59E0B)],
                stops: [0.0, 1.0],
              ),
            ),
          ),
        ),
        if (child != null) SizedBox.expand(child: child!),
      ],
    );
  }
}
