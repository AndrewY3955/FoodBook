import 'package:flutter/material.dart';

/// Material 3, one seed colour, light and dark.
///
/// The only deliberate departure from the defaults is touch target
/// size in Cooking Mode: see [cookingButtonStyle]. Standard targets are
/// 48 px, which is fine for a thumb and useless for a knuckle.
class AppTheme {
  const AppTheme._();

  // Contrast, computed against the surfaces below (WCAG 2.x):
  // white on _primary 5.54, white on _sage 5.66, _accentText on paper
  // 5.87, _successText on paper 6.57, _ink on paper 14.76.
  static const Color _paper = Color(0xFFFBF7F2);
  static const Color _ink = Color(0xFF2B2118);
  static const Color _primary = Color(0xFFB5431F);
  static const Color _accentText = Color(0xFFA63F1F);
  static const Color _sage = Color(0xFF4F6F4B);
  static const Color _successText = Color(0xFF3F6140);

  static const Color _night = Color(0xFF1C1917);
  static const Color _nightInk = Color(0xFFEDE6DD);
  static const Color _nightAccent = Color(0xFFF2A58A);

  /// Success text colour that passes AA on the current surface.
  static Color successText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF9FC79A)
          : _successText;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool dark = brightness == Brightness.dark;
    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: _primary,
      brightness: brightness,
    );
    final ColorScheme scheme = dark
        ? base.copyWith(
            surface: _night,
            onSurface: _nightInk,
            primary: _nightAccent,
            onPrimary: const Color(0xFF3A1407),
            primaryContainer: const Color(0xFF5A2410),
            onPrimaryContainer: const Color(0xFFFFDBCF),
            secondary: const Color(0xFF9FC79A),
            surfaceContainerLowest: const Color(0xFF151311),
            surfaceContainerLow: const Color(0xFF211E1B),
            surfaceContainer: const Color(0xFF262321),
            surfaceContainerHigh: const Color(0xFF2E2A27),
            outlineVariant: const Color(0xFF4A433D),
          )
        : base.copyWith(
            surface: _paper,
            onSurface: _ink,
            primary: _primary,
            onPrimary: Colors.white,
            primaryContainer: const Color(0xFFFBE0D6),
            onPrimaryContainer: const Color(0xFF5A1F0C),
            secondary: _sage,
            onSecondary: Colors.white,
            tertiary: _accentText,
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: const Color(0xFFF6F0E8),
            surfaceContainer: const Color(0xFFF1EADF),
            surfaceContainerHigh: const Color(0xFFEBE3D7),
            outlineVariant: const Color(0xFFDCD2C4),
          );

    final ThemeData seeded = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'Inter',
    );
    final TextTheme t = seeded.textTheme;
    TextStyle serif(TextStyle? s, {double? size}) =>
        (s ?? const TextStyle()).copyWith(
          fontFamily: 'Fraunces',
          fontWeight: FontWeight.w600,
          fontSize: size,
          height: 1.2,
        );
    // Body 16 px; metadata (bodySmall/labelSmall) never below 14 px.
    final TextTheme textTheme = t.copyWith(
      displaySmall: serif(t.displaySmall),
      headlineLarge: serif(t.headlineLarge),
      headlineMedium: serif(t.headlineMedium),
      headlineSmall: serif(t.headlineSmall),
      titleLarge: serif(t.titleLarge, size: 24),
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 17, height: 1.5),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 16, height: 1.5),
      bodySmall: t.bodySmall?.copyWith(fontSize: 14, height: 1.4),
      labelMedium: t.labelMedium?.copyWith(fontSize: 14),
      labelSmall: t.labelSmall?.copyWith(fontSize: 14),
    );

    return seeded.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: dark ? _nightAccent : _accentText,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        extendedTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 3),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: textTheme.labelMedium,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll<TextStyle>(
          TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
        labelType: NavigationRailLabelType.all,
        selectedLabelTextStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontSize: 14,
          color: scheme.onSurface,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 10,
      ),
      focusColor: scheme.primary.withValues(alpha: 0.2),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  /// Cooking Mode targets. 96 px minimum height, because the hand that
  /// presses this is holding a knife, is wet, or is a forearm.
  static ButtonStyle cookingButtonStyle(ColorScheme scheme) =>
      FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(96),
        textStyle: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      );

  /// Step text in Cooking Mode is read from arm's length across a
  /// worktop, not from 30 cm away.
  static TextStyle cookingStepStyle(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall!.copyWith(
            height: 1.45,
            fontWeight: FontWeight.w400,
          );
}
