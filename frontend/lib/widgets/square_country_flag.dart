import 'package:flutter/material.dart';

/// Displays country flags in a square viewport without stretching the artwork.
class SquareCountryFlag extends StatelessWidget {
  const SquareCountryFlag(this.flag, {super.key, this.size = 24});

  final String flag;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (flag.isEmpty) return SizedBox(width: size, height: size);
    if (flag == 'SOUTH_ARABIA') {
      return SizedBox(
        width: size,
        height: size,
        child: ClipRect(
          child: Image.asset(
            'web/assets/south-arabia-v2.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: Text(flag, style: TextStyle(fontSize: size)),
        ),
      ),
    );
  }
}
