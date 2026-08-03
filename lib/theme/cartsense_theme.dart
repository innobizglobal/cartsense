import 'package:flutter/material.dart';

abstract final class CartSenseColors {
  static const primary = Color(0xFF145A43);
  static const primaryDark = Color(0xFF0B3D2D);
  static const accent = Color(0xFFB7E45A);
  static const background = Color(0xFFF6F7F3);
  static const surface = Colors.white;
  static const surfaceMuted = Color(0xFFEDF3EF);
  static const text = Color(0xFF17221D);
  static const textMuted = Color(0xFF68756E);
  static const outline = Color(0xFFDCE4DF);
  static const warning = Color(0xFFFFF1CC);
  static const success = Color(0xFFE3F3D3);
}

ThemeData buildCartSenseTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: CartSenseColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: CartSenseColors.primary,
    onPrimary: Colors.white,
    secondary: CartSenseColors.accent,
    onSecondary: CartSenseColors.primaryDark,
    surface: CartSenseColors.surface,
    onSurface: CartSenseColors.text,
    outline: CartSenseColors.outline,
    surfaceContainerLow: CartSenseColors.surfaceMuted,
  );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: CartSenseColors.background,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: CartSenseColors.text,
      displayColor: CartSenseColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: CartSenseColors.background,
      foregroundColor: CartSenseColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: CartSenseColors.text,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: const CardThemeData(
      color: CartSenseColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 1.2,
      shadowColor: Color(0x220B3D2D),
      margin: EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: CartSenseColors.outline),
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: CartSenseColors.surface,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderSide: BorderSide(color: CartSenseColors.outline),
        borderRadius: BorderRadius.all(Radius.circular(15)),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: CartSenseColors.outline),
        borderRadius: BorderRadius.all(Radius.circular(15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: CartSenseColors.primary, width: 1.5),
        borderRadius: BorderRadius.all(Radius.circular(15)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        side: const BorderSide(color: CartSenseColors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: CartSenseColors.primaryDark,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: CartSenseColors.surfaceMuted,
      side: const BorderSide(color: CartSenseColors.outline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: CartSenseColors.surface,
      indicatorColor: CartSenseColors.success,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? CartSenseColors.primary
              : CartSenseColors.textMuted,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: CartSenseColors.outline,
      thickness: 1,
    ),
  );
}
