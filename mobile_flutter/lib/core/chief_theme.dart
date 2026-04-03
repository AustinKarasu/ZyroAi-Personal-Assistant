import 'package:flutter/material.dart';

class ChiefTheme {
  static ThemeData get light {
    const bg = Color(0xFF05070A);
    const panel = Color(0xFF11161F);
    const surface = Color(0xFF171D29);
    const accent = Color(0xFFF3CC78);

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: surface, brightness: Brightness.dark, primary: surface, secondary: accent),
      scaffoldBackgroundColor: bg,
      cardTheme: const CardThemeData(color: panel, elevation: 0, margin: EdgeInsets.zero),
      appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(fontWeight: FontWeight.w700),
        titleLarge: TextStyle(fontWeight: FontWeight.w700),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFF0B1017),
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(18)), borderSide: BorderSide(color: Color(0xFF2A3344))),
      ),
    );
  }
}
