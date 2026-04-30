import 'package:flutter/material.dart';

class SectionHeader extends StatelessWidget {
  final String label;
  const SectionHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class SegmentedRow<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final void Function(T) onSelected;

  const SegmentedRow({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values.map((v) {
        final isSelected = v == selected;
        return FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: isSelected
                ? colorScheme.primary
                : colorScheme.surfaceContainerHighest,
            foregroundColor: isSelected
                ? colorScheme.onPrimary
                : colorScheme.onSurface,
          ),
          onPressed: () => onSelected(v),
          child: Text(label(v)),
        );
      }).toList(),
    );
  }
}
