class RecipeFilter {
  final bool showOnlyReadyToCook;
  final Set<String> avoidedIngredients;
  final Set<String> allergyIngredients;

  RecipeFilter({
    this.showOnlyReadyToCook = false,
    Set<String>? avoidedIngredients,
    Set<String>? allergyIngredients,
  })  : avoidedIngredients = avoidedIngredients ?? {},
        allergyIngredients = allergyIngredients ?? {};

  RecipeFilter copyWith({
    bool? showOnlyReadyToCook,
    Set<String>? avoidedIngredients,
    Set<String>? allergyIngredients,
  }) => RecipeFilter(
    showOnlyReadyToCook: showOnlyReadyToCook ?? this.showOnlyReadyToCook,
    avoidedIngredients: avoidedIngredients ?? this.avoidedIngredients,
    allergyIngredients: allergyIngredients ?? this.allergyIngredients,
  );

  bool get hasActiveFilters =>
      showOnlyReadyToCook ||
      avoidedIngredients.isNotEmpty ||
      allergyIngredients.isNotEmpty;

  List<String> getActiveFilterLabels() => [
    if (showOnlyReadyToCook) 'Potluck',
    if (avoidedIngredients.isNotEmpty) '${avoidedIngredients.length} Avoided',
    if (allergyIngredients.isNotEmpty) '${allergyIngredients.length} Allergies',
  ];
}