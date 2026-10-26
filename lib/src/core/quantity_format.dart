import '../data/models/enums.dart';

/// Renders a quantity the way a person writes it on a recipe card.
///
/// 0.5 -> "1/2", 1.25 -> "1 1/4", 2.0 -> "2", 0.333 -> "1/3".
/// Anything that is not close to a common library fraction falls back
/// to at most two decimals, trailing zeros removed.
class QuantityFormat {
  const QuantityFormat._();

  /// Denominators a cook actually measures in. Fifths and sevenths are
  /// deliberately absent: "3/7 cup" is not help.
  static const List<int> _denominators = <int>[2, 3, 4, 8];

  static const double _tolerance = 0.012;

  static String amount(double value) {
    if (value <= 0) return '0';
    if (!value.isFinite) return '0';

    final int whole = value.floor();
    final double remainder = value - whole;

    if (remainder < _tolerance) return '$whole';

    for (final int denominator in _denominators) {
      for (int numerator = 1; numerator < denominator; numerator++) {
        if ((remainder - numerator / denominator).abs() < _tolerance) {
          final String fraction = '$numerator/$denominator';
          return whole == 0 ? fraction : '$whole $fraction';
        }
      }
    }

    final String plain = value.toStringAsFixed(2);
    return plain.endsWith('.00')
        ? plain.substring(0, plain.length - 3)
        : (plain.endsWith('0') ? plain.substring(0, plain.length - 1) : plain);
  }

  /// Full label: "2 1/2 cups", "3 cloves", "4" for bare counts.
  static String withUnit(double value, MeasureUnit unit) {
    if (unit == MeasureUnit.toTaste) return 'to taste';

    final String number = amount(value);
    if (unit.label.isEmpty) return number;

    final bool plural = unit.pluralises && (value - 1).abs() > 0.001;
    return '$number ${unit.label}${plural ? 's' : ''}';
  }

  /// "4 servings" / "1 serving".
  static String servings(int count) =>
      count == 1 ? '1 serving' : '$count servings';

  /// "1 h 25 min", "45 min".
  static String minutes(int? total) {
    if (total == null || total <= 0) return '';
    if (total < 60) return '$total min';
    final int hours = total ~/ 60;
    final int rest = total % 60;
    return rest == 0 ? '$hours h' : '$hours h $rest min';
  }
}
