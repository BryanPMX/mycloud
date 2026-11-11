import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();
  static const ink = Color(0xFF252923);
  static const coral = Color(0xFFB94F38);
  static const paper = Color(0xFFFAF9F6);
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(seedColor: coral, brightness: brightness).copyWith(
      primary: dark ? const Color(0xFFF1A28C) : coral,
      onPrimary: dark ? ink : Colors.white,
      secondary: dark ? const Color(0xFFBFC8AF) : const Color(0xFF596748),
      surface: dark ? const Color(0xFF20231F) : Colors.white,
      onSurface: dark ? const Color(0xFFF3F0E8) : ink,
      onSurfaceVariant:
          dark ? const Color(0xFFB6B8AE) : const Color(0xFF6E7268),
      outline: dark ? const Color(0xFF5F645A) : const Color(0xFF969A8F),
      outlineVariant: dark ? const Color(0xFF363B32) : const Color(0xFFE5E6DF),
      surfaceContainerHighest:
          dark ? const Color(0xFF30352B) : const Color(0xFFEEEFE8),
      primaryContainer:
          dark ? const Color(0xFF573B30) : const Color(0xFFFBE9E2),
    );
    final base = ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        fontFamily: 'Manrope',
        brightness: brightness,
        scaffoldBackgroundColor: dark ? const Color(0xFF181B17) : paper,
        splashFactory: InkSparkle.splashFactory);
    final text = base.textTheme;
    return base.copyWith(
        textTheme: text.copyWith(
            displaySmall: text.displaySmall?.copyWith(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.7,
                height: 1.15),
            headlineMedium: text.headlineMedium?.copyWith(
                fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -1.1),
            headlineSmall: text.headlineSmall?.copyWith(
                fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.6),
            titleLarge: text.titleLarge?.copyWith(
                fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4),
            titleMedium:
                text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            bodyLarge: text.bodyLarge?.copyWith(fontSize: 15, height: 1.6),
            bodyMedium: text.bodyMedium?.copyWith(fontSize: 13, height: 1.5),
            labelLarge: text.labelLarge
                ?.copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
        cardTheme: CardThemeData(
            color: scheme.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: scheme.outlineVariant))),
        appBarTheme: AppBarTheme(
            backgroundColor: base.scaffoldBackgroundColor,
            foregroundColor: scheme.onSurface,
            surfaceTintColor: Colors.transparent,
            centerTitle: false,
            elevation: 0),
        dividerTheme: DividerThemeData(
            color: scheme.outlineVariant, thickness: 1, space: 1),
        filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: scheme.onSurface,
                foregroundColor: scheme.surface,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)))),
        outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: scheme.onSurface,
                side: BorderSide(color: scheme.outlineVariant),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)))),
        iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
        inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: dark ? const Color(0xFF292D25) : const Color(0xFFF2F3EE),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: scheme.primary, width: 1.5))),
        chipTheme: base.chipTheme.copyWith(
            side: BorderSide.none,
            backgroundColor: scheme.surfaceContainerHighest,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7)),
        dialogTheme:
            DialogThemeData(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
        snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: scheme.onSurface, contentTextStyle: TextStyle(color: scheme.surface, fontFamily: 'Manrope'), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder()
        }),
        progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary, linearMinHeight: 3));
  }
}
