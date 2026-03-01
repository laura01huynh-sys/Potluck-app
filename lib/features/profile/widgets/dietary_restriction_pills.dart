import 'package:flutter/material.dart';

/// Builds a restriction section (Allergies or Avoid) with filterable ingredient pills.
Widget buildRestrictionSection(
  String title,
  String emoji,
  Color color,
  Set<String> restrictedItems,
  void Function(String) onToggle,
  List<String> ingredients,
  String searchQuery,
) {
  final filteredIngredients = ingredients
      .where(
        (ing) =>
            searchQuery.isEmpty ||
            ing.toLowerCase().contains(searchQuery.toLowerCase()),
      )
      .toList();

  if (filteredIngredients.isEmpty && searchQuery.isNotEmpty) {
    return const SizedBox.shrink();
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            '${restrictedItems.length}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: filteredIngredients.map((ingredient) {
          final isRestricted = restrictedItems.contains(ingredient);
          return GestureDetector(
            onTap: () => onToggle(ingredient),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: isRestricted ? color : Colors.grey.shade100,
                border: Border.all(
                  color: isRestricted ? color : Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isRestricted) ...[
                    Text(emoji, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    ingredient,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isRestricted
                          ? Colors.black87
                          : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    ],
  );
}
