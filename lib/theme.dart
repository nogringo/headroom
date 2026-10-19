import 'package:flutter/material.dart';

ThemeData buildTheme(Brightness brightness) {
  final light = brightness == Brightness.light;
  final background = light ? const Color(0xFFEAEFF3) : const Color(0xFF0F151C);
  final ink = light ? const Color(0xFF162231) : const Color(0xFFE2E9EF);
  final muted = light ? const Color(0xFF5E6E7F) : const Color(0xFF8595A6);
  final line = light ? const Color(0xFFCCD6DF) : const Color(0xFF243140);
  final accent = light ? const Color(0xFF1D4E89) : const Color(0xFF8FB6E6);
  final onAccent = light ? Colors.white : background;

  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
    primary: accent,
    onPrimary: onAccent,
    surface: background,
    onSurface: ink,
    onSurfaceVariant: muted,
    outlineVariant: line,
  );

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    textTheme: TextTheme(
      displaySmall: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w300,
        height: 1.2,
        letterSpacing: -0.4,
        color: ink,
      ),
      bodyLarge: TextStyle(
        fontSize: 17,
        height: 1.35,
        letterSpacing: 0,
        color: ink,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        letterSpacing: 0.1,
        color: muted,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionHandleColor: accent,
      selectionColor: accent.withValues(alpha: 0.25),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
