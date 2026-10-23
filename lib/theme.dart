import 'package:flutter/material.dart';

/// The corners of the note and of everything laid on the page.
const paperRadius = BorderRadius.all(Radius.circular(6));

/// What people write is set in Recursive's casual style, like a marker on a
/// sticky note. The app's own words keep the platform font.
const _handwritten = TextStyle(
  fontFamily: 'Recursive',
  fontVariations: [FontVariation('CASL', 1)],
);

/// [ColorScheme.primaryContainer] is the sticky note the thought is written
/// on, and [ColorScheme.primary] the button that sends it.
ThemeData buildTheme(Brightness brightness) {
  const graphite = Color(0xFF1D1D1B);
  const yellow = Color(0xFFFFD84A);
  final light = brightness == Brightness.light;
  final page = light ? const Color(0xFFF1F1EE) : const Color(0xFF161615);
  final ink = light ? graphite : const Color(0xFFECEBE6);
  final pencil = light ? const Color(0xFF6B6A65) : const Color(0xFF9C9B94);
  final line = light ? const Color(0xFFDCDBD5) : const Color(0xFF2C2B28);
  // Dimmed at night: a bright yellow block would glare.
  final note = light ? const Color(0xFFFFE04D) : const Color(0xFF433813);
  final onNote = light ? ink : const Color(0xFFFFF1B8);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: light ? graphite : yellow,
    onPrimary: light ? note : graphite,
    primaryContainer: note,
    onPrimaryContainer: onNote,
    secondary: pencil,
    onSecondary: page,
    error: light ? const Color(0xFFB3261E) : const Color(0xFFF2B8B5),
    onError: light ? Colors.white : const Color(0xFF601410),
    surface: page,
    onSurface: ink,
    onSurfaceVariant: pencil,
    outline: pencil,
    outlineVariant: line,
    inverseSurface: ink,
    onInverseSurface: page,
    inversePrimary: light ? note : const Color(0xFF6B5300),
  );

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: page,
    textTheme: TextTheme(
      displaySmall: _handwritten.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w400,
        height: 1.25,
        letterSpacing: -0.3,
      ),
      bodyLarge: _handwritten.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        height: 1.4,
        letterSpacing: 0,
        color: ink,
      ),
      titleSmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: ink,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        letterSpacing: 0.1,
        color: pencil,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: onNote,
      selectionHandleColor: onNote,
      selectionColor: onNote.withValues(alpha: 0.2),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: paperRadius),
      showCloseIcon: true,
    ),
  );
}
