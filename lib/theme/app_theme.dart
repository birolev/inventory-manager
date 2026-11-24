import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Available visual color-scheme presets. Adding a new preset here automatically
/// makes it available in the Account theme picker and across every screen.
enum AppColorSchemePreset {
  atelier,
  studio,
  indigo;

  String get label => switch (this) {
    AppColorSchemePreset.atelier => 'Atelier',
    AppColorSchemePreset.studio => 'Studio',
    AppColorSchemePreset.indigo => 'Indigo',
  };

  String get subtitle => switch (this) {
    AppColorSchemePreset.atelier => 'Meleg butik',
    AppColorSchemePreset.studio => 'Minimalista',
    AppColorSchemePreset.indigo => 'Kontrasztos',
  };

  AppPalette paletteFor(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return switch (this) {
      AppColorSchemePreset.atelier =>
        isDark ? AppPalette.atelierDark : AppPalette.atelierLight,
      AppColorSchemePreset.studio =>
        isDark ? AppPalette.studioDark : AppPalette.studioLight,
      AppColorSchemePreset.indigo =>
        isDark ? AppPalette.indigoDark : AppPalette.indigoLight,
    };
  }
}

/// Semantic color palette carried via [ThemeExtension] so every screen adapts
/// automatically to both Light/Dark mode and future color-scheme presets.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.borderStrong,
    required this.ink,
    required this.inkMuted,
    required this.accent,
    required this.accentSoft,
    required this.olive,
    required this.oliveSoft,
    required this.brick,
    required this.brickSoft,
    required this.ochre,
    required this.ochreSoft,
    required this.primaryAction,
    required this.onPrimaryAction,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color borderStrong;
  final Color ink;
  final Color inkMuted;
  final Color accent;
  final Color accentSoft;
  final Color olive;
  final Color oliveSoft;
  final Color brick;
  final Color brickSoft;
  final Color ochre;
  final Color ochreSoft;
  final Color primaryAction;
  final Color onPrimaryAction;

  // Semantic aliases matching the original Boutique Atelier token names.
  Color get terracotta => accent;
  Color get terracottaSoft => accentSoft;

  static const atelierLight = AppPalette(
    canvas: Color(0xFFF7F4EF),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF1ECE4),
    border: Color(0xFFE7E0D6),
    borderStrong: Color(0xFFD6CCBE),
    ink: Color(0xFF231F20),
    inkMuted: Color(0xFF6B625B),
    accent: Color(0xFFB85D3B),
    accentSoft: Color(0xFFF5E6DF),
    olive: Color(0xFF3D6B4F),
    oliveSoft: Color(0xFFE6F0EA),
    brick: Color(0xFFB53838),
    brickSoft: Color(0xFFF8E5E5),
    ochre: Color(0xFFB7791F),
    ochreSoft: Color(0xFFF9EFE0),
    primaryAction: Color(0xFF231F20),
    onPrimaryAction: Colors.white,
  );

  static const atelierDark = AppPalette(
    canvas: Color(0xFF161413),
    surface: Color(0xFF211E1C),
    surfaceMuted: Color(0xFF2B2724),
    border: Color(0xFF38322E),
    borderStrong: Color(0xFF4B433E),
    ink: Color(0xFFF4EFEA),
    inkMuted: Color(0xFFB3A89E),
    accent: Color(0xFFE0825E),
    accentSoft: Color(0xFF3D271E),
    olive: Color(0xFF6BB385),
    oliveSoft: Color(0xFF1F3528),
    brick: Color(0xFFE57373),
    brickSoft: Color(0xFF3D2121),
    ochre: Color(0xFFE0A854),
    ochreSoft: Color(0xFF3A2E1B),
    primaryAction: Color(0xFFF4EFEA),
    onPrimaryAction: Color(0xFF161413),
  );

  static const studioLight = AppPalette(
    canvas: Color(0xFFF5F7FA),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEDF1F5),
    border: Color(0xFFE1E6EE),
    borderStrong: Color(0xFFCBD5E1),
    ink: Color(0xFF111827),
    inkMuted: Color(0xFF5B6475),
    accent: Color(0xFF0F766E),
    accentSoft: Color(0xFFE0F2F1),
    olive: Color(0xFF15803D),
    oliveSoft: Color(0xFFE3F5E9),
    brick: Color(0xFFDC2626),
    brickSoft: Color(0xFFFEE2E2),
    ochre: Color(0xFFB45309),
    ochreSoft: Color(0xFFFEF3C7),
    primaryAction: Color(0xFF111827),
    onPrimaryAction: Colors.white,
  );

  static const studioDark = AppPalette(
    canvas: Color(0xFF0F1419),
    surface: Color(0xFF182028),
    surfaceMuted: Color(0xFF222C36),
    border: Color(0xFF2E3A47),
    borderStrong: Color(0xFF425264),
    ink: Color(0xFFF1F5F9),
    inkMuted: Color(0xFF94A3B8),
    accent: Color(0xFF2DD4BF),
    accentSoft: Color(0xFF153835),
    olive: Color(0xFF4ADE80),
    oliveSoft: Color(0xFF163322),
    brick: Color(0xFFF87171),
    brickSoft: Color(0xFF3B1D1D),
    ochre: Color(0xFFFBBF24),
    ochreSoft: Color(0xFF382C14),
    primaryAction: Color(0xFFF1F5F9),
    onPrimaryAction: Color(0xFF0F1419),
  );

  static const indigoLight = AppPalette(
    canvas: Color(0xFFF4F5F9),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEAEDF6),
    border: Color(0xFFDEE3F0),
    borderStrong: Color(0xFFC5CEE3),
    ink: Color(0xFF1A2036),
    inkMuted: Color(0xFF5C647E),
    accent: Color(0xFF4355B9),
    accentSoft: Color(0xFFE6EAFD),
    olive: Color(0xFF2E7D5B),
    oliveSoft: Color(0xFFE3F3EC),
    brick: Color(0xFFC62828),
    brickSoft: Color(0xFFFCE4E4),
    ochre: Color(0xFFD97706),
    ochreSoft: Color(0xFFFEF3C7),
    primaryAction: Color(0xFF1A2036),
    onPrimaryAction: Colors.white,
  );

  static const indigoDark = AppPalette(
    canvas: Color(0xFF121521),
    surface: Color(0xFF1A1F30),
    surfaceMuted: Color(0xFF242B40),
    border: Color(0xFF313A54),
    borderStrong: Color(0xFF455070),
    ink: Color(0xFFEEF1FA),
    inkMuted: Color(0xFFA0A9C4),
    accent: Color(0xFF8C9EFF),
    accentSoft: Color(0xFF252D54),
    olive: Color(0xFF66BB94),
    oliveSoft: Color(0xFF1A362A),
    brick: Color(0xFFEF6C6C),
    brickSoft: Color(0xFF3E1F24),
    ochre: Color(0xFFF5B041),
    ochreSoft: Color(0xFF3B2D17),
    primaryAction: Color(0xFFEEF1FA),
    onPrimaryAction: Color(0xFF121521),
  );

  @override
  AppPalette copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceMuted,
    Color? border,
    Color? borderStrong,
    Color? ink,
    Color? inkMuted,
    Color? accent,
    Color? accentSoft,
    Color? olive,
    Color? oliveSoft,
    Color? brick,
    Color? brickSoft,
    Color? ochre,
    Color? ochreSoft,
    Color? primaryAction,
    Color? onPrimaryAction,
  }) {
    return AppPalette(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      olive: olive ?? this.olive,
      oliveSoft: oliveSoft ?? this.oliveSoft,
      brick: brick ?? this.brick,
      brickSoft: brickSoft ?? this.brickSoft,
      ochre: ochre ?? this.ochre,
      ochreSoft: ochreSoft ?? this.ochreSoft,
      primaryAction: primaryAction ?? this.primaryAction,
      onPrimaryAction: onPrimaryAction ?? this.onPrimaryAction,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      olive: Color.lerp(olive, other.olive, t)!,
      oliveSoft: Color.lerp(oliveSoft, other.oliveSoft, t)!,
      brick: Color.lerp(brick, other.brick, t)!,
      brickSoft: Color.lerp(brickSoft, other.brickSoft, t)!,
      ochre: Color.lerp(ochre, other.ochre, t)!,
      ochreSoft: Color.lerp(ochreSoft, other.ochreSoft, t)!,
      primaryAction: Color.lerp(primaryAction, other.primaryAction, t)!,
      onPrimaryAction: Color.lerp(onPrimaryAction, other.onPrimaryAction, t)!,
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.atelierLight;
}

/// Persisted theme controller managing Light/Dark/System mode and color scheme
/// presets across the entire app.
class AppThemeController extends ChangeNotifier {
  AppThemeController({
    ThemeMode initialMode = ThemeMode.light,
    AppColorSchemePreset initialPreset = AppColorSchemePreset.atelier,
  }) : _themeMode = initialMode,
       _preset = initialPreset;

  static final AppThemeController instance = AppThemeController();

  static const _modeKey = 'app_theme_mode';
  static const _presetKey = 'app_theme_preset';

  ThemeMode _themeMode;
  AppColorSchemePreset _preset;

  ThemeMode get themeMode => _themeMode;
  AppColorSchemePreset get preset => _preset;

  ThemeData get lightTheme =>
      AppTheme.build(preset: _preset, brightness: Brightness.light);
  ThemeData get darkTheme =>
      AppTheme.build(preset: _preset, brightness: Brightness.dark);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_modeKey);
      final savedPreset = prefs.getString(_presetKey);
      if (savedMode != null) {
        _themeMode = ThemeMode.values.firstWhere(
          (mode) => mode.name == savedMode,
          orElse: () => ThemeMode.light,
        );
      }
      if (savedPreset != null) {
        _preset = AppColorSchemePreset.values.firstWhere(
          (preset) => preset.name == savedPreset,
          orElse: () => AppColorSchemePreset.atelier,
        );
      }
      notifyListeners();
    } catch (_) {
      // Keep default light/atelier theme if preferences are unavailable.
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modeKey, mode.name);
    } catch (_) {}
  }

  Future<void> setPreset(AppColorSchemePreset preset) async {
    if (_preset == preset) return;
    _preset = preset;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_presetKey, preset.name);
    } catch (_) {}
  }
}

/// Static fallback tokens (Boutique Atelier light) preserved for compatibility.
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
  static String forint(dynamic value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0.0;
    return '${amount(number)} Ft';
  }

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

  static String salesStoreLabel(String? location) => switch (location) {
    'Csengery' => 'Yoáron',
    'Astoria' => 'BVS',
    _ => location ?? '-',
  };
}

/// Centralized Material 3 theme builder supporting Light/Dark and multiple
/// color-scheme presets.
abstract final class AppTheme {
  static ThemeData light({
    AppColorSchemePreset preset = AppColorSchemePreset.atelier,
  }) => build(preset: preset, brightness: Brightness.light);

  static ThemeData dark({
    AppColorSchemePreset preset = AppColorSchemePreset.atelier,
  }) => build(preset: preset, brightness: Brightness.dark);

  static ThemeData build({
    required AppColorSchemePreset preset,
    required Brightness brightness,
  }) {
    final p = preset.paletteFor(brightness);
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: p.primaryAction,
      onPrimary: p.onPrimaryAction,
      primaryContainer: p.accentSoft,
      onPrimaryContainer: p.ink,
      secondary: p.accent,
      onSecondary: isDark ? p.canvas : Colors.white,
      secondaryContainer: p.surfaceMuted,
      onSecondaryContainer: p.ink,
      tertiary: p.olive,
      onTertiary: isDark ? p.canvas : Colors.white,
      tertiaryContainer: p.oliveSoft,
      onTertiaryContainer: p.olive,
      error: p.brick,
      onError: isDark ? p.canvas : Colors.white,
      errorContainer: p.brickSoft,
      onErrorContainer: p.brick,
      surface: p.surface,
      onSurface: p.ink,
      surfaceContainerLowest: p.surface,
      surfaceContainerLow: p.canvas,
      surfaceContainer: p.surfaceMuted,
      surfaceContainerHigh: p.surfaceMuted,
      surfaceContainerHighest: p.border,
      onSurfaceVariant: p.inkMuted,
      outline: p.borderStrong,
      outlineVariant: p.border,
      shadow: Colors.black26,
      scrim: Colors.black54,
      inverseSurface: p.ink,
      onInverseSurface: p.canvas,
      inversePrimary: p.accentSoft,
    );

    final baseText =
        (isDark ? Typography.whiteMountainView : Typography.blackMountainView)
            .apply(bodyColor: p.ink, displayColor: p.ink);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      extensions: [p],
      scaffoldBackgroundColor: p.canvas,
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
        titleSmall: baseText.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        bodySmall: baseText.bodySmall?.copyWith(color: p.inkMuted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: p.ink,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        shape: Border(bottom: BorderSide(color: p.border)),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.accent, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.brick),
        ),
        labelStyle: TextStyle(color: p.inkMuted),
        prefixIconColor: p.inkMuted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primaryAction,
          foregroundColor: p.onPrimaryAction,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.ink,
          backgroundColor: p.surface,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          side: BorderSide(color: p.borderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.surface,
          foregroundColor: p.ink,
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          side: BorderSide(color: p.borderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accent,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.accentSoft,
        side: BorderSide(color: p.borderStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: TextStyle(color: p.ink, fontWeight: FontWeight.w500),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.accentSoft,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? p.accent : p.inkMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? p.accent : p.inkMuted);
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.accentSoft,
        selectedIconTheme: IconThemeData(color: p.accent),
        unselectedIconTheme: IconThemeData(color: p.inkMuted),
        selectedLabelTextStyle: TextStyle(
          color: p.accent,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: p.inkMuted,
          fontWeight: FontWeight.w500,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
