import 'package:flutter/material.dart';

class ChiefTheme {
  static ThemeData fromName(String themeName) {
    switch (themeName) {
      case 'black-ice':
        return _buildTheme(
          bg: const Color(0xFF070A10),
          panel: const Color(0xFF141D28),
          surface: const Color(0xFF1D2A3A),
          accent: const Color(0xFF75D5FF),
        );
      case 'obsidian-blue':
        return _buildTheme(
          bg: const Color(0xFF03060F),
          panel: const Color(0xFF101A32),
          surface: const Color(0xFF1A2A4A),
          accent: const Color(0xFF5FA0FF),
        );
      default:
        return _buildTheme(
          bg: const Color(0xFF05070A),
          panel: const Color(0xFF11161F),
          surface: const Color(0xFF171D29),
          accent: const Color(0xFFF3CC78),
        );
    }
  }

  static ThemeData _buildTheme({
    required Color bg,
    required Color panel,
    required Color surface,
    required Color accent,
  }) {
    return ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: surface, brightness: Brightness.dark, primary: surface, secondary: accent),
        scaffoldBackgroundColor: bg,
        cardTheme: CardThemeData(color: panel, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontWeight: FontWeight.w800),
          titleLarge: TextStyle(fontWeight: FontWeight.w700),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF0B1017),
          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(18)), borderSide: BorderSide(color: Color(0xFF2A3344))),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? accent : null),
          trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? accent.withValues(alpha: 0.45) : null),
        ));
  }
}
