import '../models/ingredient.dart';

/// Fuzzy ingredient matching: aliases, basic staples, and match helpers.
/// Used for pantry-to-recipe matching and international/pantry-friendly names.
class IngredientMatchService {
  /// Maps base ingredient names to common variations found in recipe text.
  static const Map<String, List<String>> ingredientAliases = {
    // ─── Existing families ─────────────────────────────────────────────────
    'chicken': [
      'chicken breast',
      'chicken thigh',
      'chicken leg',
      'raw chicken',
      'cooked chicken',
      'grilled chicken',
      'rotisserie chicken',
      'chicken meat',
      'boneless chicken',
      'skinless chicken',
    ],
    'beef': [
      'ground beef',
      'beef steak',
      'steak',
      'raw beef',
      'beef meat',
      'sirloin',
      'ribeye',
      'chuck',
      'brisket',
    ],
    'pork': [
      'pork chop',
      'ground pork',
      'pork loin',
      'pork belly',
      'bacon',
      'ham',
    ],
    'fish': [
      'salmon',
      'tuna',
      'cod',
      'tilapia',
      'halibut',
      'trout',
      'fish fillet',
    ],
    'onion': [
      'onions',
      'yellow onion',
      'white onion',
      'red onion',
      'green onion',
      'scallion',
      'shallot',
    ],
    'garlic': [
      'garlic clove',
      'garlic cloves',
      'minced garlic',
      'fresh garlic',
    ],
    'tomato': [
      'tomatoes',
      'cherry tomato',
      'cherry tomatoes',
      'roma tomato',
      'diced tomatoes',
      'crushed tomatoes',
      'tomato paste',
      'tomato sauce',
    ],
    'pepper': [
      'bell pepper',
      'red pepper',
      'green pepper',
      'yellow pepper',
      'sweet pepper',
      'peppers',
    ],
    'cheese': [
      'cheddar',
      'mozzarella',
      'parmesan',
      'swiss',
      'feta',
      'gouda',
      'cream cheese',
      'shredded cheese',
    ],
    'yogurt': ['greek yogurt', 'plain yogurt', 'vanilla yogurt', 'yoghurt'],
    'milk': ['whole milk', 'skim milk', '2% milk', 'almond milk', 'oat milk'],
    'egg': ['eggs', 'large egg', 'large eggs', 'egg white', 'egg yolk'],
    'potato': [
      'potatoes',
      'russet potato',
      'yukon gold',
      'red potato',
      'sweet potato',
    ],
    'rice': [
      'white rice',
      'brown rice',
      'jasmine rice',
      'basmati rice',
      'long grain rice',
    ],
    'pasta': [
      'spaghetti',
      'penne',
      'fettuccine',
      'linguine',
      'macaroni',
      'rigatoni',
      'rotini',
    ],
    'oil': [
      'olive oil',
      'vegetable oil',
      'canola oil',
      'coconut oil',
      'cooking oil',
    ],
    'butter': ['unsalted butter', 'salted butter', 'melted butter'],
    'flour': [
      'all-purpose flour',
      'bread flour',
      'whole wheat flour',
      'ap flour',
    ],
    'sugar': [
      'white sugar',
      'brown sugar',
      'granulated sugar',
      'powdered sugar',
      'cane sugar',
    ],
    'salt': ['sea salt', 'kosher salt', 'table salt', 'himalayan salt'],
    'lettuce': [
      'romaine',
      'iceberg',
      'butter lettuce',
      'mixed greens',
      'salad greens',
    ],
    'carrot': ['carrots', 'baby carrots', 'shredded carrots'],
    'celery': ['celery stalk', 'celery stalks', 'celery ribs'],
    'broccoli': ['broccoli florets', 'broccoli crowns'],
    'spinach': ['baby spinach', 'fresh spinach', 'spinach leaves'],
    'mushroom': [
      'mushrooms',
      'button mushrooms',
      'cremini',
      'portobello',
      'shiitake',
    ],
    'lemon': ['lemons', 'lemon juice', 'fresh lemon'],
    'lime': ['limes', 'lime juice', 'fresh lime'],
    'cherry': ['cherries', 'frozen cherries', 'pitted cherries'],
    'pretzel': ['pretzels', 'pretzel nuggets', 'pretzel bites'],
    'cream': [
      'heavy cream',
      'whipping cream',
      'sour cream',
      'heavy whipping cream',
    ],
    // ─── International / pantry (20 additional families) ─────────────────
    'soy sauce': [
      'light soy sauce',
      'dark soy sauce',
      'tamari',
      'low sodium soy sauce',
      'liquid aminos',
    ],
    'tofu': [
      'firm tofu',
      'silken tofu',
      'extra firm tofu',
      'soft tofu',
      'baked tofu',
    ],
    'vinegar': [
      'white vinegar',
      'distilled vinegar',
      'rice vinegar',
      'apple cider vinegar',
      'balsamic vinegar',
      'red wine vinegar',
      'white wine vinegar',
      'sherry vinegar',
      'champagne vinegar',
    ],
    'basil': [
      'fresh basil',
      'sweet basil',
      'thai basil',
      'basil leaves',
      'dried basil',
    ],
    'cilantro': [
      'fresh cilantro',
      'coriander leaves',
      'cilantro leaves',
      'coriander',
    ],
    'parsley': [
      'fresh parsley',
      'flat leaf parsley',
      'curly parsley',
      'parsley leaves',
      'dried parsley',
    ],
    'thyme': [
      'fresh thyme',
      'thyme leaves',
      'dried thyme',
      'sprigs of thyme',
    ],
    'oregano': [
      'fresh oregano',
      'dried oregano',
      'oregano leaves',
    ],
    'ginger': [
      'fresh ginger',
      'ginger root',
      'minced ginger',
      'grated ginger',
      'ground ginger',
      'pickled ginger',
    ],
    'coconut milk': [
      'canned coconut milk',
      'full fat coconut milk',
      'lite coconut milk',
      'coconut cream',
    ],
    'quinoa': [
      'white quinoa',
      'red quinoa',
      'tri-color quinoa',
      'cooked quinoa',
    ],
    'oats': [
      'rolled oats',
      'old fashioned oats',
      'quick oats',
      'steel cut oats',
      'oatmeal',
    ],
    'beans': [
      'black beans',
      'kidney beans',
      'pinto beans',
      'cannellini beans',
      'white beans',
      'garbanzo beans',
      'chickpeas',
    ],
    'lentils': [
      'red lentils',
      'green lentils',
      'brown lentils',
      'french lentils',
      'puy lentils',
    ],
    'sesame oil': [
      'toasted sesame oil',
      'dark sesame oil',
      'sesame seed oil',
    ],
    'fish sauce': [
      'thai fish sauce',
      'nam pla',
      'nuoc mam',
    ],
    'hoisin sauce': [
      'hoisin',
      'chinese barbecue sauce',
    ],
    'curry': [
      'curry powder',
      'curry paste',
      'red curry paste',
      'green curry paste',
      'yellow curry powder',
      'madras curry',
    ],
    'soy': [
      'soy sauce',
      'tamari',
      'soy milk',
      'edamame',
    ],
    'honey': [
      'runny honey',
      'wild honey',
      'manuka honey',
      'maple syrup',
    ],
    'bread': [
      'bread slices',
      'white bread',
      'whole wheat bread',
      'sourdough',
      'baguette',
      'ciabatta',
    ],
    'nuts': [
      'almonds',
      'walnuts',
      'cashews',
      'pecans',
      'peanuts',
      'pine nuts',
      'hazelnuts',
    ],
  };

  /// Common basic pantry staples assumed to be available.
  static const Set<String> basicStaples = {
    'salt',
    'pepper',
    'black pepper',
    'white pepper',
    'oil',
    'olive oil',
    'vegetable oil',
    'canola oil',
    'cooking oil',
    'butter',
    'sugar',
    'brown sugar',
    'granulated sugar',
    'flour',
    'water',
  };

  /// Returns true if an ingredient should be treated as a basic pantry staple.
  static bool isBasicStaple(String ingredient) {
    final lower = ingredient.toLowerCase().trim();
    return basicStaples.any(
      (staple) =>
          lower == staple || lower.contains(staple) || staple.contains(lower),
    );
  }

  /// Check if recipe ingredient matches a pantry ingredient using fuzzy matching.
  static bool _ingredientMatches(
    String recipeIngredient,
    String pantryIngredient,
  ) {
    final recipeLower = recipeIngredient.toLowerCase().trim();
    final pantryLower = pantryIngredient.toLowerCase().trim();

    if (recipeLower == pantryLower) return true;

    if (recipeLower.contains(pantryLower) ||
        pantryLower.contains(recipeLower)) {
      return true;
    }

    final recipeWords = recipeLower.split(RegExp(r'[\s,]+'));
    final pantryWords = pantryLower.split(RegExp(r'[\s,]+'));

    for (var rWord in recipeWords) {
      if (rWord.length < 3) continue;
      for (var pWord in pantryWords) {
        if (pWord.length < 3) continue;
        if (rWord == pWord || rWord.contains(pWord) || pWord.contains(rWord)) {
          return true;
        }
      }
    }

    for (var entry in ingredientAliases.entries) {
      final baseIngredient = entry.key;
      final aliases = entry.value;

      bool recipeMatchesBase =
          recipeLower == baseIngredient ||
          recipeLower.contains(baseIngredient) ||
          aliases.any((a) => recipeLower.contains(a.toLowerCase()));

      bool pantryMatchesBase =
          pantryLower == baseIngredient ||
          pantryLower.contains(baseIngredient) ||
          aliases.any((a) => pantryLower.contains(a.toLowerCase()));

      if (recipeMatchesBase && pantryMatchesBase) {
        return true;
      }
    }

    return false;
  }

  /// Public helper for fuzzy ingredient matching.
  static bool ingredientMatches(
    String recipeIngredient,
    String pantryIngredient,
  ) {
    return _ingredientMatches(recipeIngredient, pantryIngredient);
  }

  // ─── POTLUCK: pantry match percentage, missing list, badge ───────────────

  /// Calculate pantry match percentage for a recipe (with fuzzy matching).
  static double calculatePantryMatchPercentage(
    List<String> recipeIngredients,
    List<Ingredient> pantryIngredients,
  ) {
    if (recipeIngredients.isEmpty) return 0.0;

    final pantryNames = pantryIngredients
        .where((ing) => ing.amount > 0)
        .map((ing) => ing.name)
        .toList();

    int matchCount = 0;
    for (var recipeIngredient in recipeIngredients) {
      if (isBasicStaple(recipeIngredient)) {
        matchCount++;
        continue;
      }
      bool found = pantryNames.any(
        (pantryName) => _ingredientMatches(recipeIngredient, pantryName),
      );
      if (found) matchCount++;
    }

    return (matchCount / recipeIngredients.length) * 100;
  }

  /// Get missing ingredients count (with fuzzy matching).
  static int getMissingIngredientsCount(
    List<String> recipeIngredients,
    List<Ingredient> pantryIngredients,
  ) {
    final pantryNames = pantryIngredients
        .where((ing) => ing.amount > 0)
        .map((ing) => ing.name)
        .toList();

    int missingCount = 0;
    for (var recipeIngredient in recipeIngredients) {
      if (isBasicStaple(recipeIngredient)) continue;
      bool found = pantryNames.any(
        (pantryName) => _ingredientMatches(recipeIngredient, pantryName),
      );
      if (!found) missingCount++;
    }
    return missingCount;
  }

  /// Get list of missing ingredients (with fuzzy matching).
  static List<String> getMissingIngredients(
    List<String> recipeIngredients,
    List<Ingredient> pantryIngredients,
  ) {
    final pantryNames = pantryIngredients
        .where((ing) => ing.amount > 0)
        .map((ing) => ing.name)
        .toList();

    return recipeIngredients.where(
      (ing) =>
          !isBasicStaple(ing) &&
          !pantryNames.any(
            (pantryName) => _ingredientMatches(ing, pantryName),
          ),
    ).toList();
  }

  /// Check if recipe is ready to cook (all ingredients available).
  static bool isReadyToCook(
    List<String> recipeIngredients,
    List<Ingredient> pantryIngredients,
  ) {
    return getMissingIngredientsCount(recipeIngredients, pantryIngredients) == 0;
  }

  /// Get pantry match badge (e.g. "✅", "+1", "+2").
  static String getPantryMatchBadge(
    List<String> recipeIngredients,
    List<Ingredient> pantryIngredients,
  ) {
    final missingCount =
        getMissingIngredientsCount(recipeIngredients, pantryIngredients);
    if (missingCount == 0) return '✅';
    if (missingCount == 1) return '+1';
    if (missingCount == 2) return '+2';
    return '+$missingCount';
  }
}
