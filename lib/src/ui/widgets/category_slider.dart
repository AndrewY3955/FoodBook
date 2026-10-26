import 'package:flutter/material.dart';

class CategoryOption<T> {
  const CategoryOption({
    required this.value,
    required this.label,
    required this.emoji,
  });

  final T value;
  final String label;
  final String emoji;
}

/// A horizontally scrolling row of round category tiles. Tapping the
/// selected tile clears the selection.
class CategorySlider<T> extends StatelessWidget {
  const CategorySlider({
    required this.options,
    required this.selected,
    required this.onChanged,
    this.semanticsLabel,
    super.key,
  });

  final List<CategoryOption<T>> options;
  final T? selected;
  final ValueChanged<T?> onChanged;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      label: semanticsLabel,
      child: SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: options.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (BuildContext context, int i) {
            final CategoryOption<T> option = options[i];
            final bool isSelected = option.value == selected;

            return Semantics(
              button: true,
              selected: isSelected,
              label: option.label,
              excludeSemantics: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onChanged(isSelected ? null : option.value),
                child: SizedBox(
                  width: 72,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerHighest,
                          border: Border.all(
                            color: isSelected
                                ? scheme.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Text(
                          option.emoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelSmall?.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
