import 'package:flutter/widgets.dart';

/// Which shape the UI is in.
enum FormFactor { phone, tablet, desktop }

/// Layout thresholds.
///
/// The numbers are width in logical pixels and are chosen to match real
/// devices rather than round numbers: 600 is where a phone in landscape
/// and a small tablet in portrait sit, 1024 is where a tablet in
/// landscape and a narrow desktop window sit.
///
/// Everything keys off the width of the box the layout is given, not
/// MediaQuery.of(context).size. On desktop the app can be in a 500 px
/// window on a 4K display, and on tablet it can be one half of a split
/// screen. Measuring the window instead of the box is the single most
/// common way responsive Flutter code goes wrong.
class Breakpoints {
  const Breakpoints._();

  static const double tablet = 600;
  static const double desktop = 1024;

  /// Beyond this, content is centred rather than stretched. A recipe
  /// step set 2000 px wide is unreadable.
  static const double maxContentWidth = 1400;

  static FormFactor of(double width) {
    if (width >= desktop) return FormFactor.desktop;
    if (width >= tablet) return FormFactor.tablet;
    return FormFactor.phone;
  }

  /// Columns for the recipe grid at a given width.
  static int recipeColumns(double width) {
    if (width >= 1600) return 5;
    if (width >= 1280) return 4;
    if (width >= 900) return 3;
    if (width >= 560) return 2;
    return 1;
  }

  /// Cooking Mode uses a split pane only when there is genuinely room
  /// for two readable columns side by side.
  static bool splitCookingPane(double width) => width >= 840;
}

/// Inherited form factor, so a deep widget can adapt without every
/// intermediate widget threading a parameter down.
class LayoutScope extends InheritedWidget {
  const LayoutScope({
    required this.formFactor,
    required this.width,
    required super.child,
    super.key,
  });

  final FormFactor formFactor;
  final double width;

  bool get isPhone => formFactor == FormFactor.phone;
  bool get isTablet => formFactor == FormFactor.tablet;
  bool get isDesktop => formFactor == FormFactor.desktop;

  static LayoutScope of(BuildContext context) {
    final LayoutScope? scope =
        context.dependOnInheritedWidgetOfExactType<LayoutScope>();
    assert(scope != null, 'LayoutScope is missing above this widget.');
    return scope!;
  }

  /// Non-asserting lookup for widgets that may be used outside a scope
  /// (dialogs pushed on the root navigator, for instance).
  static LayoutScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LayoutScope>();

  @override
  bool updateShouldNotify(LayoutScope oldWidget) =>
      oldWidget.formFactor != formFactor || oldWidget.width != width;
}

/// Wraps a subtree in a LayoutScope derived from its own constraints.
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, LayoutScope scope) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        final FormFactor factor = Breakpoints.of(width);

        return LayoutScope(
          formFactor: factor,
          width: width,
          child: Builder(
            builder: (BuildContext inner) =>
                builder(inner, LayoutScope.of(inner)),
          ),
        );
      },
    );
  }
}
