import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../models/recipe.dart';

/// Horizontal bar showing Calories, Protein, Carbs, and Fat.
class NutritionSummaryBar extends StatelessWidget {
  final Nutrition nutrition;
  final double servingMultiplier;

  const NutritionSummaryBar({
    super.key, 
    required this.nutrition, 
    this.servingMultiplier = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    // Scaling logic moved into a helper to keep build method clean
    String scale(double value, {int decimals = 0}) => 
        (value * servingMultiplier).toStringAsFixed(decimals);

    return Row(
      children: [
        _buildTile('Calories', '${scale(nutrition.calories.toDouble())} kcal'),
        _divider(),
        _buildTile('Protein', '${scale(nutrition.protein)} g'),
        _divider(),
        _buildTile('Carbs', '${scale(nutrition.carbs)} g'),
        _divider(),
        _buildTile('Fat', '${scale(nutrition.fat)} g'),
      ],
    );
  }

  Widget _buildTile(String label, String value) {
    final parts = value.split(' ');
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: kDeepForestGreen),
              children: [
                TextSpan(text: parts[0]),
                if (parts.length > 1) TextSpan(text: ' ${parts[1]}', style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 24, color: kCharcoal.withOpacity(0.1));
}

/// Left-aligned "Pills" for additional facts like Fiber and Sodium.
class CompactNutritionDetails extends StatelessWidget {
  final Nutrition nutrition;
  const CompactNutritionDetails({super.key, required this.nutrition});

  @override
  Widget build(BuildContext context) {
    // Map of labels to values, only including if they aren't null
    final extras = {
      if (nutrition.fiber != null) 'Fiber': '${nutrition.fiber!.toStringAsFixed(1)}g',
      if (nutrition.sugar != null) 'Sugar': '${nutrition.sugar!.toStringAsFixed(1)}g',
      if (nutrition.sodium != null) 'Sodium': '${nutrition.sodium!.toStringAsFixed(0)}mg',
    };

    if (extras.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: extras.entries.map((e) => Chip(
        label: Text('${e.key} ${e.value}', 
          style: const TextStyle(fontSize: 11, color: kDeepForestGreen, fontWeight: FontWeight.bold)),
        backgroundColor: kSageGreen.withOpacity(0.1),
        side: BorderSide(color: kSageGreen.withOpacity(0.2)),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      )).toList(),
    );
  }
}