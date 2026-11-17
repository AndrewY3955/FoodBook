import '../data/models/enums.dart';
import 'security/input_sanitizer.dart';

/// Interprets an amount embedded in a legacy ingredient name when the
/// separately stored unit is a bare count.
class IngredientAmount {
  const IngredientAmount({required this.quantity, required this.name});

  final double quantity;
  final String name;

  static final RegExp _leading = RegExp(
    r'^(\d+\s+\d+\s*/\s*\d+|\d+\s*/\s*\d+|\d+(?:[.,]\d+)?)(?:\s+|(?=(?:kg|g|ml|l|oz|lb|lbs)\b))(.+)$',
    caseSensitive: false,
  );

  static IngredientAmount? fromName(
    String name,
    double quantity,
    MeasureUnit unit,
  ) {
    if (unit != MeasureUnit.unit) return null;
    final RegExpMatch? match = _leading.firstMatch(name.trim());
    if (match == null) return null;
    final double? embedded = InputSanitizer.quantity(match.group(1)!);
    final String remainder = match.group(2)!.trim();
    if (embedded == null || remainder.isEmpty) return null;
    return IngredientAmount(quantity: embedded * quantity, name: remainder);
  }
}
