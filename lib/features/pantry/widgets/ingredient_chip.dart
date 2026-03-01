import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../models/ingredient.dart';

/// Reusable pantry ingredient chip that handles selection and delete UI.
class IngredientChip extends StatelessWidget {
  final Ingredient ingredient;
  final bool isSelected;
  final bool selectionEnabled;
  final VoidCallback? onToggleSelected;
  final VoidCallback onDelete;

  const IngredientChip({
    super.key,
    required this.ingredient,
    required this.isSelected,
    required this.selectionEnabled,
    required this.onToggleSelected,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: selectionEnabled ? onToggleSelected : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? kDeepForestGreen.withOpacity(0.15)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? kDeepForestGreen : Colors.grey.shade300,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check_circle, size: 16, color: kDeepForestGreen),
              const SizedBox(width: 6),
            ],
            Text(
              ingredient.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? kDeepForestGreen : kCharcoal,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDelete,
              child: Icon(
                Icons.close,
                size: 16,
                color: isSelected ? kDeepForestGreen : kCharcoal,
              ),
            ),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }
}

