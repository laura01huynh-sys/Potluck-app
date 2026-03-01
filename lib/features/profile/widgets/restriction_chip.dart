import 'package:flutter/material.dart';

/// Chip for displaying a dietary restriction (allergy, avoid, lifestyle, custom).
/// [type] is one of: 'allergy', 'avoid', 'lifestyle', 'custom'.
class RestrictionChip extends StatelessWidget {
  final String label;
  final String type;
  final VoidCallback onDeleted;

  const RestrictionChip({
    super.key,
    required this.label,
    required this.type,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;
    String icon;
    bool showIcon = true;
    switch (type) {
      case 'allergy':
        backgroundColor = const Color(0xFFFFE5E5);
        textColor = const Color(0xFFDC2626);
        icon = '⚠️';
        break;
      case 'custom':
        backgroundColor = Colors.green.shade100;
        textColor = Colors.green.shade900;
        icon = '✨';
        break;
      case 'lifestyle':
        backgroundColor = Colors.blue.shade50;
        textColor = Colors.blue.shade700;
        icon = '';
        showIcon = false;
        break;
      default:
        backgroundColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFFB45309);
        icon = '🚫';
    }

    String displayLabel = label;
    if (type == 'lifestyle' && label.isNotEmpty) {
      displayLabel = label
          .replaceAll('-', ' ')
          .split(' ')
          .map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : w)
          .join(' ');
    }

    return Chip(
      label: Text(
        showIcon ? '$icon $displayLabel' : displayLabel,
        style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
      ),
      backgroundColor: backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onDeleted: onDeleted,
    );
  }
}
