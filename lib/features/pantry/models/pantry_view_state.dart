import '../../../models/ingredient.dart';

/// Precomputed view state for the pantry screen: filtered ingredients,
/// grouped categories, and counts used to build the UI.
class PantryViewState {
  final List<Ingredient> activeIngredients;
  final List<Ingredient> allActiveIngredients;
  final Map<IngredientCategory, List<Ingredient>> groupedByCategory;
  final Map<IngredientCategory, int> categoryCounts;
  final List<IngredientCategory> categoriesWithItems;

  const PantryViewState({
    required this.activeIngredients,
    required this.allActiveIngredients,
    required this.groupedByCategory,
    required this.categoryCounts,
    required this.categoriesWithItems,
  });

  factory PantryViewState.from({
    required List<Ingredient> sharedIngredients,
    required String searchQuery,
    required IngredientCategory? selectedCategory,
  }) {
    // All ingredients that are currently in stock.
    final allActive = sharedIngredients
        .where((ing) => !ing.needsPurchase)
        .toList();

    // Start from all active, then apply filters.
    var active = List<Ingredient>.from(allActive);

    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      active = active
          .where((ing) => ing.name.toLowerCase().contains(q))
          .toList();
    }

    if (selectedCategory != null) {
      active = active
          .where((ing) => ing.category == selectedCategory)
          .toList();
    }

    // Group filtered ingredients by category.
    final grouped = <IngredientCategory, List<Ingredient>>{};
    for (final ingredient in active) {
      grouped
          .putIfAbsent(ingredient.category, () => <Ingredient>[])
          .add(ingredient);
    }

    // Category counts from all active (unfiltered) ingredients.
    final counts = <IngredientCategory, int>{};
    for (final ingredient in allActive) {
      counts.update(
        ingredient.category,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }

    // Categories that currently have at least one active ingredient.
    final catsWithItems = IngredientCategory.displayOrder
        .where((cat) => (counts[cat] ?? 0) > 0)
        .toList();

    return PantryViewState(
      activeIngredients: active,
      allActiveIngredients: allActive,
      groupedByCategory: grouped,
      categoryCounts: counts,
      categoriesWithItems: catsWithItems,
    );
  }
}

