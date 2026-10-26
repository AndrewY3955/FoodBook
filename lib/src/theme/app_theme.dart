import 'package:flutter/material.dart';

/// Material 3, one seed colour, light and dark.
///
/// The only deliberate departure from the defaults is touch target
/// size in Cooking Mode: see [cookingButtonStyle]. Standard targets are
/// 48 px, which is fine for a thumb and useless for a knuckle.
class AppTheme {
  const AppTheme._();

  static const Color _seed = Color(0xFF7A5C3E);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 10,
      ),
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
