import 'package:flutter/material.dart';
import 'tokens.dart';

// Provides Dark (default) and Light ThemeData conforming to Flik minimal design tokens.
class FlikTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: FlikTokens.background,
      primaryColor: FlikTokens.accent,
      colorScheme: const ColorScheme.dark(
        primary: FlikTokens.accent,
        surface: FlikTokens.surface,
        background: FlikTokens.background,
        error: FlikTokens.danger,
        onPrimary: Colors.white,
        onSurface: FlikTokens.text,
        onBackground: FlikTokens.text,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: FlikTokens.background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: FlikTokens.text,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: FlikTokens.text),
      ),
      cardTheme: CardTheme(
        color: FlikTokens.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlikTokens.radiusGroup),
          side: const BorderSide(color: FlikTokens.line, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: FlikTokens.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(88, FlikTokens.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FlikTokens.radiusPill),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: FlikTokens.text,
          side: const BorderSide(color: FlikTokens.line, width: 1),
          minimumSize: const Size(88, FlikTokens.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FlikTokens.radiusPill),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: FlikTokens.surface,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlikTokens.radiusGroup),
          side: const BorderSide(color: FlikTokens.line, width: 1),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: FlikTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(FlikTokens.radiusSheet),
          ),
        ),
      ),
    );
  }
}
