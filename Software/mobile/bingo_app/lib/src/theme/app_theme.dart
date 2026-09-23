import 'package:flutter/material.dart';

class AppColors {
  static const navy = Color(0xFF0A1E3F);
  static const blue = Color(0xFF00AEEF);
  static const deepCyan = Color(0xFF007B91);
  static const green = Color(0xFF39D353);
  static const surface = Color(0xFFF4F8FC);
  static const line = Color(0xFFD8E7F5);
  static const textMuted = Color(0xFF637087);
  static const warning = Color(0xFFFFB020);
  static const scr4p = Color(0xFF8A2CFF);
  static const danger = Color(0xFFFF2B2B);
}

class AppMotion {
  static const fast = 150;
  static const standard = 260;
}

class AppElevation {
  static const buttonBlur = 10.0;
  static const buttonOffset = Offset(0, 4);
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.blue,
        primary: AppColors.blue,
        secondary: AppColors.green,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.surface,
      useMaterial3: true,
    );

    final textTheme = base.textTheme
        .apply(fontFamily: 'Inter')
        .copyWith(
          displaySmall: const TextStyle(
            fontFamily: 'Sora',
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
          headlineMedium: const TextStyle(
            fontFamily: 'Sora',
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
          titleLarge: const TextStyle(
            fontFamily: 'Sora',
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
          titleMedium: const TextStyle(
            fontFamily: 'Sora',
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
          bodyMedium: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            height: 1.35,
            color: AppColors.textMuted,
          ),
          labelLarge: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.navy,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.line),
        ),
      ),
    );
  }
}
