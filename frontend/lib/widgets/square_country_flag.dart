import 'package:flutter/material.dart';

/// Displays country flags as consistent square images on Android, iOS and Web.
class SquareCountryFlag extends StatelessWidget {
  const SquareCountryFlag(
    this.flag, {
    super.key,
    this.size = 24,
  });

  final String flag;
  final double size;

  /// Accepts either a two-letter ISO country code (SA) or a flag emoji (🇸🇦).
  /// Returns an empty string for unsupported values instead of rendering text.
  String _resolveCountryCode(String value) {
    final normalized = value.trim().toUpperCase();

    if (RegExp(r'^[A-Z]{2}$').hasMatch(normalized)) {
      return normalized.toLowerCase();
    }

    final regionalIndicators = normalized.runes
        .where((rune) => rune >= 0x1F1E6 && rune <= 0x1F1FF)
        .toList(growable: false);

    if (regionalIndicators.length != 2) {
      return '';
    }

    final countryCode = String.fromCharCodes(
      regionalIndicators.map((rune) => rune - 0x1F1E6 + 0x41),
    );

    return countryCode.toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    if (size <= 0 || flag.trim().isEmpty) {
      return SizedBox(width: size > 0 ? size : 0, height: size > 0 ? size : 0);
    }

    // South Arabia has its own local artwork and must never resolve to YE.
    if (flag.trim() == 'SOUTH_ARABIA') {
      return SizedBox.square(
        dimension: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.asset(
            'web/assets/south-arabia-v2.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) =>
                SizedBox.square(dimension: size),
          ),
        ),
      );
    }

    final countryCode = _resolveCountryCode(flag);
    if (countryCode.isEmpty) {
      return SizedBox.square(dimension: size);
    }

    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          'https://flagcdn.com/w40/$countryCode.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) =>
              SizedBox.square(dimension: size),
        ),
      ),
    );
  }
}
