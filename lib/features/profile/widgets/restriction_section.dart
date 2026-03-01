import 'package:flutter/material.dart';

import 'summary_chip.dart';

/// Section displaying a group of dietary restrictions with a title.
class RestrictionSection extends StatelessWidget {
  final String title;
  final List<String> items;
  final String variant;

  const RestrictionSection({
    super.key,
    required this.title,
    required this.items,
    required this.variant,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map((item) => SummaryChip(label: item, variant: variant))
              .toList(),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
