import '../core/quantity_format.dart';
import '../data/models/enums.dart';
import '../data/models/models.dart';

/// Pure serving-size arithmetic. No Riverpod, no Flutter — so it can be
/// unit tested directly, and so the scaling rules live in one place
/// rather than being re-derived in each widget that shows a quantity.
class PortionScaler {
  const PortionScaler._();

  /// Serving counts the stepper will stop at. Bounded because the
  /// database CHECK on base_servings is 1..100 and the UI must not let
  /// the user build a request the server will reject.
  static const int minServings = 1;
  static const int maxServings = 100;

  static int clampServings(int value) => value < minServings
      ? minServings
      : (value > maxServings ? maxServings : value);

  static double factor(
      {required int baseServings, required int targetServings}) {
    if (baseServings <= 0) return 1;
    return clampServings(targetServings) / baseServings;
  }

  /// Scales one line. Units that do not scale — "to taste" — pass
  /// through untouched, which is why this is not a plain multiply at
  /// the call site.
  static RecipeIngredient scaleLine(RecipeIngredient line, double factor) {
    if (!line.unit.isScalable) return line;
    if ((factor - 1).abs() < 0.0001) return line;

    final double scaled = line.quantity * factor;
    // Three decimals matches numeric(10,3) in the schema. Rounding here
    // keeps the on-screen value and the value sent to the shopping list
    // aggregator identical.
    return line.copyWith(quantity: double.parse(scaled.toStringAsFixed(3)));
  }

  static List<RecipeIngredient> scaleAll(
    List<RecipeIngredient> lines,
    double factor,
  ) =>
      lines
          .map((RecipeIngredient l) => scaleLine(l, factor))
          .toList(growable: false);

  /// Convenience for the detail screen.
  static List<RecipeIngredient> forServings({
    required List<RecipeIngredient> lines,
    required int baseServings,
    required int targetServings,
  }) =>
      scaleAll(
        lines,
        factor(baseServings: baseServings, targetServings: targetServings),
      );

  /// "2 1/2 cups flour" for a scaled line, ready to render.
  static String describe(RecipeIngredient line) {
    final String quantity = QuantityFormat.withUnit(line.quantity, line.unit);
    if (line.unit == MeasureUnit.toTaste) return '${line.name}, to taste';
    return quantity.isEmpty ? line.name : '$quantity ${line.name}';
  }
}
