import 'package:flutter/material.dart';

abstract final class BogleColors {
  static const cream = Color(0xFFFFFEEE);
  static const ink = Color(0xFF172033);
  static const muted = Color(0xFF6B7280);
  static const blue = Color(0xFF8199FF);
  static const blueStrong = Color(0xFF4D6FFF);
  static const blueSoft = Color(0xFFDDE5FF);
  static const mint = Color(0xFFBDEFD3);
  static const pink = Color(0xFFFFD4DF);
  static const yellow = Color(0xFFFFE89A);
  static const line = Color(0x1A172033);

  /// Figma style "메인 로고".
  static const logo = Color(0xFF8BA2FF);

  /// Figma style "Black".
  static const text = Color(0xFF333333);
}

/// Figma's soft card shadow (x 0, y 0, blur 4, spread 1, 15 % black): white
/// cards, panels, the setting buttons and the house balloon's box.
const figmaShadow = [
  BoxShadow(color: Color(0x26000000), blurRadius: 4, spreadRadius: 1),
];

/// The app's display typeface: 양진체 (Yangjin). The roles below use it;
/// they stay separate so one can change alone.
const bogleFont = 'Yangjin';

/// Figma's interface lettering: page pills, chips, button labels and other
/// small text set in Pretendard beside the 양진체 titles.
const bogleUiFont = 'Pretendard';

/// Kid-facing titles and buttons.
const bogleDisplayFont = bogleFont;

/// The friend's questions in setup.
const bogleQuestionFont = bogleFont;

/// Reading text, settings explanations and editable content.
const bogleBodyFont = bogleUiFont;

/// Wraps a screen that sets its body copy in [font] ([bogleBodyFont] unless
/// given). Dialogs opened from it capture this theme too.
Widget withBogleBodyFont(
  BuildContext context,
  Widget child, {
  String font = bogleBodyFont,
}) {
  final base = Theme.of(context);
  return Theme(
    data: base.copyWith(
      textTheme: base.textTheme.copyWith(
        bodyLarge: base.textTheme.bodyLarge?.copyWith(fontFamily: font),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(fontFamily: font),
        bodySmall: base.textTheme.bodySmall?.copyWith(fontFamily: font),
      ),
    ),
    child: DefaultTextStyle.merge(
      style: TextStyle(fontFamily: font),
      child: child,
    ),
  );
}

ThemeData buildBogleTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: BogleColors.blue,
    surface: BogleColors.cream,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: BogleColors.cream,
    fontFamily: bogleBodyFont,
    dialogTheme: const DialogThemeData(
      titleTextStyle: TextStyle(
        fontFamily: bogleDisplayFont,
        fontSize: 24,
        color: BogleColors.text,
      ),
      contentTextStyle: TextStyle(
        fontFamily: bogleBodyFont,
        fontSize: 16,
        height: 1.5,
        color: BogleColors.text,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontFamily: bogleDisplayFont),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        textStyle: const TextStyle(fontFamily: bogleDisplayFont),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        textStyle: const TextStyle(fontFamily: bogleDisplayFont),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        textStyle: const TextStyle(fontFamily: bogleDisplayFont),
      ),
    ),
    splashFactory: InkSparkle.splashFactory,
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontFamily: bogleDisplayFont,
        fontSize: 52,
        height: 1.08,
        fontWeight: FontWeight.w800,
        letterSpacing: -2.2,
        color: BogleColors.ink,
      ),
      headlineLarge: TextStyle(
        fontFamily: bogleDisplayFont,
        fontSize: 36,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
        color: BogleColors.ink,
      ),
      headlineMedium: TextStyle(
        fontFamily: bogleDisplayFont,
        fontSize: 27,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: BogleColors.ink,
      ),
      titleLarge: TextStyle(
        fontFamily: bogleDisplayFont,
        fontSize: 22,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.45,
        color: BogleColors.ink,
      ),
      titleMedium: TextStyle(
        fontFamily: bogleDisplayFont,
        fontSize: 18,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: BogleColors.ink,
      ),
      bodyLarge: TextStyle(
        fontSize: 17,
        height: 1.55,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.25,
        color: BogleColors.ink,
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        height: 1.5,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
        color: BogleColors.muted,
      ),
      labelLarge: TextStyle(
        fontFamily: bogleDisplayFont,
        fontSize: 16,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.86),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: BogleColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: BogleColors.blueStrong, width: 2),
      ),
    ),
  );
}
