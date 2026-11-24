import 'package:flutter/material.dart';

/// Boutique Atelier (Warm Editorial Retail) color tokens.
abstract final class AppColors {
  static const canvas = Color(0xFFF7F4EF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF1ECE4);
  static const border = Color(0xFFE7E0D6);
  static const borderStrong = Color(0xFFD6CCBE);

  static const ink = Color(0xFF231F20);
  static const inkMuted = Color(0xFF6B625B);

  static const terracotta = Color(0xFFB85D3B);
  static const terracottaSoft = Color(0xFFF5E6DF);

  static const olive = Color(0xFF3D6B4F);
  static const oliveSoft = Color(0xFFE6F0EA);

  static const brick = Color(0xFFB53838);
  static const brickSoft = Color(0xFFF8E5E5);

  static const ochre = Color(0xFFB7791F);
  static const ochreSoft = Color(0xFFF9EFE0);
}

/// Shared Hungarian formatting helpers for currency, locations, and payments.
abstract final class AppFormat {
  /// Formats a numeric or string price in Hungarian Forint (e.g. `30 000 Ft`).
  static String forint(dynamic value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0.0;
    return '${amount(number)} Ft';
  }

  /// Formats a number with space thousands separators (e.g. `30 000` or `1 250,50`).
  static String amount(double value) {
    final negative = value < 0;
    final abs = value.abs();
    final isWhole = abs == abs.roundToDouble();
    final fixed = isWhole ? abs.toStringAsFixed(0) : abs.toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final grouped = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      final remaining = intPart.length - i;
      if (i > 0 && remaining % 3 == 0) grouped.write(' ');
      grouped.write(intPart[i]);
    }
    final prefix = negative ? '-' : '';
    if (isWhole) return '$prefix$grouped';
    return '$prefix$grouped,${parts[1]}';
  }

  static String paymentMethod(String? method) => switch (method) {
    'cash' => 'Készpénz',
    'card' => 'Kártya',
    'mixed' => 'Készpénz + kártya',
    _ => method ?? '-',
  };

  static String locationLabel(String location) =>
      location == 'All locations' ? 'Összes üzlet' : location;
}

/// Centralized Boutique Atelier Material 3 theme.
abstract final class AppTheme {
  static ThemeData light() {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.ink,
      onPrimary: Colors.white,
      primaryContainer: AppColors.terracottaSoft,
      onPrimaryContainer: AppColors.ink,
      secondary: AppColors.terracotta,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.surfaceMuted,
      onSecondaryContainer: AppColors.ink,
      tertiary: AppColors.olive,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.oliveSoft,
      onTertiaryContainer: AppColors.olive,
      error: AppColors.brick,
      onError: Colors.white,
      errorContainer: AppColors.brickSoft,
      onErrorContainer: AppColors.brick,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      surfaceContainerLowest: AppColors.surface,
      surfaceContainerLow: AppColors.canvas,
      surfaceContainer: AppColors.surfaceMuted,
      surfaceContainerHigh: Color(0xFFEBE4DA),
      surfaceContainerHighest: AppColors.border,
      onSurfaceVariant: AppColors.inkMuted,
      outline: AppColors.borderStrong,
      outlineVariant: AppColors.border,
      shadow: Colors.black12,
      scrim: Colors.black45,
      inverseSurface: AppColors.ink,
      onInverseSurface: AppColors.canvas,
      inversePrimary: AppColors.terracottaSoft,
    );

    final baseText = Typography.blackMountainView.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.canvas,
      textTheme: baseText.copyWith(
        headlineSmall: baseText.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleLarge: baseText.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        titleSmall: baseText.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodySmall: baseText.bodySmall?.copyWith(
          color: AppColors.inkMuted,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.terracotta, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.brick),
        ),
        labelStyle: const TextStyle(color: AppColors.inkMuted),
        prefixIconColor: AppColors.inkMuted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          backgroundColor: AppColors.surface,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          side: const BorderSide(color: AppColors.borderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          side: const BorderSide(color: AppColors.borderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.terracotta,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.terracottaSoft,
        side: const BorderSide(color: AppColors.borderStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        labelStyle: const TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w500,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.terracottaSoft,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.terracotta : AppColors.inkMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.terracotta : AppColors.inkMuted,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.terracottaSoft,
        selectedIconTheme: const IconThemeData(color: AppColors.terracotta),
        unselectedIconTheme: const IconThemeData(color: AppColors.inkMuted),
        selectedLabelTextStyle: const TextStyle(
          color: AppColors.terracotta,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: const TextStyle(
          color: AppColors.inkMuted,
          fontWeight: FontWeight.w500,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
