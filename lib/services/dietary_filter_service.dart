import '../core/dietary.dart';
import '../models/recipe.dart';
import '../features/profile/models/user_profile.dart';

class FilterService {
  /// THE SMART FILTER
  /// Returns TRUE if an ingredient is safe, FALSE if it contains a blocked keyword.
  static bool isIngredientSafe(
    String ingredient,
    List<String> blockedKeywords,
  ) {
    final lowerIng = ingredient.toLowerCase();

    for (final keyword in blockedKeywords) {
      final lowerKeyword = keyword.toLowerCase();

      // If the ingredient mentions a blocked item (e.g., "Milk")
      if (lowerIng.contains(lowerKeyword)) {
        // CHECK FOR SAFETY NEGATORS:
        // Does it say "Dairy-free Milk" or "Vegan Cheese"?
        final hasSafetyWord = RecipeDataConstants.safetyNegators.any(
          (safety) =>
              lowerIng.contains('$safety $lowerKeyword') ||
              lowerIng.contains('$lowerKeyword-$safety') ||
              lowerIng.startsWith(safety),
        );

        // If it found the bad word but NO safety context, it's unsafe.
        if (!hasSafetyWord) return false;
      }
    }

    return true; // No violations found
  }

  /// THE FILTERING LOOP
  /// Takes a list of recipes and returns only those that match the user's lifestyles.
  static List<Recipe> filterByLifestyle(
    List<Recipe> recipes,
    List<String> activeLifestyles,
  ) {
    if (activeLifestyles.isEmpty) return recipes;

    // 1. Gather all blocked keywords for all selected lifestyles
    final allBlocked = activeLifestyles
        .expand(
          (l) =>
              RecipeDataConstants.lifestyleRules[l.toLowerCase()] ??
              const <String>[],
        )
        .map((e) => e.toString())
        .toList();

    // 2. Filter the recipe list
    return recipes.where((recipe) {
      // The recipe is safe only if EVERY SINGLE ingredient is safe
      return recipe.ingredients
          .every((ing) => isIngredientSafe(ing, allBlocked));
    }).toList();
  }
}

/// Dietary/allergy/lifestyle filtering and helpers (no substitution logic).
class RecipeFilterService {
  /// Tier 1: Check if recipe should be excluded due to allergies
  static bool hasAllergyConflict(Recipe recipe, Set<String> allergies) {
    if (allergies.isEmpty) return false;
    for (var ingredient in recipe.ingredients) {
      if (allergies.contains(ingredient)) {
        return true;
      }
    }
    return false;
  }

  /// Tier 2: Check if recipe violates lifestyle restrictions
  static bool violatesLifestyle(Recipe recipe, Set<String> lifestyles) {
    if (lifestyles.isEmpty) return false;

    for (var lifestyle in lifestyles) {
      final excludedTags =
          RecipeDataConstants.lifestyleRules[lifestyle] ?? [];

      // Special case for Kosher: exclude dairy+meat combination
      if (lifestyle == 'kosher') {
        final hasDairy = recipe.ingredientTags.values.any(
          (tags) => tags.contains('Dairy'),
        );
        final hasMeat = recipe.ingredientTags.values.any(
          (tags) => tags.contains('Meat'),
        );
        if (hasDairy && hasMeat) return true;

        // Also exclude pork and shellfish
        if (recipe.ingredientTags['Pork'] != null ||
            recipe.ingredientTags['Shellfish'] != null) {
          return true;
        }
      }

      // Check for excluded tags
      for (var tags in recipe.ingredientTags.values) {
        for (var tag in tags) {
          if (excludedTags.contains(tag)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Apply filters to recipes
  static List<Recipe> filterRecipes(
      List<Recipe> recipes, UserProfile profile) {
    return recipes.where((recipe) {
      if (hasAllergyConflict(recipe, profile.allergies)) {
        return false;
      }
      if (violatesLifestyle(recipe, profile.selectedLifestyles)) {
        return false;
      }
      if (violatesCustomLifestyle(
        recipe,
        profile.customLifestyles,
        profile.activeCustomLifestyles,
      )) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Sort recipes for high-protein lifestyle (moves to top)
  static List<Recipe> sortByProtein(
      List<Recipe> recipes, bool isHighProtein) {
    if (!isHighProtein) return recipes;
    return recipes..sort((a, b) => b.proteinGrams.compareTo(a.proteinGrams));
  }

  /// Get all allergy risk ingredients
  static List<String> getAllergyRiskIngredients() {
    return RecipeDataConstants
            .defaultIngredientClassification['allergy_risk'] ??
        [];
  }

  /// Get all common avoidance ingredients
  static List<String> getCommonAvoidanceIngredients() {
    return RecipeDataConstants
            .defaultIngredientClassification['common_avoidance'] ??
        [];
  }

  /// Quick add all allergy risk ingredients to allergies
  static Set<String> addAllAllergyRisks(Set<String> currentAllergies) {
    return {...currentAllergies, ...getAllergyRiskIngredients()};
  }

  /// Quick add all common avoidance ingredients to avoided
  static Set<String> addAllCommonAvoidance(Set<String> currentAvoided) {
    return {...currentAvoided, ...getCommonAvoidanceIngredients()};
  }

  /// Check if a recipe contains an ingredient the user is intolerant to
  /// (keyword-based: e.g. "Dairy" -> milk, cheese, butter...). Uses
  /// [FilterService.isIngredientSafe] for safety negators (e.g. dairy-free).
  static bool recipeContainsIntolerance(
    List<String> ingredients,
    String intolerance,
  ) {
    final keywords = _intoleranceKeywords[intolerance.toLowerCase()] ?? [];
    if (keywords.isEmpty) return false;
    for (final ing in ingredients) {
      if (!FilterService.isIngredientSafe(ing, keywords)) return true;
    }
    return false;
  }

  static const Map<String, List<String>> _intoleranceKeywords = {
    'dairy': [
      'milk', 'cream', 'cheese', 'butter', 'yogurt', 'whey', 'casein', 'ghee',
      'sour cream', 'cream cheese', 'cottage cheese', 'ricotta', 'mozzarella',
      'parmesan', 'cheddar', 'brie', 'feta', 'gouda', 'swiss', 'provolone',
      'ice cream',
    ],
    'egg': ['egg', 'eggs', 'mayonnaise', 'meringue', 'custard'],
    'gluten': [
      'wheat', 'flour', 'bread', 'pasta', 'noodle', 'spaghetti', 'fettuccine',
      'penne', 'macaroni', 'barley', 'rye', 'couscous', 'bulgur', 'semolina',
      'seitan', 'beer', 'breadcrumb', 'crouton',
    ],
    'peanut': ['peanut', 'peanuts', 'peanut butter'],
    'seafood': [
      'fish', 'salmon', 'tuna', 'cod', 'tilapia', 'halibut', 'trout',
      'sardine', 'anchovy', 'mackerel',
    ],
    'shellfish': [
      'shrimp', 'prawn', 'crab', 'lobster', 'clam', 'mussel', 'oyster',
      'scallop', 'squid', 'octopus', 'calamari',
    ],
    'soy': ['soy', 'soya', 'tofu', 'tempeh', 'edamame', 'miso'],
    'tree nut': [
      'almond', 'walnut', 'cashew', 'pistachio', 'pecan', 'hazelnut',
      'macadamia', 'brazil nut', 'chestnut', 'pine nut',
    ],
    'wheat': [
      'wheat', 'flour', 'bread', 'pasta', 'noodle', 'couscous', 'bulgur',
      'semolina', 'farina',
    ],
    'sesame': ['sesame', 'tahini'],
    'sulfite': ['wine', 'dried fruit', 'molasses'],
  };

  /// Check if recipe violates any active custom lifestyles
  static bool violatesCustomLifestyle(
    Recipe recipe,
    List<CustomLifestyle> customLifestyles,
    Set<String> activeCustomLifestyleIds,
  ) {
    if (customLifestyles.isEmpty || activeCustomLifestyleIds.isEmpty) {
      return false;
    }

    for (var lifestyle in customLifestyles) {
      if (activeCustomLifestyleIds.contains(lifestyle.id)) {
        for (var ingredient in recipe.ingredients) {
          if (lifestyle.blockList.contains(ingredient)) {
            return true;
          }
        }
      }
    }
    return false;
  }
}

