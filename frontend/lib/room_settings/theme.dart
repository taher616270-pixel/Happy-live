import 'package:flutter/material.dart';

class RS {
  static const primary = Color(0xFF26E9BF);
  static const primaryDark = Color(0xFF22CDAB);
  static const chipFill = Color(0xFFD9FAF3);
  static const bg = Colors.white;
  static const hintBar = Colors.white;
  static const divider = Color(0xFFEFEFF1);
  static const groupGap = Colors.white;
  static const text = Colors.black;
  static const gray = Color(0xFF777777);
  static const lightGray = Color(0xFFB0B0B0);
  static const switchGreen = Color(0xFF34C759);
  static const penBg = Color(0xFFEDEEF2);
  static const penIcon = Color(0xFF3B9BE8);
  static const shade = Color(0xFFF2F3F5);

  static ThemeData theme() => ThemeData(
        useMaterial3: false,
        scaffoldBackgroundColor: Colors.white,
        canvasColor: Colors.white,
        cardColor: Colors.white,
        dialogBackgroundColor: Colors.white,
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
          iconTheme: IconThemeData(color: Colors.black),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.black),
          bodyMedium: TextStyle(color: Colors.black),
          bodySmall: TextStyle(color: Colors.black),
          titleLarge: TextStyle(color: Colors.black),
          titleMedium: TextStyle(color: Colors.black),
          titleSmall: TextStyle(color: Colors.black),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      );
}
