import 'package:flutter/material.dart';

import '../../data/models/enums.dart';

/// Wrapping multi-select chips for dietary labels. Used by the filter
/// bars and by the recipe form.
class DietChips extends StatelessWidget {
  const DietChips({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  final List<Diet> selected;
  final ValueChanged<Diet> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: <Widget>[
        for (final Diet d in Diet.values)
          FilterChip(
            label: Text(d.label),
            selected: selected.contains(d),
            onSelected: (_) => onToggle(d),
          ),
      ],
    );
  }
}
