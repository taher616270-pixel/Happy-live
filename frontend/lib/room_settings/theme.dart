import 'package:flutter/material.dart';

class RS {
  static const primary = Color(0xFF26E9BF);
  static const primaryDark = Color(0xFF22CDAB);
  static const chipFill = Color(0xFFD9FAF3);
  static const bg = Color(0xFFF7F7F9);
  static const hintBar = Color(0xFFF5F6F8);
  static const divider = Color(0xFFEFEFF1);
  static const groupGap = Color(0xFFF1F1F5);
  static const text = Color(0xFF1B1B1F);
  static const gray = Color(0xFF9A9BA3);
  static const lightGray = Color(0xFFC7C8CC);
  static const switchGreen = Color(0xFF34C759);
  static const penBg = Color(0xFFEDEEF2);
  static const penIcon = Color(0xFF3B9BE8);
  static const shade = Color(0xFFF2F3F5);

  static ThemeData theme() => ThemeData(
        useMaterial3: false,
        scaffoldBackgroundColor: bg,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      );
}
