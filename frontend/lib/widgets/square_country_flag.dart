import 'package:flutter/material.dart';
import 'package:world_flags/world_flags.dart';

/// Renders country flags as crisp vector graphics on every supported platform.
class SquareCountryFlag extends StatelessWidget {
  const SquareCountryFlag(
    this.flag, {
    super.key,
    this.size = 24,
  });

  final String flag;
  final double size;

  /// Accepts an ISO alpha-2 code (for example, "SA") or a flag emoji.
  String _resolveCountryCode(String value) {
    final normalized = value.trim().toUpperCase();

    if (RegExp(r'^[A-Z]{2}$').hasMatch(normalized)) {
      return normalized;
    }

    final regionalIndicators = normalized.runes
        .where((rune) => rune >= 0x1F1E6 && rune <= 0x1F1FF)
        .toList(growable: false);

    if (regionalIndicators.length != 2) {
      return '';
    }

    return String.fromCharCodes(
      regionalIndicators.map((rune) => rune - 0x1F1E6 + 0x41),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (size <= 0 || flag.trim().isEmpty) {
      return SizedBox.square(dimension: size > 0 ? size : 0);
    }

    final normalizedFlag = flag.trim();

    // South Arabia is a custom flag, not Yemen (YE).
    if (normalizedFlag == 'SOUTH_ARABIA') {
      return SizedBox.square(
        dimension: size,
        child: Center(
          // Let the custom flag paint at its requested dimensions instead of
          // being constrained back to the square slot by Center.
          child: OverflowBox(
            minWidth: size + 2,
            maxWidth: size + 2,
            minHeight: size - 2,
            maxHeight: size - 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset(
                'web/assets/south-arabia.png',
                width: size + 2,
                height: size - 2,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
                errorBuilder: (context, error, stackTrace) =>
                    SizedBox.square(dimension: size),
              ),
            ),
          ),
        ),
      );
    }

    final countryCode = _resolveCountryCode(normalizedFlag);
    if (countryCode.isEmpty) {
      return SizedBox.square(dimension: size);
    }

    final country = WorldCountry.maybeFromCodeShort(countryCode);
    if (country == null) {
      return SizedBox.square(dimension: size);
    }

    // Keep the full flag visible at its natural proportions inside a square
    // slot. Vector painting stays sharp without downloading raster images.
    return SizedBox.square(
      dimension: size,
      child: FittedBox(
        fit: BoxFit.contain,
        child: CountryFlag.simplified(
          country,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}
