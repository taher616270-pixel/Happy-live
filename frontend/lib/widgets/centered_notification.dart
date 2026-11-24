import 'dart:async';
import 'package:flutter/material.dart';

final Map<OverlayState, OverlayEntry> _activeNotifications = {};

/// Displays SnackBar messages as compact, centered capsules instead of
/// the default full-width bar at the bottom of the screen.
void showCenteredNotification(BuildContext context, SnackBar snackBar) {
  final overlay = Overlay.of(context, rootOverlay: true);
  _activeNotifications.remove(overlay)?.remove();

  final theme = Theme.of(context).snackBarTheme;
  final entry = OverlayEntry(
    builder: (overlayContext) {
      final maxWidth = MediaQuery.sizeOf(overlayContext).width - 40;
      return Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: .92, end: 1),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              builder: (context, scale, child) => Opacity(
                opacity: ((scale - .92) / .08).clamp(0.0, 1.0).toDouble(),
                child: Transform.scale(scale: scale, child: child),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Material(
                  color: snackBar.backgroundColor ?? theme.backgroundColor ?? const Color(0xEE24202B),
                  elevation: snackBar.elevation ?? theme.elevation ?? 10,
                  shape: snackBar.shape ?? theme.shape ?? const StadiumBorder(
                    side: BorderSide(color: Color(0x66E8C477), width: 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: snackBar.padding ?? const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                    child: DefaultTextStyle.merge(
                      style: snackBar.contentTextStyle ?? theme.contentTextStyle ??
                          const TextStyle(color: Colors.white, fontFamily: 'Tajawal', fontSize: 14, fontWeight: FontWeight.w700),
                      child: snackBar.content,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  _activeNotifications[overlay] = entry;
  overlay.insert(entry);
  Timer(snackBar.duration, () {
    if (_activeNotifications[overlay] == entry) {
      _activeNotifications.remove(overlay);
      entry.remove();
    }
  });
}
