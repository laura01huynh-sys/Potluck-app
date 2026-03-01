import 'package:flutter/material.dart';

import '../utils/string_extensions.dart';

/// Chip for displaying a dietary restriction in the Palate Summary.
/// [variant] is one of: 'allergy', 'avoided', 'lifestyle'.
class SummaryChip extends StatelessWidget {
  final String label;
  final String variant;

  const SummaryChip({
    super.key,
    required this.label,
    required this.variant,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color borderColor;
    Color textColor;
    switch (variant) {
      case 'allergy':
        backgroundColor = Colors.red.shade50;
        borderColor = Colors.red.shade200;
        textColor = Colors.red.shade700;
        break;
      case 'avoided':
        backgroundColor = Colors.orange.shade50;
        borderColor = Colors.orange.shade200;
        textColor = Colors.orange.shade700;
        break;
      case 'lifestyle':
        backgroundColor = Colors.blue.shade50;
        borderColor = Colors.blue.shade200;
        textColor = Colors.blue.shade700;
        break;
      default:
        backgroundColor = Colors.grey.shade100;
        borderColor = Colors.grey.shade300;
        textColor = Colors.grey.shade700;
    }

    final displayLabel = variant == 'lifestyle' ? label.toTitleCase() : label;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        displayLabel,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),
    );
  }
}
