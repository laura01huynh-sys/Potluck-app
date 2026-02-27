// ignore_for_file: deprecated_member_use, library_private_types_in_public_api

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:http/http.dart' as http;
import 'services/ingredient_detection_service.dart';
import 'services/edamam_recipe_service.dart';
import 'services/recipe_instruction_service.dart';
import 'services/recipe_ingredient_service.dart';
import 'services/recipe_data_service.dart';
import 'services/recipe_image_file_service.dart';
import 'services/firebase_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'config/gemini_config.dart';
import 'config/app_colors.dart';
import 'utils/format_utils.dart';

// ================= BACKGROUND JSON ENCODING =================
List<String> _encodeIngredientsInBackground(
  List<Map<String, dynamic>> ingredientsData,
) {
  return ingredientsData.map((data) => jsonEncode(data)).toList();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const PotluckApp());
}

class NutritionSummaryBar extends StatelessWidget {
  final Nutrition nutrition;
  final double servingMultiplier;

  const NutritionSummaryBar({
    super.key,
    required this.nutrition,
    this.servingMultiplier = 1.0,
  });

  Widget _buildMacroTile(String label, String formattedValue, Color color) {
    // Split value into number and unit for different styling
    final parts = formattedValue.split(' ');
    final number = parts.isNotEmpty ? parts[0] : formattedValue;
    final unit = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: number,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: kDeepForestGreen,
                    ),
                  ),
                  if (unit.isNotEmpty)
                    TextSpan(
                      text: ' $unit',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: kDeepForestGreen,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Apply serving multiplier to nutrition values
    final scaledCalories = (nutrition.calories * servingMultiplier).round();
    final scaledProtein = nutrition.protein * servingMultiplier;
    final scaledCarbs = nutrition.carbs * servingMultiplier;
    final scaledFat = nutrition.fat * servingMultiplier;

    return Row(
      children: [
        _buildMacroTile('Calories', '$scaledCalories kcal', kMutedGold),
        Container(width: 1, height: 28, color: kCharcoal.withOpacity(0.18)),
        _buildMacroTile(
          'Protein',
          '${scaledProtein.toStringAsFixed(0)} g',
          kDeepForestGreen,
        ),
        Container(width: 1, height: 28, color: kCharcoal.withOpacity(0.18)),
        _buildMacroTile(
          'Carbs',
          '${scaledCarbs.toStringAsFixed(0)} g',
          kSoftSlateGray,
        ),
        Container(width: 1, height: 28, color: kCharcoal.withOpacity(0.18)),
        _buildMacroTile(
          'Fat',
          '${scaledFat.toStringAsFixed(0)} g',
          kSoftTerracotta,
        ),
      ],
    );
  }
}

// ================= FILTER SERVICE =================
class FilterService {
  static const Map<String, List<String>> substitutionMap = {
    'Cilantro': ['Parsley', 'Basil'],
    'Mushrooms': ['Zucchini', 'Eggplant'],
    'Onions': ['Garlic', 'Leeks'],
    'Garlic': ['Onions', 'Shallots'],
  };

  static const Map<String, List<String>> lifestyleRules = {
    'vegetarian': ['Meat', 'Poultry', 'Seafood'],
    'vegan': ['Meat', 'Poultry', 'Seafood', 'Dairy', 'Eggs'],
    'keto': ['Grains', 'Sugar', 'HighCarb'],
    'paleo': ['Grains', 'Legumes', 'Dairy'],
    'gluten-free': ['Wheat', 'Barley', 'Rye'],
    'pescatarian': ['Meat', 'Poultry'],
    'kosher': [], // Handled separately due to Dairy+Meat combo rule
    'high-protein': [], // Ranking only, not exclusion
    'dairy-free': ['Dairy', 'Milk', 'Cheese', 'Butter'],
    'low-sodium': [], // Ranking only, not exclusion
    'halal': [], // Handled separately due to specific rules
  };

  /// Default ingredient classifications for quick-select options
  static const Map<String, List<String>> defaultIngredientClassification = {
    'allergy_risk': [
      'Peanuts',
      'Tree Nuts',
      'Shellfish',
      'Fish',
      'Soy',
      'Dairy',
      'Eggs',
      'Wheat',
      'Sesame',
    ],
    'common_avoidance': [
      'Cilantro',
      'Mushrooms',
      'Olives',
      'Eggplant',
      'Blue Cheese',
      'Mayonnaise',
      'Onions',
    ],
  };

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
      final excludedTags = lifestyleRules[lifestyle] ?? [];

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

  /// Tier 3: Check for avoided ingredients and get substitutes
  static List<String> getAvoidedIngredientsWithSubstitutes(
    Recipe recipe,
    Set<String> avoided,
  ) {
    final warnings = <String>[];
    for (var ingredient in recipe.ingredients) {
      if (avoided.contains(ingredient)) {
        final substitutes = substitutionMap[ingredient] ?? [];
        if (substitutes.isNotEmpty) {
          warnings.add('$ingredient → Try ${substitutes.first}!');
        } else {
          warnings.add('Contains $ingredient (You dislike this)');
        }
      }
    }
    return warnings;
  }

  /// Tier 3: Get avoided ingredients with substitutes as a map
  static Map<String, String> getAvoidedIngredientsMap(
    Recipe recipe,
    Set<String> avoided,
  ) {
    final result = <String, String>{};
    for (var ingredient in recipe.ingredients) {
      if (avoided.contains(ingredient)) {
        final substitutes = substitutionMap[ingredient] ?? [];
        result[ingredient] = substitutes.isNotEmpty
            ? substitutes.join(', ')
            : 'No substitute available';
      }
    }
    return result;
  }

  /// Apply filters to recipes
  static List<Recipe> filterRecipes(List<Recipe> recipes, UserProfile profile) {
    return recipes.where((recipe) {
      // Tier 1: Allergies - total exclusion
      if (hasAllergyConflict(recipe, profile.allergies)) {
        return false;
      }

      // Tier 2: Lifestyles - exclusion
      if (violatesLifestyle(recipe, profile.selectedLifestyles)) {
        return false;
      }

      // Tier 2: Custom Lifestyles - exclusion
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
  static List<Recipe> sortByProtein(List<Recipe> recipes, bool isHighProtein) {
    if (!isHighProtein) return recipes;
    return recipes..sort((a, b) => b.proteinGrams.compareTo(a.proteinGrams));
  }

  /// Get all allergy risk ingredients
  static List<String> getAllergyRiskIngredients() {
    return defaultIngredientClassification['allergy_risk'] ?? [];
  }

  /// Get all common avoidance ingredients
  static List<String> getCommonAvoidanceIngredients() {
    return defaultIngredientClassification['common_avoidance'] ?? [];
  }

  /// Quick add all allergy risk ingredients to allergies
  static Set<String> addAllAllergyRisks(Set<String> currentAllergies) {
    return {...currentAllergies, ...getAllergyRiskIngredients()};
  }

  /// Quick add all common avoidance ingredients to avoided
  static Set<String> addAllCommonAvoidance(Set<String> currentAvoided) {
    return {...currentAvoided, ...getCommonAvoidanceIngredients()};
  }

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
        // Check if any recipe ingredient is in the blocked list
        for (var ingredient in recipe.ingredients) {
          if (lifestyle.blockList.contains(ingredient)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Common ingredient aliases for fuzzy matching
  /// Maps base ingredient names to their variations
  static const Map<String, List<String>> ingredientAliases = {
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
  };

  /// Common basic pantry staples assumed to be available
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

  /// Returns true if an ingredient should be treated as a basic pantry staple
  static bool isBasicStaple(String ingredient) {
    final lower = ingredient.toLowerCase().trim();
    return basicStaples.any(
      (staple) =>
          lower == staple || lower.contains(staple) || staple.contains(lower),
    );
  }

  /// Check if recipe ingredient matches a pantry ingredient using fuzzy matching
  static bool _ingredientMatches(
    String recipeIngredient,
    String pantryIngredient,
  ) {
    final recipeLower = recipeIngredient.toLowerCase().trim();
    final pantryLower = pantryIngredient.toLowerCase().trim();

    // Direct match
    if (recipeLower == pantryLower) return true;

    // Contains match (either direction)
    if (recipeLower.contains(pantryLower) ||
        pantryLower.contains(recipeLower)) {
      return true;
    }

    // Check word overlap (at least one significant word matches)
    final recipeWords = recipeLower.split(RegExp(r'[\s,]+'));
    final pantryWords = pantryLower.split(RegExp(r'[\s,]+'));

    for (var rWord in recipeWords) {
      if (rWord.length < 3) continue; // Skip short words like "of", "a", etc.
      for (var pWord in pantryWords) {
        if (pWord.length < 3) continue;
        if (rWord == pWord || rWord.contains(pWord) || pWord.contains(rWord)) {
          return true;
        }
      }
    }

    // Check aliases
    for (var entry in ingredientAliases.entries) {
      final baseIngredient = entry.key;
      final aliases = entry.value;

      // Check if recipe ingredient matches base or any alias
      bool recipeMatchesBase =
          recipeLower == baseIngredient ||
          recipeLower.contains(baseIngredient) ||
          aliases.any((a) => recipeLower.contains(a.toLowerCase()));

      // Check if pantry ingredient matches base or any alias
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

  /// Public helper for fuzzy ingredient matching
  static bool ingredientMatches(
    String recipeIngredient,
    String pantryIngredient,
  ) {
    return _ingredientMatches(recipeIngredient, pantryIngredient);
  }

  /// POTLUCK FEATURE: Calculate pantry match percentage for a recipe (with fuzzy matching)
  static double calculatePantryMatchPercentage(
    List<String> recipeIngredients,
    List<Ingredient> pantryIngredients,
  ) {
    if (recipeIngredients.isEmpty) return 0.0;

    final pantryNames = pantryIngredients
        .where((ing) => ing.amount > 0) // Only count items in stock
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

    final percentage = (matchCount / recipeIngredients.length) * 100;
    return percentage;
  }

  /// POTLUCK FEATURE: Get missing ingredients count (with fuzzy matching)
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
      if (isBasicStaple(recipeIngredient)) {
        continue;
      }
      bool found = pantryNames.any(
        (pantryName) => _ingredientMatches(recipeIngredient, pantryName),
      );
      if (!found) missingCount++;
    }
    return missingCount;
  }

  /// POTLUCK FEATURE: Get list of missing ingredients (with fuzzy matching)
  static List<String> getMissingIngredients(
    List<String> recipeIngredients,
    List<Ingredient> pantryIngredients,
  ) {
    final pantryNames = pantryIngredients
        .where((ing) => ing.amount > 0)
        .map((ing) => ing.name)
        .toList();

    return recipeIngredients
        .where(
          (ing) =>
              !isBasicStaple(ing) &&
              !pantryNames.any(
                (pantryName) => _ingredientMatches(ing, pantryName),
              ),
        )
        .toList();
  }

  /// POTLUCK FEATURE: Check if recipe is ready to cook (all ingredients available)
  static bool isReadyToCook(
    List<String> recipeIngredients,
    List<Ingredient> pantryIngredients,
  ) {
    return getMissingIngredientsCount(recipeIngredients, pantryIngredients) ==
        0;
  }

  /// POTLUCK FEATURE: Get pantry match badge (e.g., "✅", "+1", "+2")
  static String getPantryMatchBadge(
    List<String> recipeIngredients,
    List<Ingredient> pantryIngredients,
  ) {
    final missingCount = getMissingIngredientsCount(
      recipeIngredients,
      pantryIngredients,
    );

    if (missingCount == 0) {
      return '✅'; // Ready to cook
    } else if (missingCount == 1) {
      return '+1'; // Missing 1 ingredient
    } else if (missingCount == 2) {
      return '+2'; // Missing 2 ingredients
    } else {
      return '+$missingCount'; // Missing more than 2
    }
  }
}

// Data Models
class FridgeImage {
  final String id;
  final File imageFile;
  final DateTime timestamp;
  final ImageSource source;
  final List<String> ingredients;

  FridgeImage({
    required this.id,
    required this.imageFile,
    required this.timestamp,
    required this.source,
    this.ingredients = const [],
  });

  FridgeImage copyWith({
    String? id,
    File? imageFile,
    DateTime? timestamp,
    ImageSource? source,
    List<String>? ingredients,
  }) {
    return FridgeImage(
      id: id ?? this.id,
      imageFile: imageFile ?? this.imageFile,
      timestamp: timestamp ?? this.timestamp,
      source: source ?? this.source,
      ingredients: ingredients ?? this.ingredients,
    );
  }
}

enum IngredientCategory {
  proteins('Proteins'),
  produce('Produce'),
  dairyRefrigerated('Dairy & Refrigerated'),
  cannedGoods('Canned Goods'),
  snacksExtras('Snacks & Extras'),
  condimentsSauces('Condiments & Sauces'),
  grainsLegumes('Grains & Legumes'),
  spicesSeasonings('Spices & Seasonings'),
  baking('Baking'),
  frozen('Frozen');

  final String displayName;
  const IngredientCategory(this.displayName);
}

enum UnitType {
  volume, // Liters/mL - represented as 0.0-1.0 (Full to Empty)
  count, // Units/pieces - represented as integer
  weight; // Grams - represented as integer

  String get label => switch (this) {
    UnitType.volume => 'Volume',
    UnitType.count => 'Count',
    UnitType.weight => 'Weight',
  };
}

class Ingredient {
  final String id;
  final String name;
  final String? imageId; // Reference to the FridgeImage it came from
  final IngredientCategory category;
  final UnitType unitType; // volume, count, or weight
  final dynamic amount; // double for volume (0.0-1.0), int for count/weight
  final String baseUnit; // e.g., 'bottle', 'units', 'grams'
  final bool isSelected;
  final bool isPriority; // Mark as must-use ingredient for recipe search
  final bool isAvoided; // Mark as ingredient user wants to avoid
  final bool isAllergy; // Mark as ingredient user is allergic to

  Ingredient({
    required this.id,
    required this.name,
    this.imageId,
    required this.category,
    required this.unitType,
    required this.amount,
    required this.baseUnit,
    this.isSelected = false,
    this.isPriority = false,
    this.isAvoided = false,
    this.isAllergy = false,
  });

  bool get needsPurchase => amount == 0 || (amount is double && amount < 0.01);

  /// Returns normalized amount (0.0-1.0) for color calculations
  double get normalizedAmount {
    return switch (unitType) {
      UnitType.volume => (amount as double).clamp(0.0, 1.0),
      UnitType.count =>
        (amountAsDouble(amount) > 0
            ? (amountAsDouble(amount) / 5.0).clamp(0.0, 1.0)
            : 0.0),
      UnitType.weight => (amountAsDouble(amount) / 500.0).clamp(
        0.0,
        1.0,
      ), // 500g = full
    };
  }

  /// Generates smart label under ingredient name
  String getSmartLabel() {
    return switch (unitType) {
      UnitType.volume => _getVolumeLabel(),
      UnitType.count => _getCountLabel(),
      UnitType.weight => _getWeightLabel(),
    };
  }

  String _getVolumeLabel() {
    final vol = amount as double;
    if (vol >= 0.9) return 'Full $baseUnit';
    if (vol >= 0.6) return '3/4 $baseUnit';
    if (vol >= 0.4) return 'Half $baseUnit';
    if (vol >= 0.2) return '1/4 $baseUnit';
    return 'Empty';
  }

  String _getCountLabel() {
    final count = amountAsInt(amount);
    return '$count $baseUnit';
  }

  String _getWeightLabel() {
    final weight = amountAsDouble(amount);
    final unitLower = baseUnit.toLowerCase();
    final isGramUnit =
        unitLower == 'g' || unitLower == 'gram' || unitLower == 'grams';
    if (isGramUnit) {
      if (weight >= 1000) {
        return 'About ${(weight / 1000).toStringAsFixed(1)} kg of $baseUnit';
      }
      return 'About $weight $baseUnit';
    }
    return 'About $weight $baseUnit';
  }

  Ingredient copyWith({
    String? id,
    String? name,
    String? imageId,
    IngredientCategory? category,
    UnitType? unitType,
    dynamic amount,
    String? baseUnit,
    bool? isSelected,
    bool? isPriority,
    bool? isAvoided,
    bool? isAllergy,
  }) {
    return Ingredient(
      id: id ?? this.id,
      name: name ?? this.name,
      imageId: imageId ?? this.imageId,
      category: category ?? this.category,
      unitType: unitType ?? this.unitType,
      amount: amount ?? this.amount,
      baseUnit: baseUnit ?? this.baseUnit,
      isSelected: isSelected ?? this.isSelected,
      isPriority: isPriority ?? this.isPriority,
      isAvoided: isAvoided ?? this.isAvoided,
      isAllergy: isAllergy ?? this.isAllergy,
    );
  }
}

// Nutrition model for recipes
class Nutrition {
  final int calories; // kcal
  final double protein; // g
  final double fat; // g
  final double carbs; // g

  // Optional micros
  final double? fiber; // g
  final double? sugar; // g
  final double? sodium; // mg

  Nutrition({
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    this.fiber,
    this.sugar,
    this.sodium,
  });

  factory Nutrition.fromMap(Map<String, dynamic> json) {
    double readNum(String key) {
      final value = json[key];
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    return Nutrition(
      calories: readNum('calories').round(),
      protein: readNum('protein'),
      fat: readNum('fat'),
      carbs: readNum('carbs'),
      fiber: json['fiber'] != null ? readNum('fiber') : null,
      sugar: json['sugar'] != null ? readNum('sugar') : null,
      sodium: json['sodium'] != null ? readNum('sodium') : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'calories': calories,
    'protein': protein,
    'fat': fat,
    'carbs': carbs,
    'fiber': fiber,
    'sugar': sugar,
    'sodium': sodium,
  };
}

/// Compact, collapsible nutrition details with per-nutrient toggles.
class CompactNutritionDetails extends StatefulWidget {
  final Nutrition nutrition;

  const CompactNutritionDetails({super.key, required this.nutrition});

  @override
  State<CompactNutritionDetails> createState() =>
      _CompactNutritionDetailsState();
}

class _CompactNutritionDetailsState extends State<CompactNutritionDetails> {
  late final Map<String, String> _allFacts;
  @override
  void initState() {
    super.initState();
    _allFacts = {
      'Calories': '${widget.nutrition.calories} kcal',
      'Protein': '${widget.nutrition.protein.toStringAsFixed(0)} g',
      'Fat': '${widget.nutrition.fat.toStringAsFixed(0)} g',
      'Carbs': '${widget.nutrition.carbs.toStringAsFixed(0)} g',
    };

    if (widget.nutrition.fiber != null) {
      _allFacts['Fiber'] = '${widget.nutrition.fiber!.toStringAsFixed(1)} g';
    }
    if (widget.nutrition.sugar != null) {
      _allFacts['Sugar'] = '${widget.nutrition.sugar!.toStringAsFixed(1)} g';
    }
    if (widget.nutrition.sodium != null) {
      _allFacts['Sodium'] = '${widget.nutrition.sodium!.toStringAsFixed(0)} mg';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Define core nutrients to exclude
    const coreNutrients = {'Calories', 'Protein', 'Fat', 'Carbs'};

    // Only show additional facts (not core nutrients)
    final additionalFactKeys = _allFacts.keys
        .where((k) => !coreNutrients.contains(k))
        .toList();

    if (additionalFactKeys.isEmpty) {
      return const Text(
        'No additional nutritional information.',
        style: TextStyle(fontSize: 12, color: kSoftSlateGray),
      );
    }

    // Show additional facts as left-aligned, smaller font pills, no semicolon, and format numbers
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        alignment: WrapAlignment.start,
        spacing: 6,
        runSpacing: 4,
        children: additionalFactKeys.map((key) {
          // Remove semicolon, format value (remove .0 for whole numbers)
          String value = _allFacts[key] ?? '';
          // Remove trailing .0 for whole numbers and join number/unit with no space (e.g., 8g)
          value = value.replaceAllMapped(
            RegExp(r'(\d+)\.0\s*(\w+)'),
            (m) => '${m[1]}${m[2]}',
          );
          // Also join any number and unit with no space (e.g., 8 g -> 8g)
          value = value.replaceAllMapped(
            RegExp(r'(\d+)\s+(\w+)'),
            (m) => '${m[1]}${m[2]}',
          );
          value = value.replaceAll(';', '');
          return Chip(
            label: Text(
              '$key $value',
              style: const TextStyle(
                fontSize: 12,
                color: kDeepForestGreen,
                fontWeight: FontWeight.w700, // Bold text per request
              ),
            ),
            backgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: kSageGreen.withOpacity(0.25)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity(vertical: -2),
          );
        }).toList(),
      ),
    );
  }
}

class Recipe {
  final String id;
  final String title;
  final String imageUrl;
  final List<String> ingredients;
  final Map<String, List<String>>
  ingredientTags; // ingredient -> [tags like 'Meat', 'Grain', etc.]
  final Map<String, String> ingredientMeasurements; // ingredient -> measurement
  final int cookTimeMinutes;
  final double rating;
  final int reviewCount;
  final DateTime createdDate;
  final bool isSaved;
  final List<String>
  mealTypes; // breakfast, lunch, dinner, dessert, snacks, appetizers
  final int proteinGrams; // for High-Protein ranking
  final String authorName; // Who shared this recipe
  final double
  aspectRatio; // For staggered grid (e.g., 0.7 = tall, 1.0 = square)
  // Optional nutrition facts
  final Nutrition? nutrition;
  final String? sourceUrl; // URL to the original recipe

  Recipe({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.ingredients,
    this.ingredientTags = const {},
    this.ingredientMeasurements = const {},
    required this.cookTimeMinutes,
    required this.rating,
    required this.reviewCount,
    required this.createdDate,
    required this.isSaved,
    this.mealTypes = const ['lunch'],
    this.proteinGrams = 0,
    this.authorName = 'Anonymous',
    this.aspectRatio = 1.0,
    this.nutrition,
    this.sourceUrl,
  });

  Recipe copyWith({
    String? id,
    String? title,
    String? imageUrl,
    List<String>? ingredients,
    Map<String, List<String>>? ingredientTags,
    Map<String, String>? ingredientMeasurements,
    int? cookTimeMinutes,
    double? rating,
    int? reviewCount,
    DateTime? createdDate,
    bool? isSaved,
    List<String>? mealTypes,
    int? proteinGrams,
    String? authorName,
    double? aspectRatio,
    Nutrition? nutrition,
    String? sourceUrl,
  }) {
    return Recipe(
      id: id ?? this.id,
      title: title ?? this.title,
      imageUrl: imageUrl ?? this.imageUrl,
      ingredients: ingredients ?? this.ingredients,
      ingredientTags: ingredientTags ?? this.ingredientTags,
      ingredientMeasurements:
          ingredientMeasurements ?? this.ingredientMeasurements,
      cookTimeMinutes: cookTimeMinutes ?? this.cookTimeMinutes,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      createdDate: createdDate ?? this.createdDate,
      isSaved: isSaved ?? this.isSaved,
      mealTypes: mealTypes ?? this.mealTypes,
      proteinGrams: proteinGrams ?? this.proteinGrams,
      authorName: authorName ?? this.authorName,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      nutrition: nutrition ?? this.nutrition,
      sourceUrl: sourceUrl ?? this.sourceUrl,
    );
  }
}

// ================= COMMUNITY FEED MODEL =================
class CommunityReview {
  final String id;
  final String recipeId;
  final String userName;
  final String? userAvatarUrl;
  final int rating; // 1-5 stars
  final String comment;
  final String? imageUrl; // Photo of finished dish
  final DateTime createdDate;
  final int likes; // Number of likes this review received
  final List<ReviewReply> replies; // Replies to this review

  CommunityReview({
    required this.id,
    required this.recipeId,
    required this.userName,
    this.userAvatarUrl,
    required this.rating,
    required this.comment,
    this.imageUrl,
    required this.createdDate,
    this.likes = 0,
    this.replies = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'recipeId': recipeId,
    'userName': userName,
    'userAvatarUrl': userAvatarUrl,
    'rating': rating,
    'comment': comment,
    'imageUrl': imageUrl,
    'createdDate': createdDate.toIso8601String(),
    'likes': likes,
    'replies': replies.map((r) => r.toJson()).toList(),
  };

  factory CommunityReview.fromJson(Map<String, dynamic> json) {
    return CommunityReview(
      id: json['id'],
      recipeId: json['recipeId'],
      userName: json['userName'],
      userAvatarUrl: json['userAvatarUrl'],
      rating: json['rating'],
      comment: json['comment'],
      imageUrl: json['imageUrl'],
      createdDate: DateTime.parse(json['createdDate']),
      likes: json['likes'] ?? 0,
      replies:
          (json['replies'] as List<dynamic>?)
              ?.map((r) => ReviewReply.fromJson(r))
              .toList() ??
          [],
    );
  }
}

// ================= REVIEW REPLY MODEL =================
class ReviewReply {
  final String id;
  final String userName;
  final String comment;
  final DateTime createdDate;
  final int likes;

  ReviewReply({
    required this.id,
    required this.userName,
    required this.comment,
    required this.createdDate,
    this.likes = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'userName': userName,
    'comment': comment,
    'createdDate': createdDate.toIso8601String(),
    'likes': likes,
  };

  factory ReviewReply.fromJson(Map<String, dynamic> json) {
    return ReviewReply(
      id: json['id'],
      userName: json['userName'],
      comment: json['comment'],
      createdDate: DateTime.parse(json['createdDate']),
      likes: json['likes'] ?? 0,
    );
  }
}

// ================= FILTER MODELS =================
enum EffortLevel {
  quick('Quick', 'Under 20m', 20),
  medium('Medium', '20-45m', 45),
  project('Project', 'Over 45m', 999);

  final String label;
  final String description;
  final int maxMinutes;

  const EffortLevel(this.label, this.description, this.maxMinutes);
}

enum MealContext {
  breakfast('Breakfast', '5:00', '11:59'),
  lunch('Lunch', '12:00', '16:59'),
  dinner('Dinner', '17:00', '23:59');

  final String label;
  final String startTime; // HH:mm format
  final String endTime; // HH:mm format

  const MealContext(this.label, this.startTime, this.endTime);

  static MealContext getCurrentMealContext() {
    final now = DateTime.now();
    final hour = now.hour;

    if (hour >= 5 && hour < 12) return MealContext.breakfast;
    if (hour >= 12 && hour < 17) return MealContext.lunch;
    return MealContext.dinner;
  }
}

class RecipeFilter {
  final bool
  showOnlyReadyToCook; // true = only 100%, false = all recommendations
  final Set<EffortLevel> selectedEffortLevels;
  final Set<MealContext> selectedMealContexts;
  final Set<String> avoidedIngredients; // Ingredients to exclude
  final Set<String> allergyIngredients; // Ingredients to exclude

  RecipeFilter({
    this.showOnlyReadyToCook = false,
    Set<EffortLevel>? selectedEffortLevels,
    Set<MealContext>? selectedMealContexts,
    Set<String>? avoidedIngredients,
    Set<String>? allergyIngredients,
  }) : selectedEffortLevels = selectedEffortLevels ?? {},
       selectedMealContexts = selectedMealContexts ?? {},
       avoidedIngredients = avoidedIngredients ?? {},
       allergyIngredients = allergyIngredients ?? {};

  RecipeFilter copyWith({
    bool? showOnlyReadyToCook,
    Set<EffortLevel>? selectedEffortLevels,
    Set<MealContext>? selectedMealContexts,
    Set<String>? avoidedIngredients,
    Set<String>? allergyIngredients,
  }) {
    return RecipeFilter(
      showOnlyReadyToCook: showOnlyReadyToCook ?? this.showOnlyReadyToCook,
      selectedEffortLevels: selectedEffortLevels ?? this.selectedEffortLevels,
      selectedMealContexts: selectedMealContexts ?? this.selectedMealContexts,
      avoidedIngredients: avoidedIngredients ?? this.avoidedIngredients,
      allergyIngredients: allergyIngredients ?? this.allergyIngredients,
    );
  }

  bool get hasActiveFilters =>
      showOnlyReadyToCook ||
      selectedEffortLevels.isNotEmpty ||
      selectedMealContexts.length < MealContext.values.length ||
      avoidedIngredients.isNotEmpty ||
      allergyIngredients.isNotEmpty;

  List<String> getActiveFilterLabels() {
    final labels = <String>[];

    if (showOnlyReadyToCook) labels.add('Potluck');
    if (selectedEffortLevels.isNotEmpty) {
      labels.add(selectedEffortLevels.map((e) => e.label).join(', '));
    }
    if (selectedMealContexts.isNotEmpty) {
      labels.add(selectedMealContexts.map((e) => e.label).join(', '));
    }
    if (avoidedIngredients.isNotEmpty) {
      labels.add('${avoidedIngredients.length} Avoided');
    }
    if (allergyIngredients.isNotEmpty) {
      labels.add('${allergyIngredients.length} Allergies');
    }

    return labels;
  }
}

// ================= CUSTOM LIFESTYLE MODEL =================
class CustomLifestyle {
  final String id;
  final String name;
  final List<String> blockList; // Ingredients to exclude

  CustomLifestyle({
    required this.id,
    required this.name,
    required this.blockList,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'blockList': blockList,
  };

  factory CustomLifestyle.fromJson(Map<String, dynamic> json) {
    return CustomLifestyle(
      id: json['id'],
      name: json['name'],
      blockList: List<String>.from(json['blockList'] ?? []),
    );
  }
}

// ================= PROFILE MODELS =================
class UserProfile {
  final String userId;
  final String userName;
  final String? avatarUrl;
  final Set<String> allergies; // Ingredient names with allergy flag
  final Set<String> avoided; // Ingredient names with avoid flag
  final List<String> savedRecipeIds; // IDs of saved recipes
  final List<String> cookedRecipeIds; // IDs of cooked recipes
  final int recipesCookedCount;
  final double estimatedMoneySaved;
  final Set<String>
  selectedLifestyles; // vegan, vegetarian, keto, paleo, gluten-free, pescatarian, kosher, high-protein
  final List<String> customRestrictions; // User-defined custom restrictions
  final List<CustomLifestyle> customLifestyles; // User-created lifestyle rules
  final Set<String> activeCustomLifestyles; // IDs of active custom lifestyles

  UserProfile({
    required this.userId,
    required this.userName,
    this.avatarUrl,
    Set<String>? allergies,
    Set<String>? avoided,
    List<String>? savedRecipeIds,
    List<String>? cookedRecipeIds,
    this.recipesCookedCount = 0,
    this.estimatedMoneySaved = 0.0,
    Set<String>? selectedLifestyles,
    List<String>? customRestrictions,
    List<CustomLifestyle>? customLifestyles,
    Set<String>? activeCustomLifestyles,
  }) : allergies = allergies ?? {},
       avoided = avoided ?? {},
       savedRecipeIds = savedRecipeIds ?? [],
       cookedRecipeIds = cookedRecipeIds ?? [],
       selectedLifestyles = selectedLifestyles ?? {},
       customRestrictions = customRestrictions ?? [],
       customLifestyles = customLifestyles ?? [],
       activeCustomLifestyles = activeCustomLifestyles ?? {};

  UserProfile copyWith({
    String? userId,
    String? userName,
    String? avatarUrl,
    Set<String>? allergies,
    Set<String>? avoided,
    List<String>? savedRecipeIds,
    List<String>? cookedRecipeIds,
    int? recipesCookedCount,
    double? estimatedMoneySaved,
    Set<String>? selectedLifestyles,
    List<String>? customRestrictions,
    List<CustomLifestyle>? customLifestyles,
    Set<String>? activeCustomLifestyles,
  }) {
    return UserProfile(
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      allergies: allergies ?? this.allergies,
      avoided: avoided ?? this.avoided,
      savedRecipeIds: savedRecipeIds ?? this.savedRecipeIds,
      cookedRecipeIds: cookedRecipeIds ?? this.cookedRecipeIds,
      recipesCookedCount: recipesCookedCount ?? this.recipesCookedCount,
      estimatedMoneySaved: estimatedMoneySaved ?? this.estimatedMoneySaved,
      selectedLifestyles: selectedLifestyles ?? this.selectedLifestyles,
      customRestrictions: customRestrictions ?? this.customRestrictions,
      customLifestyles: customLifestyles ?? this.customLifestyles,
      activeCustomLifestyles:
          activeCustomLifestyles ?? this.activeCustomLifestyles,
    );
  }
}

// ================= NO TRANSITION BUILDER =================
class ZeroTransitionsBuilder extends PageTransitionsBuilder {
  const ZeroTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

class PotluckApp extends StatefulWidget {
  const PotluckApp({super.key});

  @override
  State<PotluckApp> createState() => _PotluckAppState();
}

class _PotluckAppState extends State<PotluckApp> {
  bool _isAuthenticated = false;
  bool _needsChefIdentity = false;
  bool _checkingSession = true;
  late final StreamSubscription<User?> _authSub;

  @override
  void initState() {
    super.initState();
    _isAuthenticated = FirebaseService.isSignedIn;
    _checkingSession = false;
    _authSub = FirebaseService.authStateChanges.listen((user) {
      setState(() {
        _isAuthenticated = user != null;
      });
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  static const _theme = TextTheme(
    displayLarge: TextStyle(
      fontFamily: 'Lora',
      fontSize: 32,
      fontWeight: FontWeight.bold,
      color: kDeepForestGreen,
      letterSpacing: 0.5,
    ),
    displayMedium: TextStyle(
      fontFamily: 'Lora',
      fontSize: 28,
      fontWeight: FontWeight.bold,
      color: kDeepForestGreen,
      letterSpacing: 0.5,
    ),
    headlineSmall: TextStyle(
      fontFamily: 'Lora',
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: kDeepForestGreen,
      letterSpacing: 0.5,
    ),
    titleLarge: TextStyle(
      fontFamily: 'Inter',
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: kDeepForestGreen,
      letterSpacing: 0.5,
    ),
    titleMedium: TextStyle(
      fontFamily: 'Inter',
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: kDeepForestGreen,
      letterSpacing: 0.5,
    ),
    bodyLarge: TextStyle(
      fontFamily: 'Inter',
      fontSize: 16,
      fontWeight: FontWeight.normal,
      color: kDeepForestGreen,
      letterSpacing: 0.5,
    ),
    bodyMedium: TextStyle(
      fontFamily: 'Inter',
      fontSize: 14,
      fontWeight: FontWeight.normal,
      color: kSoftSlateGray,
      letterSpacing: 0.5,
    ),
    labelMedium: TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: kSoftSlateGray,
      letterSpacing: 0.5,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Potluck',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kBoneCreame,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: ZeroTransitionsBuilder(),
            TargetPlatform.iOS: ZeroTransitionsBuilder(),
          },
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 90, 131, 120),
        ),
        textTheme: _theme,
        appBarTheme: const AppBarTheme(
          backgroundColor: kBoneCreame,
          foregroundColor: kDeepForestGreen,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: _checkingSession
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _isAuthenticated && _needsChefIdentity
              ? ChefIdentityScreen(
                  onComplete: () {
                    setState(() => _needsChefIdentity = false);
                  },
                )
              : _isAuthenticated
                  ? const MainNavigation()
                  : WelcomeScreen(
                      onSignUpSuccess: () {
                        setState(() {
                          _isAuthenticated = true;
                          _needsChefIdentity = true;
                        });
                      },
                      onSignInSuccess: () {
                        setState(() => _isAuthenticated = true);
                      },
                    ),
    );
  }
}

// ================= WELCOME / AUTH SCREEN (Phase 1: Speedy signup) =================
class WelcomeScreen extends StatefulWidget {
  /// Called when sign-up succeeds — app shows Chef Identity step next.
  final VoidCallback? onSignUpSuccess;
  /// Called when sign-in succeeds — app goes to Home.
  final VoidCallback? onSignInSuccess;

  const WelcomeScreen({super.key, this.onSignUpSuccess, this.onSignInSuccess});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;

  void _showSignUpModal(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.66;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) => SizedBox(
        height: height,
        child: _SignUpSheetContent(
          onSuccess: () {
            Navigator.pop(modalContext);
            widget.onSignUpSuccess?.call();
          },
          onClose: () => Navigator.pop(modalContext),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('Invalid login credentials')) {
      return 'Invalid email or password. Please try again.';
    }
    if (msg.contains('User already registered')) {
      return 'An account with this email already exists. Try signing in.';
    }
    if (msg.contains('Password should be at least')) {
      return 'Password must be at least 6 characters.';
    }
    if (msg.contains('Unable to validate email')) {
      return 'Please enter a valid email address.';
    }
    if (msg.contains('Email rate limit exceeded')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (msg.contains('Connection timed out') || msg.contains('TimeoutException')) {
      return 'Connection timed out. Check your network and try again.';
    }
    return msg.replaceFirst('AuthException: ', '').replaceFirst('Exception: ', '');
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email and password are required.');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      if (_isSignUp) {
        await FirebaseService.signUp(email, password).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw Exception('Connection timed out. Check your network.'),
        );
      } else {
        await FirebaseService.signIn(email, password).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw Exception('Connection timed out. Check your network.'),
        );
      }
      if (!mounted) return;
      if (FirebaseService.isSignedIn) {
        setState(() => _loading = false);
        if (!mounted) return;
        if (_isSignUp) {
          widget.onSignUpSuccess?.call();
        } else {
          widget.onSignInSuccess?.call();
        }
      } else {
        setState(() {
          _error = _isSignUp
              ? 'Account created! Check your email to confirm, then sign in.'
              : 'Sign-in failed. Please try again.';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isSignUp = _isSignUp;

    return Scaffold(
      backgroundColor: isSignUp
          ? kDeepForestGreen.withOpacity(0.06)
          : kBoneCreame,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 24, 24, bottomInset + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ----- Sign Up: full-width header card -----
                if (isSignUp) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
                    decoration: BoxDecoration(
                      color: kDeepForestGreen,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: kDeepForestGreen.withOpacity(0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.restaurant_menu,
                          color: Colors.white,
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Join Potluck',
                          style: TextStyle(
                            fontFamily: 'Lora',
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Get cooking in seconds',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                ],

                // ----- Sign In: compact logo + title -----
                if (!isSignUp) ...[
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: kDeepForestGreen,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: kDeepForestGreen.withOpacity(0.2),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.restaurant_menu,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Welcome back',
                    style: TextStyle(
                      fontFamily: 'Lora',
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: kDeepForestGreen,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sign in to continue',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      color: kSoftSlateGray,
                    ),
                  ),
                  const SizedBox(height: 28),
                ],

                // ----- Sign Up: form in a card -----
                if (isSignUp)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: _buildForm(context),
                  )
                else
                  _buildForm(context),

                const SizedBox(height: 20),

                // Toggle sign in / sign up (Sign Up opens modal; Sign In toggles back)
                TextButton(
                  onPressed: () {
                    if (isSignUp) {
                      setState(() {
                        _isSignUp = false;
                        _error = null;
                      });
                    } else {
                      _showSignUpModal(context);
                    }
                  },
                  child: Text.rich(
                    TextSpan(
                      text: isSignUp ? 'Already have an account? ' : "Don't have an account? ",
                      style: TextStyle(color: kSoftSlateGray, fontSize: 14),
                      children: [
                        TextSpan(
                          text: isSignUp ? 'Sign In' : 'Sign Up',
                          style: const TextStyle(
                            color: kDeepForestGreen,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final isSignUp = _isSignUp;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'Email',
            prefixIcon: const Icon(Icons.email_outlined, size: 20),
            filled: true,
            fillColor: isSignUp ? kBoneCreame.withOpacity(0.4) : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: kMutedGold.withOpacity(0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: kMutedGold.withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kDeepForestGreen, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                size: 20,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            filled: true,
            fillColor: isSignUp ? kBoneCreame.withOpacity(0.4) : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: kMutedGold.withOpacity(0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: kMutedGold.withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kDeepForestGreen, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _loading ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: isSignUp ? kMutedGold : kDeepForestGreen,
              foregroundColor: isSignUp ? kDeepForestGreen : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _loading
                ? SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isSignUp ? kDeepForestGreen : Colors.white,
                    ),
                  )
                : Text(
                    isSignUp ? 'Join' : 'Sign In',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isSignUp ? kDeepForestGreen : Colors.white,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Sign-up form shown in a modal bottom sheet (two-thirds height).
class _SignUpSheetContent extends StatefulWidget {
  final VoidCallback? onSuccess;
  final VoidCallback onClose;

  const _SignUpSheetContent({this.onSuccess, required this.onClose});

  @override
  State<_SignUpSheetContent> createState() => _SignUpSheetContentState();
}

class _SignUpSheetContentState extends State<_SignUpSheetContent> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('Invalid login credentials')) return 'Invalid email or password. Please try again.';
    if (msg.contains('User already registered')) return 'An account with this email already exists. Try signing in.';
    if (msg.contains('Password should be at least')) return 'Password must be at least 6 characters.';
    if (msg.contains('Unable to validate email')) return 'Please enter a valid email address.';
    if (msg.contains('Email rate limit exceeded')) return 'Too many attempts. Please wait a moment and try again.';
    if (msg.contains('Connection timed out') || msg.contains('TimeoutException')) return 'Connection timed out. Check your network and try again.';
    return msg.replaceFirst('AuthException: ', '').replaceFirst('Exception: ', '');
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email and password are required.');
      return;
    }
    setState(() { _error = null; _loading = true; });
    try {
      await FirebaseService.signUp(email, password).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Connection timed out. Check your network.'),
      );
      if (!mounted) return;
      setState(() => _loading = false);
      if (!mounted) return;
      if (FirebaseService.isSignedIn) {
        widget.onSuccess?.call();
        return;
      }
      setState(() => _error = 'Account created! Check your email to confirm, then sign in.');
    } catch (e) {
      if (mounted) setState(() { _error = _friendlyError(e); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Join Potluck',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kCharcoal),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                  color: kCharcoal,
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Get cooking in seconds',
                    style: TextStyle(fontSize: 14, color: kSoftSlateGray),
                  ),
                  const SizedBox(height: 24),
                  if (_error != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined, size: 20),
                      filled: true,
                      fillColor: kBoneCreame.withOpacity(0.4),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kMutedGold.withOpacity(0.3))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kMutedGold.withOpacity(0.3))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kDeepForestGreen, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 20),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      filled: true,
                      fillColor: kBoneCreame.withOpacity(0.4),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kMutedGold.withOpacity(0.3))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kMutedGold.withOpacity(0.3))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kDeepForestGreen, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _loading ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: kMutedGold,
                        foregroundColor: kDeepForestGreen,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _loading
                          ? SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: kDeepForestGreen))
                          : const Text('Join', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kDeepForestGreen)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: widget.onClose,
                    child: Text.rich(
                      TextSpan(
                        text: 'Already have an account? ',
                        style: TextStyle(color: kSoftSlateGray, fontSize: 14),
                        children: [
                          TextSpan(text: 'Sign In', style: const TextStyle(color: kDeepForestGreen, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================= CHEF IDENTITY SCREEN (Phase 2: Post-Signup) =================
class ChefIdentityScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const ChefIdentityScreen({super.key, required this.onComplete});

  @override
  State<ChefIdentityScreen> createState() => _ChefIdentityScreenState();
}

class _ChefIdentityScreenState extends State<ChefIdentityScreen> {
  final _handleController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _saving = false;
  String? _error;

  static const _potluckAdjectives = [
    'Spicy', 'Golden', 'Crispy', 'Savory', 'Smoky', 'Zesty', 'Tangy',
    'Sweet', 'Toasty', 'Sizzling', 'Fresh', 'Rustic', 'Velvet', 'Herby',
    'Mellow', 'Peppered', 'Roasted', 'Honeyed', 'Buttery', 'Wild',
  ];

  static const _potluckNouns = [
    'Basil', 'Gnocchi', 'Sage', 'Thyme', 'Mango', 'Truffle', 'Paprika',
    'Saffron', 'Olive', 'Fennel', 'Clove', 'Nutmeg', 'Rosemary', 'Cinnamon',
    'Maple', 'Pecan', 'Walnut', 'Fig', 'Cardamom', 'Lavender',
  ];

  @override
  void initState() {
    super.initState();
    _prefillFromEmail();
  }

  void _prefillFromEmail() {
    final email = FirebaseService.currentUser?.email ?? '';
    final local = email.split('@').first;
    final cleaned = local.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    _handleController.text = cleaned;
    final display = local
        .replaceAll(RegExp(r'[._-]+'), ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
    _displayNameController.text = display;
  }

  void _shuffle() {
    final rng = Random();
    final adj = _potluckAdjectives[rng.nextInt(_potluckAdjectives.length)];
    final noun = _potluckNouns[rng.nextInt(_potluckNouns.length)];
    setState(() {
      _handleController.text = '$adj$noun';
    });
  }

  @override
  void dispose() {
    _handleController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final handle = _handleController.text.trim();
    final displayName = _displayNameController.text.trim();
    if (handle.isEmpty) {
      setState(() => _error = 'Username cannot be empty.');
      return;
    }
    if (handle.contains(' ')) {
      setState(() => _error = 'Username cannot contain spaces.');
      return;
    }
    setState(() { _error = null; _saving = true; });
    try {
      final uid = FirebaseService.currentUser?.uid;
      if (uid == null) return;
      await FirebaseService.updateProfile(
        userId: uid,
        username: handle,
        displayName: displayName.isEmpty ? handle : displayName,
      );
      if (mounted) widget.onComplete();
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        if (msg.contains('duplicate') || msg.contains('unique')) {
          setState(() { _error = 'That username is taken. Try another!'; _saving = false; });
        } else {
          setState(() { _error = msg.replaceFirst('PostgrestException: ', ''); _saving = false; });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBoneCreame,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              32, 48, 32, MediaQuery.of(context).viewInsets.bottom + 32,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: kDeepForestGreen.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.restaurant_menu, color: kDeepForestGreen, size: 40),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Create your Chef Identity',
                  style: TextStyle(
                    fontFamily: 'Lora', fontSize: 26, fontWeight: FontWeight.bold,
                    color: kDeepForestGreen,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pick a username and display name for your profile.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: kSoftSlateGray),
                ),
                const SizedBox(height: 32),

                if (_error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                  ),

                // Username / handle
                TextField(
                  controller: _handleController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    prefixText: '@',
                    prefixStyle: const TextStyle(color: kDeepForestGreen, fontWeight: FontWeight.w600),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.casino, color: kMutedGold, size: 22),
                      tooltip: 'Shuffle',
                      onPressed: _shuffle,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: kMutedGold.withOpacity(0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: kMutedGold.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kDeepForestGreen, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Unique handle for tagging & following',
                    style: TextStyle(fontSize: 12, color: kSoftSlateGray),
                  ),
                ),
                const SizedBox(height: 18),

                // Display name
                TextField(
                  controller: _displayNameController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    labelText: 'Display Name',
                    prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: kMutedGold.withOpacity(0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: kMutedGold.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kDeepForestGreen, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'What people see on your profile (can be anything)',
                    style: TextStyle(fontSize: 12, color: kSoftSlateGray),
                  ),
                ),
                const SizedBox(height: 28),

                // Continue button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: kDeepForestGreen,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 22, width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            "Let's Cook!",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  late List<Ingredient> _sharedIngredients;
  late UserProfile _userProfile;
  late List<CommunityReview> _communityReviews;
  Set<String> _dismissedRestockIds =
      {}; // Track dismissed restock items for badge count
  Set<String> _selectedIngredientIds =
      {}; // Track selected ingredients for recipe search
  Timer? _pantrySaveTimer;
  /// authorId -> list of userIds who follow that author (for Followers count, local-only)
  Map<String, List<String>> _authorFollowers = {};
  /// When signed in to Firebase, follower count from profiles.follower_count
  int? _firebaseFollowerCount;
  /// When signed in, set of profile ids the current user follows (for quick-add check)
  Set<String> _firebaseFollowingIds = {};

  @override
  void initState() {
    super.initState();
    _sharedIngredients = [];
    _userProfile = UserProfile(
      userId: '1',
      userName: 'Laura Huynh',
      recipesCookedCount: 12,
      estimatedMoneySaved: 87.50,
    );
    _communityReviews = [];
    _loadPantryIngredients();
    _loadUserProfile();
    _loadDismissedRestockIds();
    _clearStaleRecipeDataCache();
    _syncFirebaseAuth();
    FirebaseService.authStateChanges.listen((_) => _syncFirebaseAuth());
  }

  Future<void> _syncFirebaseAuth() async {
    final user = FirebaseService.currentUser;
    if (user == null) {
      setState(() {
        _firebaseFollowerCount = null;
        _firebaseFollowingIds = {};
      });
      return;
    }
    try {
      final profile = await FirebaseService.getProfile(user.uid);
      if (profile == null) return;
      final username = profile['username'] as String? ?? user.email ?? 'User';
      final avatarUrl = profile['avatar_url'] as String?;
      final followerCount = profile['follower_count'] as int? ?? 0;
      final followingIds = await FirebaseService.getFollowingIds();
      setState(() {
        _userProfile = _userProfile.copyWith(
          userId: user.uid,
          userName: username,
          avatarUrl: avatarUrl,
        );
        _firebaseFollowerCount = followerCount;
        _firebaseFollowingIds = followingIds;
      });
    } catch (_) {}
  }

  /// One-time clear of recipe data caches to purge entries with wrong units.
  /// Uses a version flag so it only runs once.
  Future<void> _clearStaleRecipeDataCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const versionKey = 'recipe_data_cache_version';
      const currentVersion = 4; // bump this to force a re-clear
      final storedVersion = prefs.getInt(versionKey) ?? 0;
      if (storedVersion < currentVersion) {
        await RecipeDataService.clearAllCaches();
        // Also clear old service caches
        await RecipeInstructionService.clearAllCaches();
        await RecipeIngredientService.clearAllCaches();
        await prefs.setInt(versionKey, currentVersion);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pantrySaveTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDismissedRestockIds() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getStringList('dismissed_restock_ids') ?? [];
    setState(() {
      _dismissedRestockIds = Set<String>.from(dismissed);
    });
  }

  Future<void> _loadPantryIngredients() async {
    final prefs = await SharedPreferences.getInstance();
    final ingredientsJson = prefs.getStringList('pantry_ingredients') ?? [];

    setState(() {
      _sharedIngredients = ingredientsJson.map((json) {
        try {
          final data = jsonDecode(json) as Map<String, dynamic>;

          final unitType = UnitType.values.firstWhere(
            (u) => u.name == data['unitType'],
          );

          dynamic amount;
          if (unitType == UnitType.volume) {
            amount = double.parse(data['amount'].toString());
          } else {
            final parsed = double.tryParse(data['amount'].toString()) ?? 0.0;
            amount = parsed == parsed.roundToDouble() ? parsed.toInt() : parsed;
          }

          final category = IngredientCategory.values.firstWhere(
            (c) => c.name == data['category'],
            orElse: () => IngredientCategory.produce,
          );

          return Ingredient(
            id: data['id'] as String,
            name: data['name'] as String,
            imageId: data['imageId'] as String?,
            category: category,
            unitType: unitType,
            amount: amount,
            baseUnit: data['baseUnit'] as String,
            isSelected: data['isSelected'] as bool? ?? false,
            isPriority: data['isPriority'] as bool? ?? false,
            isAvoided: data['isAvoided'] as bool? ?? false,
            isAllergy: data['isAllergy'] as bool? ?? false,
          );
        } catch (e) {
          rethrow;
        }
      }).toList();
    });
  }

  Future<void> _savePantryIngredients() async {
    try {
      // Prepare data on main thread (lightweight)
      final ingredientsData = _sharedIngredients
          .map(
            (ing) => {
              'id': ing.id,
              'name': ing.name,
              'imageId': ing.imageId,
              'category': ing.category.name,
              'unitType': ing.unitType.name,
              'amount': ing.amount,
              'baseUnit': ing.baseUnit,
              'isSelected': ing.isSelected,
              'isPriority': ing.isPriority,
              'isAvoided': ing.isAvoided,
              'isAllergy': ing.isAllergy,
            },
          )
          .toList();

      // Do expensive JSON encoding in background
      final ingredientsJson = await compute(
        _encodeIngredientsInBackground,
        ingredientsData,
      );

      // Save to SharedPreferences (fast operation)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('pantry_ingredients', ingredientsJson);
    } catch (e) {
      // Silently fail to avoid blocking UI
      debugPrint('Error saving pantry ingredients: $e');
    }
  }

  /// Clean up expired AWS signed S3 URLs used for recipe images.
  ///
  /// Edamam S3 URLs include a time‑limited signature (`X-Amz-` query params).
  /// Instead of eagerly stripping them (which caused images to disappear
  /// immediately after app restart), we now:
  /// - Keep the URL as‑is when it still returns HTTP 200
  /// - Only clear it when we've confirmed the URL is no longer valid
  /// - Fail open (keep URL) on network errors/timeouts so offline users
  ///   still see images when they become reachable again.
  Future<void> _replaceSignedUrlWithFallback(
    Map<String, dynamic> recipe,
  ) async {
    final url = recipe['imageUrl'] as String?;
    if (url == null || url.isEmpty) return;

    // Only inspect signed S3 URLs; local file paths and regular HTTPS images
    // are left untouched.
    if (!url.contains('X-Amz-')) return;

    try {
      final response = await http
          .head(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      // If the signed URL is no longer valid (e.g., 403/404), clear it so
      // UI components fall back to their placeholder image.
      if (response.statusCode != 200) {
        recipe['imageUrl'] = '';
      }
    } catch (_) {
      // On any failure (offline, timeout, parse error), keep the URL as-is.
      // Image widgets already have error builders to handle broken URLs.
    }
  }

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();

    // Load saved recipes
    final savedRecipeIds = prefs.getStringList('saved_recipe_ids') ?? [];
    // Load cooked recipes
    final cookedRecipeIds = prefs.getStringList('cooked_recipe_ids') ?? [];

    // Load persisted recipe data (survives app restart)
    final savedRecipeDataJson = prefs.getStringList('saved_recipe_data') ?? [];
    final cookedRecipeDataJson =
        prefs.getStringList('cooked_recipe_data') ?? [];

    // Restore recipe data to the static caches (saved/cooked keep persisted imageUrl e.g. local path)
    for (final json in savedRecipeDataJson) {
      try {
        final data = jsonDecode(json) as Map<String, dynamic>;
        await _replaceSignedUrlWithFallback(data);
        final id = data['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final existingIndex = _RecipeFeedScreenState._fetchedRecipesCache
            .indexWhere((r) => r['id']?.toString() == id);
        if (existingIndex >= 0) {
          // Overwrite so persisted data (e.g. local image path) is used in Profile
          _RecipeFeedScreenState._fetchedRecipesCache[existingIndex] = data;
        } else {
          _RecipeFeedScreenState._fetchedRecipesCache.add(data);
        }
      } catch (e) {
        // ignore: empty catch blocks
      }
    }
    for (final json in cookedRecipeDataJson) {
      try {
        final data = jsonDecode(json) as Map<String, dynamic>;
        await _replaceSignedUrlWithFallback(data);
        final id = data['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final existingIndex = _RecipeFeedScreenState._fetchedRecipesCache
            .indexWhere((r) => r['id']?.toString() == id);
        if (existingIndex >= 0) {
          _RecipeFeedScreenState._fetchedRecipesCache[existingIndex] = data;
        } else {
          _RecipeFeedScreenState._fetchedRecipesCache.add(data);
        }
      } catch (e) {
        // ignore: empty catch blocks
      }
    }

    // Load dietary preferences
    final allergies = prefs.getStringList('allergies') ?? [];
    final avoided = prefs.getStringList('avoided') ?? [];
    final lifestyles = prefs.getStringList('lifestyles') ?? [];
    final customRestrictions = prefs.getStringList('custom_restrictions') ?? [];

    // Load custom lifestyles
    final customLifestylesJson = prefs.getStringList('custom_lifestyles') ?? [];
    final customLifestyles = customLifestylesJson
        .map((json) => CustomLifestyle.fromJson(jsonDecode(json)))
        .toList();

    // Load active custom lifestyles
    final activeCustomLifestyles =
        prefs.getStringList('active_custom_lifestyles') ?? [];

    // Load author followers (who quick-added whom)
    Map<String, List<String>> authorFollowers = {};
    try {
      final followersJson = prefs.getString('author_followers');
      if (followersJson != null) {
        final decoded = jsonDecode(followersJson) as Map<String, dynamic>;
        authorFollowers = decoded.map(
          (k, v) => MapEntry(k, List<String>.from((v as List).map((e) => e.toString()))),
        );
      }
    } catch (_) {}

    setState(() {
      _authorFollowers = authorFollowers;
      _userProfile = _userProfile.copyWith(
        savedRecipeIds: savedRecipeIds,
        cookedRecipeIds: cookedRecipeIds,
        allergies: Set<String>.from(allergies),
        avoided: Set<String>.from(avoided),
        selectedLifestyles: Set<String>.from(lifestyles),
        customRestrictions: customRestrictions,
        customLifestyles: customLifestyles,
        activeCustomLifestyles: Set<String>.from(activeCustomLifestyles),
      );
    });
  }

  Future<void> _saveAuthorFollowers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('author_followers', jsonEncode(_authorFollowers));
    } catch (_) {}
  }

  Future<void> _saveUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('saved_recipe_ids', _userProfile.savedRecipeIds);
    await prefs.setStringList(
      'cooked_recipe_ids',
      _userProfile.cookedRecipeIds,
    );

    // Persist actual recipe data for saved recipes (so they survive app restart)
    final savedRecipeData = <String>[];
    final cookedRecipeData = <String>[];

    // Load existing persisted recipe data to avoid dropping entries
    final existingSavedDataJson =
        prefs.getStringList('saved_recipe_data') ?? [];
    final existingCookedDataJson =
        prefs.getStringList('cooked_recipe_data') ?? [];

    Map<String, String> buildExistingMap(List<String> jsonList) {
      final map = <String, String>{};
      for (final raw in jsonList) {
        try {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          final id = decoded['id']?.toString();
          if (id != null && id.isNotEmpty) {
            map[id] = raw;
          }
        } catch (_) {
          // Ignore invalid entries
        }
      }
      return map;
    }

    final existingSavedMap = buildExistingMap(existingSavedDataJson);
    final existingCookedMap = buildExistingMap(existingCookedDataJson);

    // Get all available recipe data
    final allRecipeMaps = [
      ..._RecipeFeedScreenState._userRecipes,
      ..._RecipeFeedScreenState._fetchedRecipesCache,
    ];

    // Save data for saved recipes
    for (final id in _userProfile.savedRecipeIds) {
      final recipe = allRecipeMaps.firstWhere(
        (r) => r['id'] == id,
        orElse: () => <String, dynamic>{},
      );
      if (recipe.isNotEmpty) {
        final copy = Map<String, dynamic>.from(recipe);
        // Keep the original image URL as-is when saving
        // Only replace with fallback on load if the URL is actually broken
        savedRecipeData.add(jsonEncode(copy));
      } else if (existingSavedMap.containsKey(id)) {
        savedRecipeData.add(existingSavedMap[id]!);
      }
    }

    // Save data for cooked recipes
    for (final id in _userProfile.cookedRecipeIds) {
      final recipe = allRecipeMaps.firstWhere(
        (r) => r['id'] == id,
        orElse: () => <String, dynamic>{},
      );
      if (recipe.isNotEmpty) {
        final copy = Map<String, dynamic>.from(recipe);
        // Keep the original image URL as-is when saving
        // Only replace with fallback on load if the URL is actually broken
        cookedRecipeData.add(jsonEncode(copy));
      } else if (existingCookedMap.containsKey(id)) {
        cookedRecipeData.add(existingCookedMap[id]!);
      }
    }

    await prefs.setStringList('saved_recipe_data', savedRecipeData);
    await prefs.setStringList('cooked_recipe_data', cookedRecipeData);

    await prefs.setStringList('allergies', _userProfile.allergies.toList());
    await prefs.setStringList('avoided', _userProfile.avoided.toList());
    await prefs.setStringList(
      'lifestyles',
      _userProfile.selectedLifestyles.toList(),
    );
    await prefs.setStringList(
      'custom_restrictions',
      _userProfile.customRestrictions,
    );

    // Save custom lifestyles
    final customLifestylesJson = _userProfile.customLifestyles
        .map((cl) => jsonEncode(cl.toJson()))
        .toList();
    await prefs.setStringList('custom_lifestyles', customLifestylesJson);

    // Save active custom lifestyles
    await prefs.setStringList(
      'active_custom_lifestyles',
      _userProfile.activeCustomLifestyles.toList(),
    );
  }

  void _onProfileUpdated(UserProfile updatedProfile) {
    setState(() {
      _userProfile = updatedProfile;
    });
    _saveUserProfile();

    // Update ingredient flags
    _updateIngredientsFlags();
  }

  void _updateIngredientsFlags() {
    final updatedIngredients = _sharedIngredients.map((ing) {
      return ing.copyWith(
        isAllergy: _userProfile.allergies.contains(ing.name),
        isAvoided: _userProfile.avoided.contains(ing.name),
      );
    }).toList();

    setState(() {
      _sharedIngredients = updatedIngredients;
    });
  }

  void _onTabTapped(int index) {
    if (_currentIndex == index) return;

    setState(() {
      _currentIndex = index;
    });
  }

  // Removed _showAddPopupMenu; Add tab now directly shows AddIngredientScreen

  void _updateSharedIngredients(List<Ingredient> ingredients) {
    setState(() {
      _sharedIngredients = ingredients;
    });

    // Cancel previous timer and set new one for debounced saving
    _pantrySaveTimer?.cancel();
    _pantrySaveTimer = Timer(const Duration(seconds: 1), () {
      _savePantryIngredients();
    });
  }

  void _addCommunityReview(CommunityReview review) {
    setState(() {
      _communityReviews.add(review);
    });
  }

  void _addConfirmedIngredients(List<Ingredient> newIngredients) {
    setState(() {
      // Add confirmed ingredients to the shared list
      // Consolidate by name and baseUnit to avoid duplicates
      for (var newIng in newIngredients) {
        final existingIndex = _sharedIngredients.indexWhere(
          (ing) => ing.name == newIng.name && ing.baseUnit == newIng.baseUnit,
        );

        if (existingIndex != -1) {
          // Ingredient already exists, update quantity
          _sharedIngredients[existingIndex] = _sharedIngredients[existingIndex]
              .copyWith(
                amount:
                    _sharedIngredients[existingIndex].amount + newIng.amount,
              );
        } else {
          // New ingredient, add it
          _sharedIngredients.add(newIng);
        }
      }
    });

    // Cancel previous timer and set new one for debounced saving
    _pantrySaveTimer?.cancel();
    _pantrySaveTimer = Timer(const Duration(seconds: 1), () {
      _savePantryIngredients();
    });
  }

  void _restockIngredient(String ingredientId) {
    setState(() {
      final index = _sharedIngredients.indexWhere(
        (ing) => ing.id == ingredientId,
      );
      if (index != -1) {
        final ing = _sharedIngredients[index];
        final newAmount = switch (ing.unitType) {
          UnitType.volume => 1.0,
          UnitType.count => 5,
          UnitType.weight => 500,
        };
        _sharedIngredients[index] = ing.copyWith(amount: newAmount);
      }
    });
  }

  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return PantryScreen(
          key: const PageStorageKey('PantryScreen'),
          onIngredientsUpdated: _updateSharedIngredients,
          sharedIngredients: _sharedIngredients,
          selectedIngredientIds: _selectedIngredientIds,
          onSelectionChanged: (ids) {
            setState(() {
              _selectedIngredientIds = ids;
            });
          },
          onFindRecipes: () {
            setState(() {
              _currentIndex = 1;
            });
          },
        );
      case 1:
        return RecipeFeedScreen(
          key: const PageStorageKey('RecipeFeedScreen'),
          sharedIngredients: _sharedIngredients,
          onIngredientsUpdated: _updateSharedIngredients,
          userProfile: _userProfile,
          onProfileUpdated: _onProfileUpdated,
          onAddCommunityReview: _addCommunityReview,
          communityReviews: _communityReviews,
          dismissedRestockIds: _dismissedRestockIds,
          selectedIngredientIds: _selectedIngredientIds,
          onClearSelection: () {
            setState(() {
              _selectedIngredientIds = {};
            });
          },
          onFollowAuthor: (authorId) async {
            if (authorId == null || authorId.isEmpty || authorId == _userProfile.userId) return;
            if (FirebaseService.isSignedIn && FirebaseService.isFirebaseUserId(authorId)) {
              await FirebaseService.follow(authorId);
              setState(() => _firebaseFollowingIds.add(authorId));
              return;
            }
            setState(() {
              _authorFollowers.putIfAbsent(authorId, () => []);
              if (!_authorFollowers[authorId]!.contains(_userProfile.userId)) {
                _authorFollowers[authorId]!.add(_userProfile.userId);
              }
              _saveAuthorFollowers();
            });
          },
          isFollowingAuthor: (id) {
            if (id == null) return false;
            if (_authorFollowers[id]?.contains(_userProfile.userId) ?? false) return true;
            if (FirebaseService.isFirebaseUserId(id) && _firebaseFollowingIds.contains(id)) return true;
            return false;
          },
        );
      case 2:
        return AddIngredientScreen(
          key: const PageStorageKey('AddIngredientScreen'),
          onSwitchTab: _onTabTapped,
          onAddIngredients: _addConfirmedIngredients,
        );
      case 3:
        return ShoppingListScreen(
          key: const PageStorageKey('ShoppingListScreen'),
          pantryIngredients: _sharedIngredients,
          onRestock: _restockIngredient,
          onAddIngredients: _addConfirmedIngredients,
          onDismissRestock: (itemId) {
            setState(() {
              _dismissedRestockIds.add(itemId);
            });
          },
        );
      case 4:
        return HubScreen(
          key: const PageStorageKey('HubScreen'),
          pantryIngredients: _sharedIngredients,
          onIngredientsUpdated: _updateSharedIngredients,
          userProfile: _userProfile,
          onProfileUpdated: _onProfileUpdated,
          onAddCommunityReview: _addCommunityReview,
          communityReviews: _communityReviews,
          followerCount: _firebaseFollowerCount ?? _authorFollowers[_userProfile.userId]?.length ?? 0,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shoppingListCount = _sharedIngredients
        .where(
          (ing) => ing.needsPurchase && !_dismissedRestockIds.contains(ing.id),
        )
        .length;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: List.generate(5, (index) => _buildScreen(index)),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 80,
              child: PotluckNavigationBar(
                currentIndex: _currentIndex,
                onTap: _onTabTapped,
                shoppingListCount: shoppingListCount,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================= POTLUCK NAVIGATION BAR =================
class PotluckNavigationBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final int shoppingListCount;

  const PotluckNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.shoppingListCount = 0,
  });

  static const List<_NavTab> tabs = [
    _NavTab(
      icon: Icons.kitchen_outlined,
      activeIcon: Icons.kitchen,
      label: 'PANTRY',
    ),
    _NavTab(
      icon: Icons.restaurant_outlined,
      activeIcon: Icons.restaurant,
      label: 'POTLUCK',
    ),
    _NavTab(
      icon: Icons.add_circle_outline,
      activeIcon: Icons.add_circle,
      label: 'ADD',
      isCenter: true,
    ),
    _NavTab(
      icon: Icons.shopping_cart_outlined,
      activeIcon: Icons.shopping_cart,
      label: 'SHOP',
    ),
    _NavTab(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'PROFILE',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            tabs.length,
            (index) => _buildTab(tabs[index], index, index == currentIndex),
          ),
        ),
      ),
    );
  }

  Widget _buildTab(_NavTab tab, int index, bool isActive) {
    // Use fixed-width tabs so we can center the row and cluster items
    // Slightly increase non-center tab width and horizontal padding
    final double tabWidth = tab.isCenter ? 72.0 : 62.0;
    return SizedBox(
      width: tabWidth,
      child: GestureDetector(
        onTap: () => onTap(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: tab.isCenter ? 56 : 40,
                    height: tab.isCenter ? 56 : 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tab.isCenter
                          ? kMutedGold
                          : (isActive ? Colors.black12 : Colors.transparent),
                    ),
                    alignment: Alignment.center,
                    child: tab.isCenter
                        ? Text(
                            '+',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.normal,
                              color: kDeepForestGreen,
                              height: 0.5,
                            ),
                          )
                        : Icon(
                            isActive ? tab.activeIcon : tab.icon,
                            color: kDeepForestGreen,
                            size: 24,
                          ),
                  ),
                  if (index == 3 && shoppingListCount > 0) ...[
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: Color.fromARGB(255, 255, 253, 253),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          shoppingListCount.toString(),
                          style: const TextStyle(
                            color: Color.fromARGB(255, 82, 77, 77),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (!tab.isCenter) ...[
                const SizedBox(height: 0),
                Text(
                  tab.label.toUpperCase(),
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: isActive
                        ? const Color.fromARGB(255, 16, 21, 20)
                        : const Color.fromARGB(255, 49, 72, 66),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTab {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isCenter;

  const _NavTab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.isCenter = false,
  });
}

// ================= 1. PANTRY SCREEN =================
class PantryScreen extends StatefulWidget {
  final Function(List<Ingredient>)? onIngredientsUpdated;
  final List<Ingredient> sharedIngredients;
  final Set<String> selectedIngredientIds;
  final Function(Set<String>) onSelectionChanged;
  final VoidCallback onFindRecipes;

  const PantryScreen({
    super.key,
    this.onIngredientsUpdated,
    required this.sharedIngredients,
    required this.selectedIngredientIds,
    required this.onSelectionChanged,
    required this.onFindRecipes,
  });

  @override
  State<PantryScreen> createState() => _PantryScreenState();
}

class _PantryScreenState extends State<PantryScreen> {
  final List<FridgeImage> _fridgeImages = [];
  // State for search and category filter
  String _searchQuery = '';
  IngredientCategory? _selectedCategory;
  final TextEditingController _searchController = TextEditingController();
  bool _isSelectionMode = false;
  Timer? _saveTimer;

  @override
  void dispose() {
    _searchController.dispose();
    _saveTimer?.cancel();
    super.dispose();
  }

  // AI-powered ingredient detection - uses Google Generative AI
  Future<void> _extractIngredientsAutomatically(FridgeImage fridgeImage) async {
    // Create a loading dialog overlay with CircularProgressIndicator
    final loadingDialogContext = context;
    showDialog(
      context: loadingDialogContext,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Analyzing image with AI...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // Use centralized API key from GeminiConfig (supports environment variables)
      const String apiKey = GeminiConfig.apiKey;

      // Check if API key is configured
      if (apiKey.isEmpty || apiKey == 'YOUR_GOOGLE_GENERATIVE_AI_API_KEY') {
        if (!mounted) return;
        Navigator.pop(context); // Close loading dialog
        return;
      }

      final detectionService = IngredientDetectionService(apiKey: apiKey);

      // Detect ingredients from image using AI
      final detectedIngredients = await detectionService
          .detectIngredientsFromImage(fridgeImage.imageFile);

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      // If no ingredients detected, show message
      if (detectedIngredients.isEmpty) {
        return;
      }

      // Associate detected ingredients with the image
      final ingredientsWithImageId = detectedIngredients
          .map((ing) => ing.copyWith(imageId: fridgeImage.id))
          .toList();

      // Show Review Scan modal to let user confirm/edit detected ingredients
      if (mounted) {
        _showReviewScanModal(fridgeImage, ingredientsWithImageId);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
    }
  }

  void _showReviewScanModal(
    FridgeImage fridgeImage,
    List<Ingredient> detectedIngredients,
  ) {
    final reviewIngredients = List<Ingredient>.from(detectedIngredients);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            // HEADER: Grabber bar + Title
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(70),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    // Grabber bar
                    Padding(
                      padding: const EdgeInsets.only(top: 10.0, bottom: 8.0),
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2.5),
                          ),
                        ),
                      ),
                    ),
                    // Header title + close button
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Review Detected Items',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: kCharcoal,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                            color: kCharcoal,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // BODY: Scrollable ingredient list (center, like Instagram Comments)
            body: Container(
              color: Colors.white,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                itemCount: reviewIngredients.length,
                itemBuilder: (context, index) {
                  return _buildReviewIngredientTile(
                    reviewIngredients[index],
                    index,
                    reviewIngredients,
                    setModalState,
                  );
                },
              ),
            ),
            // BOTTOM BAR: Fixed Cancel and Confirm buttons (NEVER SCROLLS)
            bottomNavigationBar: Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: kDeepForestGreen),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: kDeepForestGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _confirmAndAddIngredients(
                          fridgeImage,
                          reviewIngredients,
                        );
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kSageGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Confirm',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReviewIngredientTile(
    Ingredient ingredient,
    int index,
    List<Ingredient> reviewIngredients,
    StateSetter setModalState,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ingredient name and remove button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  ingredient.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: kCharcoal,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: kSoftTerracotta),
                onPressed: () {
                  setModalState(() {
                    reviewIngredients.removeAt(index);
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Unit selector row
          Row(
            children: [
              Expanded(
                child: _buildUnitSelector(index, ingredient, setModalState),
              ),
              const SizedBox(width: 12),
              // Quantity adjuster
              _buildQuantityAdjuster(
                ingredient,
                index,
                reviewIngredients,
                setModalState,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUnitSelector(
    int index,
    Ingredient ingredient,
    StateSetter setModalState,
  ) {
    // Unit selector removed - units no longer managed in pantry
    return const SizedBox.shrink();
  }

  Widget _buildQuantityAdjuster(
    Ingredient ingredient,
    int index,
    List<Ingredient> reviewIngredients,
    StateSetter setModalState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Qty',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            GestureDetector(
              onTap: () {
                setModalState(() {
                  dynamic newAmount;
                  if (ingredient.unitType == UnitType.volume) {
                    newAmount = ((ingredient.amount as double) - 0.1).clamp(
                      0.0,
                      1.0,
                    );
                  } else {
                    newAmount = (amountAsInt(ingredient.amount) - 1).clamp(
                      0,
                      999,
                    );
                  }
                  reviewIngredients[index] = ingredient.copyWith(
                    amount: newAmount,
                  );
                });
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  border: Border.all(color: kSageGreen),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.remove, size: 16, color: kSageGreen),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 40,
              child: Text(
                ingredient.unitType == UnitType.volume
                    ? (() {
                        final amount = ingredient.amount as double;
                        // Remove .0 from whole numbers
                        if (amount == amount.round()) {
                          return amount.round().toString();
                        }
                        return amount.toStringAsFixed(1);
                      })()
                    : ingredient.amount.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                setModalState(() {
                  dynamic newAmount;
                  if (ingredient.unitType == UnitType.volume) {
                    newAmount = ((ingredient.amount as double) + 0.1).clamp(
                      0.0,
                      1.0,
                    );
                  } else {
                    newAmount = (amountAsInt(ingredient.amount) + 1).clamp(
                      0,
                      999,
                    );
                  }
                  reviewIngredients[index] = ingredient.copyWith(
                    amount: newAmount,
                  );
                });
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  border: Border.all(color: kSageGreen),
                  borderRadius: BorderRadius.circular(6),
                  color: kSageGreen.withOpacity(0.1),
                ),
                child: const Icon(Icons.add, size: 16, color: kSageGreen),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _confirmAndAddIngredients(
    FridgeImage fridgeImage,
    List<Ingredient> reviewIngredients,
  ) {
    if (reviewIngredients.isEmpty) {
      return;
    }

    setState(() {
      // Update fridge image with extracted ingredients
      final imageIndex = _fridgeImages.indexWhere(
        (img) => img.id == fridgeImage.id,
      );
      if (imageIndex != -1) {
        _fridgeImages[imageIndex] = _fridgeImages[imageIndex].copyWith(
          ingredients: reviewIngredients.map((ing) => ing.name).toList(),
        );
      }

      // Add to pantry - merge by ingredient name to avoid duplicates
      for (var ingredient in reviewIngredients) {
        final existingIndex = widget.sharedIngredients.indexWhere(
          (ing) => ing.name == ingredient.name,
        );

        if (existingIndex != -1) {
          // Ingredient already exists - merge the amounts
          final existing = widget.sharedIngredients[existingIndex];
          if (ingredient.unitType == existing.unitType &&
              ingredient.baseUnit == existing.baseUnit) {
            // Same unit type and base unit - combine amounts
            dynamic newAmount;
            if (ingredient.unitType == UnitType.volume) {
              newAmount =
                  ((existing.amount as double) + (ingredient.amount as double))
                      .clamp(0.0, 1.0);
            } else {
              final existingAmount = amountAsDouble(existing.amount);
              final addedAmount = amountAsDouble(ingredient.amount);
              final summed = existingAmount + addedAmount;
              newAmount =
                  ingredient.unitType == UnitType.count &&
                      summed == summed.roundToDouble()
                  ? summed.toInt()
                  : summed;
            }
            widget.sharedIngredients[existingIndex] = existing.copyWith(
              amount: newAmount,
            );
          } else {
            // Different units - don't merge, just add as is
            widget.sharedIngredients.add(ingredient);
          }
        } else {
          // New ingredient - add it
          widget.sharedIngredients.add(ingredient);
        }
      }

      // Clear the scanned image after confirming (UI cleanup)
      _fridgeImages.removeWhere((img) => img.id == fridgeImage.id);
    });

    _notifyIngredientsUpdated();
  }

  void _deleteImage(String imageId) {
    setState(() {
      _fridgeImages.removeWhere((img) => img.id == imageId);
      // Keep ingredients even after deleting the image
      // Just clear the imageId reference so they're no longer tied to this scan
      for (int i = 0; i < widget.sharedIngredients.length; i++) {
        if (widget.sharedIngredients[i].imageId == imageId) {
          widget.sharedIngredients[i] = widget.sharedIngredients[i].copyWith(
            imageId: null,
          );
        }
      }
    });
  }

  void _deleteIngredient(String ingredientId) {
    setState(() {
      widget.sharedIngredients.removeWhere((ing) => ing.id == ingredientId);
    });
    _notifyIngredientsUpdated();
  }

  void _notifyIngredientsUpdated() {
    // Cancel previous timer
    _saveTimer?.cancel();

    // Set a new timer to save after 1 second of inactivity
    _saveTimer = Timer(const Duration(seconds: 1), () {
      widget.onIngredientsUpdated?.call(
        List<Ingredient>.from(widget.sharedIngredients),
      );
    });
  }

  void _showAddIngredientDialog(FridgeImage fridgeImage) {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Ingredient'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter ingredient name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              _addIngredientManually(fridgeImage, value.trim());
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final ingredient = controller.text.trim();
              if (ingredient.isNotEmpty) {
                _addIngredientManually(fridgeImage, ingredient);
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: kSageGreen),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _addIngredientManually(FridgeImage fridgeImage, String ingredientName) {
    setState(() {
      // Check if ingredient already exists in this image
      final existingIngredients = _fridgeImages
          .firstWhere((img) => img.id == fridgeImage.id)
          .ingredients;

      if (!existingIngredients.contains(ingredientName)) {
        // Update the fridge image with the new ingredient
        final index = _fridgeImages.indexWhere(
          (img) => img.id == fridgeImage.id,
        );
        if (index != -1) {
          _fridgeImages[index] = _fridgeImages[index].copyWith(
            ingredients: [...existingIngredients, ingredientName],
          );
        }
      }

      // Add to main ingredients list if it doesn't exist
      if (!widget.sharedIngredients.any((ing) => ing.name == ingredientName)) {
        widget.sharedIngredients.add(
          Ingredient(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: ingredientName,
            imageId: fridgeImage.id,
            category: IngredientCategory.produce,
            unitType: UnitType.count,
            amount: 1,
            baseUnit: 'ea',
          ),
        );
      }
    });

    _notifyIngredientsUpdated();
  }

  @override
  Widget build(BuildContext context) {
    // Separate active ingredients from those needing purchase
    var activeIngredients = widget.sharedIngredients
        .where((ing) => !ing.needsPurchase)
        .toList();

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      activeIngredients = activeIngredients
          .where(
            (ing) =>
                ing.name.toLowerCase().contains(_searchQuery.toLowerCase()),
          )
          .toList();
    }

    // Apply category filter
    if (_selectedCategory != null) {
      activeIngredients = activeIngredients
          .where((ing) => ing.category == _selectedCategory)
          .toList();
    }

    // Group active ingredients by category
    final groupedByCategory = <IngredientCategory, List<Ingredient>>{};
    for (var ingredient in activeIngredients) {
      groupedByCategory
          .putIfAbsent(ingredient.category, () => [])
          .add(ingredient);
    }

    // Count items per category (from all active, not filtered)
    final allActiveIngredients = widget.sharedIngredients
        .where((ing) => !ing.needsPurchase)
        .toList();
    final categoryCounts = <IngredientCategory, int>{};
    for (var ingredient in allActiveIngredients) {
      categoryCounts.update(
        ingredient.category,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    // Define category order once for consistent display ordering
    final categoryOrder = [
      IngredientCategory.produce,
      IngredientCategory.proteins,
      IngredientCategory.dairyRefrigerated,
      IngredientCategory.grainsLegumes,
      IngredientCategory.cannedGoods,
      IngredientCategory.frozen,
      IngredientCategory.condimentsSauces,
      IngredientCategory.spicesSeasonings,
      IngredientCategory.baking,
      IngredientCategory.snacksExtras,
    ];

    // Only show categories that have items
    final categoriesWithItems = categoryOrder
        .where((cat) => (categoryCounts[cat] ?? 0) > 0)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSelectionMode
              ? '${widget.selectedIngredientIds.length} Selected'
              : 'My Pantry',
        ),
        actions: [
          if (!_isSelectionMode)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.rectangle,
                      color: Colors.white.withOpacity(0.75),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.85),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _isSelectionMode = true;
                        });
                      },
                      child: Text(
                        'Select',
                        style: TextStyle(
                          color: kDeepForestGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_isSelectionMode)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.rectangle,
                      color: Colors.white.withOpacity(0.75),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.85),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _isSelectionMode = false;
                          widget.onSelectionChanged({});
                        });
                      },
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: kDeepForestGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: widget.selectedIngredientIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: widget.onFindRecipes,
              backgroundColor: kDeepForestGreen,
              icon: const Icon(Icons.restaurant_menu, color: Colors.white),
              label: Text(
                'Find Recipes (${widget.selectedIngredientIds.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: widget.sharedIngredients.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.kitchen, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(
                      'No ingredients yet',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                // Search Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search ingredients...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: kDeepForestGreen,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                // Category Filter Row
                if (categoriesWithItems.isNotEmpty)
                  SizedBox(
                    height: 36,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(left: 20, right: 16),
                      itemCount:
                          categoriesWithItems.length + 1, // +1 for "All" chip
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          // "All" chip
                          final isSelected = _selectedCategory == null;
                          final totalCount = allActiveIngredients.length;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedCategory = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? kDeepForestGreen
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected
                                        ? kDeepForestGreen
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'All',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected
                                            ? Colors.white
                                            : kCharcoal,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.white.withOpacity(0.2)
                                            : kDeepForestGreen.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        totalCount.toString(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected
                                              ? Colors.white
                                              : kDeepForestGreen,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        final category = categoriesWithItems[index - 1];
                        final isSelected = _selectedCategory == category;
                        final count = categoryCounts[category] ?? 0;

                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedCategory = isSelected
                                    ? null
                                    : category;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? kDeepForestGreen
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? kDeepForestGreen
                                      : Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    category.displayName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? Colors.white
                                          : kCharcoal,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.white.withOpacity(0.2)
                                          : kDeepForestGreen.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      count.toString(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected
                                            ? Colors.white
                                            : kDeepForestGreen,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                // Ingredient List
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 140),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Active Ingredients with Categorized Chips
                          if (activeIngredients.isNotEmpty) ...[
                            // Display categories in order
                            ...categoryOrder
                                .where(
                                  (cat) => groupedByCategory.containsKey(cat),
                                )
                                .map((category) {
                                  final ingredients =
                                      groupedByCategory[category]!;

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        category.displayName,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: kDeepForestGreen,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          alignment: WrapAlignment.start,
                                          children: ingredients.map((
                                            ingredient,
                                          ) {
                                            return _buildIngredientChip(
                                              ingredient,
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                    ],
                                  );
                                }),
                          ] else if (_searchQuery.isNotEmpty ||
                              _selectedCategory != null) ...[
                            // Empty state when filters active but no results
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 40,
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.search_off,
                                      size: 48,
                                      color: Colors.grey.shade300,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No ingredients found',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _searchQuery = '';
                                          _searchController.clear();
                                          _selectedCategory = null;
                                        });
                                      },
                                      child: const Text('Clear filters'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          // Scanned Images Horizontal Reel
                          if (_fridgeImages.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Scanned Images',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: kCharcoal,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 120,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _fridgeImages.length,
                                itemBuilder: (context, index) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: _buildImageThumbnail(
                                      _fridgeImages[index],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildIngredientChip(Ingredient ingredient) {
    final isSelected = widget.selectedIngredientIds.contains(ingredient.id);

    return GestureDetector(
      onTap: _isSelectionMode
          ? () {
              // Toggle selection
              final newSelection = Set<String>.from(
                widget.selectedIngredientIds,
              );
              if (isSelected) {
                newSelection.remove(ingredient.id);
              } else {
                newSelection.add(ingredient.id);
              }
              widget.onSelectionChanged(newSelection);
            }
          : null, // Disable tap when not in selection mode
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
            // Checkmark for selected items
            if (isSelected) ...[
              Icon(Icons.check_circle, size: 16, color: kDeepForestGreen),
              const SizedBox(width: 6),
            ],
            // Ingredient name only
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
            // Delete button (X)
            GestureDetector(
              onTap: () => _deleteIngredient(ingredient.id),
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

  Widget _buildImageThumbnail(FridgeImage fridgeImage) {
    final ingredientsFromImage = widget.sharedIngredients
        .where((ing) => ing.imageId == fridgeImage.id)
        .length;

    return GestureDetector(
      onTap: () => _showScanReviewModal(fridgeImage),
      child: Column(
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  fridgeImage.imageFile,
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => _deleteImage(fridgeImage.id),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ingredientsFromImage > 0
                ? '$ingredientsFromImage item${ingredientsFromImage > 1 ? 's' : ''}'
                : 'Review',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: kCharcoal,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showScanReviewModal(FridgeImage fridgeImage) {
    final ingredientsFromImage = widget.sharedIngredients
        .where((ing) => ing.imageId == fridgeImage.id)
        .map((ing) => ing.name)
        .toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with close button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Scan Details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: kCharcoal,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Full-size image
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    fridgeImage.imageFile,
                    width: double.infinity,
                    height: 250,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 16),
                // Timestamp info
                Row(
                  children: [
                    Icon(
                      fridgeImage.source == ImageSource.camera
                          ? Icons.camera_alt
                          : Icons.photo_library,
                      size: 14,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      fridgeImage.timestamp.toString().split('.')[0],
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Ingredients section
                if (ingredientsFromImage.isNotEmpty) ...[
                  const Text(
                    'Ingredients from this scan:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: kCharcoal,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ingredientsFromImage
                        .map(
                          (ingredient) => Chip(
                            label: Text(ingredient),
                            backgroundColor: kSageGreen.withValues(alpha: 0.2),
                            labelStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showAddIngredientDialog(fridgeImage);
                      },
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Add More Ingredients'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kSageGreen,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ] else ...[
                  const Text(
                    'No ingredients extracted yet',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: kCharcoal,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _extractIngredientsAutomatically(fridgeImage);
                      },
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Auto Extract Ingredients'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kSageGreen,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ================= ADVANCED SEARCH PAGE =================
class AdvancedSearchPage extends StatefulWidget {
  final UserProfile userProfile;
  final Function(Map<String, dynamic>) onApplyFilters;

  const AdvancedSearchPage({
    super.key,
    required this.userProfile,
    required this.onApplyFilters,
  });

  @override
  State<AdvancedSearchPage> createState() => _AdvancedSearchPageState();
}

class _AdvancedSearchPageState extends State<AdvancedSearchPage> {
  late Set<String> _selectedDiets;
  late Set<String> _selectedIntolerances;
  late Set<String> _selectedCuisines;
  late Set<String> _selectedMealTypes;
  late Set<String> _selectedCookingMethods;
  late Set<String> _selectedMacroGoals;
  String _selectedPrepTime = '';
  late TextEditingController _searchController;
  String _searchQuery = '';

  final List<String> _diets = [
    'Vegan',
    'Vegetarian',
    'Ketogenic',
    'Paleo',
    'Pescatarian',
    'Gluten-Free',
    'Whole30',
  ];

  final List<String> _intolerances = [
    'Dairy',
    'Egg',
    'Gluten',
    'Peanut',
    'Seafood',
    'Sesame',
    'Shellfish',
    'Soy',
    'Sulfite',
    'Tree Nut',
    'Wheat',
  ];

  final List<String> _cuisines = [
    'Italian',
    'Mexican',
    'Asian',
    'Indian',
    'Mediterranean',
    'French',
    'Greek',
    'Spanish',
  ];

  final List<String> _mealTypes = [
    'Main Course',
    'Side Dish',
    'Dessert',
    'Appetizer',
    'Salad',
    'Breakfast',
    'Soup',
    'Beverage',
    'Fingerfood',
  ];

  final List<String> _prepTimes = [
    'Under 15 mins',
    'Under 30 mins',
    'Under 45 mins',
    'Slow Cook (1hr+)',
  ];

  final List<String> _cookingMethods = [
    'Air Fryer',
    'Slow Cooker',
    'One-Pot Meals',
    'Oven-Baked',
    'No-Cook',
  ];

  final List<String> _macroGoals = [
    'High Protein (20g+)',
    'Low Carb (20g-)',
    'Low Calorie (400-)',
    'Low Fat',
  ];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    // Pre-select from Profile
    _selectedDiets = Set<String>.from(
      widget.userProfile.selectedLifestyles.where(
        (l) => _diets.map((d) => d.toLowerCase()).contains(l),
      ),
    );
    _selectedIntolerances = Set<String>.from(widget.userProfile.allergies);
    _selectedCuisines = {};
    _selectedMealTypes = {};
    _selectedCookingMethods = {};
    _selectedMacroGoals = {};
    _selectedPrepTime = '';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    final filters = {
      'diets': _selectedDiets.toList(),
      'intolerances': _selectedIntolerances.toList(),
      'cuisines': _selectedCuisines.toList(),
      'mealTypes': _selectedMealTypes.toList(),
      'cookingMethods': _selectedCookingMethods.toList(),
      'macroGoals': _selectedMacroGoals.toList(),
      'prepTime': _selectedPrepTime,
      'searchQuery': _searchQuery,
    };
    widget.onApplyFilters(filters);
    Navigator.pop(context);
  }

  Widget _buildFilterSection(
    String title,
    List<String> items,
    Set<String> selected,
    bool isHighContrast,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: kDeepForestGreen,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((item) {
            final isSelected = selected.contains(item);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    selected.remove(item);
                  } else {
                    selected.add(item);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isHighContrast
                            ? Colors.red.shade100
                            : kSageGreen.withOpacity(0.2))
                      : Colors.grey.shade100,
                  border: Border.all(
                    color: isSelected
                        ? (isHighContrast ? Colors.red.shade400 : kSageGreen)
                        : Colors.grey.shade300,
                    width: isHighContrast && isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  item,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? (isHighContrast
                              ? Colors.red.shade700
                              : kDeepForestGreen)
                        : kSoftSlateGray,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced Search'),
        backgroundColor: kBoneCreame,
        foregroundColor: kDeepForestGreen,
      ),
      body: Stack(
        children: [
          // Scrollable filter content
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              20,
              20,
              20,
              100,
            ), // Extra bottom padding for floating button
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search bar for specific dishes
                TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search recipes...',
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: kDeepForestGreen, width: 2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: kDeepForestGreen, width: 2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: kDeepForestGreen,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: kBoneCreame.withOpacity(0.5),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: 24),
                _buildFilterSection(
                  'Diet & Lifestyle',
                  _diets,
                  _selectedDiets,
                  false,
                ),
                const SizedBox(height: 24),
                _buildFilterSection(
                  'Intolerances & Allergies',
                  _intolerances,
                  _selectedIntolerances,
                  true,
                ),
                const SizedBox(height: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Preparation & Time',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: kDeepForestGreen,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _prepTimes.map((time) {
                        final isSelected = _selectedPrepTime == time;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedPrepTime = isSelected ? '' : time;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? kSageGreen.withOpacity(0.2)
                                  : Colors.grey.shade100,
                              border: Border.all(
                                color: isSelected
                                    ? kSageGreen
                                    : Colors.grey.shade300,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              time,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected
                                    ? kDeepForestGreen
                                    : kSoftSlateGray,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildFilterSection(
                  'Meal Type',
                  _mealTypes,
                  _selectedMealTypes,
                  false,
                ),
                const SizedBox(height: 24),
                _buildFilterSection(
                  'Global Cuisines',
                  _cuisines,
                  _selectedCuisines,
                  false,
                ),
                const SizedBox(height: 24),
                _buildFilterSection(
                  'Nutritional Goals (Macros)',
                  _macroGoals,
                  _selectedMacroGoals,
                  false,
                ),
                const SizedBox(height: 24),
                _buildFilterSection(
                  'Cooking Method & Equipment',
                  _cookingMethods,
                  _selectedCookingMethods,
                  false,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
          // Floating Apply Filters button
          Positioned(
            left: 20,
            right: 20,
            bottom: 20 + MediaQuery.of(context).padding.bottom,
            child: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _applyFilters,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kDeepForestGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Apply Filters',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================= 2. DISCOVERY FEED =================
class RecipeFeedScreen extends StatefulWidget {
  final List<Ingredient> sharedIngredients;
  final Function(List<Ingredient>) onIngredientsUpdated;
  final UserProfile userProfile;
  final Function(UserProfile)? onProfileUpdated;
  final Function(CommunityReview)? onAddCommunityReview;
  final List<CommunityReview> communityReviews;
  final Set<String> dismissedRestockIds;
  final Set<String> selectedIngredientIds;
  final VoidCallback? onClearSelection;
  final void Function(String? authorId)? onFollowAuthor;
  final bool Function(String? authorId) isFollowingAuthor;

  const RecipeFeedScreen({
    super.key,
    required this.sharedIngredients,
    required this.onIngredientsUpdated,
    required this.userProfile,
    this.onProfileUpdated,
    this.onAddCommunityReview,
    required this.communityReviews,
    this.dismissedRestockIds = const {},
    this.selectedIngredientIds = const {},
    this.onClearSelection,
    this.onFollowAuthor,
    this.isFollowingAuthor = _defaultIsFollowingAuthor,
  });

  @override
  State<RecipeFeedScreen> createState() => _RecipeFeedScreenState();
}

bool _defaultIsFollowingAuthor(String? authorId) => false;

// ================= RECIPE ENTRY SCREEN =================
class RecipeEntryScreen extends StatefulWidget {
  final List<Ingredient> pantryIngredients;
  final Recipe? existingRecipe;
  const RecipeEntryScreen({
    super.key,
    required this.pantryIngredients,
    this.existingRecipe,
  });

  @override
  State<RecipeEntryScreen> createState() => _RecipeEntryScreenState();
}

class _RecipeEntryScreenState extends State<RecipeEntryScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _recipeImage;
  String recipeTitle = '';
  final TextEditingController _titleController = TextEditingController();
  List<Map<String, String>> ingredients = [
    {'name': '', 'amount': ''},
  ];
  List<String> instructions = [''];

  final _ingredientNameControllers = <TextEditingController>[];
  final _ingredientAmountControllers = <TextEditingController>[];
  final _instructionControllers = <TextEditingController>[];

  @override
  void initState() {
    super.initState();
    if (widget.existingRecipe != null) {
      _titleController.text = widget.existingRecipe!.title;
      ingredients = widget.existingRecipe!.ingredients
          .map((ing) => {'name': ing, 'amount': ''})
          .toList();
      instructions = ['']; // Keep simple for now
    }
    _syncControllers();
  }

  void _syncControllers() {
    // Ingredients
    while (_ingredientNameControllers.length < ingredients.length) {
      _ingredientNameControllers.add(
        TextEditingController(
          text: ingredients[_ingredientNameControllers.length]['name'],
        ),
      );
      _ingredientAmountControllers.add(
        TextEditingController(
          text: ingredients[_ingredientAmountControllers.length]['amount'],
        ),
      );
    }
    while (_ingredientNameControllers.length > ingredients.length) {
      _ingredientNameControllers.removeLast().dispose();
      _ingredientAmountControllers.removeLast().dispose();
    }
    // Instructions
    while (_instructionControllers.length < instructions.length) {
      _instructionControllers.add(
        TextEditingController(
          text: instructions[_instructionControllers.length],
        ),
      );
    }
    while (_instructionControllers.length > instructions.length) {
      _instructionControllers.removeLast().dispose();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (var c in _ingredientNameControllers) {
      c.dispose();
    }
    for (var c in _ingredientAmountControllers) {
      c.dispose();
    }
    for (var c in _instructionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Set<String> get pantryNames => widget.pantryIngredients
      .where(
        (ing) => (ing.unitType == UnitType.volume
            ? (ing.amount as double) > 0
            : amountAsDouble(ing.amount) > 0),
      )
      .map((ing) => ing.name.toLowerCase())
      .toSet();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _recipeImage = File(image.path);
        });
      }
    } catch (e) {
      // Image picking error - silently handle
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncControllers();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingRecipe != null ? 'Edit Recipe' : 'Create Recipe',
        ),
        backgroundColor: kBoneCreame,
        foregroundColor: kDeepForestGreen,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Recipe Title Field
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Recipe Title',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: kDeepForestGreen,
              ),
              onChanged: (val) {
                setState(() {
                  recipeTitle = val;
                });
              },
            ),
            const SizedBox(height: 24),
            // Recipe Image Section
            GestureDetector(
              onTap: () => _showImagePickerModal(),
              child: Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: kBoneCreame,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kMutedGold, width: 2),
                ),
                child: _recipeImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(_recipeImage!, fit: BoxFit.cover),
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt, size: 48, color: kMutedGold),
                            const SizedBox(height: 12),
                            const Text(
                              'Tap to add recipe photo',
                              style: TextStyle(
                                color: kMutedGold,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 32),
            // Ingredients Section
            const Text(
              'INGREDIENTS',
              style: TextStyle(
                color: kMutedGold,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ...ingredients.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final ing = entry.value;
                    final inPantry = pantryNames.contains(
                      ing['name']!.toLowerCase(),
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 120,
                                  child: TextField(
                                    controller: _ingredientNameControllers[idx],
                                    decoration: const InputDecoration(
                                      hintText: 'Ingredient',
                                      border: InputBorder.none,
                                    ),
                                    textCapitalization:
                                        TextCapitalization.words,
                                    style: const TextStyle(
                                      color: kDeepForestGreen,
                                      fontFamily: 'Playfair Display',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    onChanged: (val) {
                                      setState(() {
                                        ingredients[idx]['name'] = val;
                                      });
                                    },
                                  ),
                                ),
                                if (inPantry && ing['name']!.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kSageGreen.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'In Pantry',
                                      style: TextStyle(
                                        color: kSageGreen,
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: _ingredientAmountControllers[idx],
                              decoration: const InputDecoration(
                                hintText: 'Amount',
                                border: InputBorder.none,
                              ),
                              style: const TextStyle(
                                color: kMutedGold,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                              onChanged: (val) {
                                setState(() {
                                  ingredients[idx]['amount'] = val;
                                });
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: kSoftTerracotta,
                            ),
                            onPressed: ingredients.length > 1
                                ? () {
                                    setState(() {
                                      ingredients.removeAt(idx);
                                    });
                                  }
                                : null,
                          ),
                        ],
                      ),
                    );
                  }),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        ingredients.add({'name': '', 'amount': ''});
                      });
                    },
                    icon: const Icon(Icons.add, color: kSageGreen),
                    label: const Text(
                      'Add Ingredient',
                      style: TextStyle(color: kSageGreen),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'HOW TO MAKE',
                    style: TextStyle(
                      color: kMutedGold,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...instructions.asMap().entries.map((entry) {
                    final idx = entry.key;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${idx + 1}. ',
                            style: const TextStyle(
                              color: kDeepForestGreen,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _instructionControllers[idx],
                              maxLines: null,
                              decoration: const InputDecoration(
                                hintText: 'Step',
                                border: InputBorder.none,
                              ),
                              textCapitalization: TextCapitalization.sentences,
                              style: const TextStyle(
                                color: kDeepForestGreen,
                                fontFamily: 'Inter',
                                fontSize: 15,
                                height: 1.5,
                              ),
                              onChanged: (val) {
                                setState(() {
                                  instructions[idx] = val;
                                });
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: kSoftTerracotta,
                            ),
                            onPressed: instructions.length > 1
                                ? () {
                                    setState(() {
                                      instructions.removeAt(idx);
                                    });
                                  }
                                : null,
                          ),
                        ],
                      ),
                    );
                  }),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        instructions.add('');
                      });
                    },
                    icon: const Icon(Icons.add, color: kSageGreen),
                    label: const Text(
                      'Add Step',
                      style: TextStyle(color: kSageGreen),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        // Validate form
                        if (_titleController.text.trim().isEmpty) {
                          return;
                        }

                        // Create Recipe object from form data
                        final ingredientNames = _ingredientNameControllers
                            .map((c) => c.text.trim())
                            .where((name) => name.isNotEmpty)
                            .toList();

                        if (ingredientNames.isEmpty) {
                          return;
                        }

                        if (widget.existingRecipe != null) {
                          // Update existing recipe
                          final index = _RecipeFeedScreenState._userRecipes
                              .indexWhere(
                                (r) => r['id'] == widget.existingRecipe!.id,
                              );
                          if (index != -1) {
                            _RecipeFeedScreenState._userRecipes[index] = {
                              'id': widget.existingRecipe!.id,
                              'title': _titleController.text.trim(),
                              'ingredients': ingredientNames,
                              'cookTime':
                                  widget.existingRecipe!.cookTimeMinutes,
                              'rating': widget.existingRecipe!.rating,
                              'reviews': widget.existingRecipe!.reviewCount,
                              'imageUrl': widget.existingRecipe!.imageUrl,
                              'aspectRatio': widget.existingRecipe!.aspectRatio,
                              'authorName': widget.existingRecipe!.authorName,
                            };
                          }
                          Navigator.pop(context);
                        } else {
                          // Create new recipe
                          final newRecipe = Recipe(
                            id: DateTime.now().millisecondsSinceEpoch
                                .toString(),
                            title: _titleController.text.trim(),
                            imageUrl: '',
                            ingredients: ingredientNames,
                            ingredientTags: {},
                            cookTimeMinutes: 30,
                            rating: 5.0,
                            reviewCount: 0,
                            createdDate: DateTime.now(),
                            isSaved: false,
                          );
                          Navigator.pop(context, newRecipe);
                        }
                      },
                      child: Text(
                        widget.existingRecipe != null
                            ? 'UPDATE RECIPE'
                            : 'BRING TO POTLUCK',
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImagePickerModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose Recipe Photo',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: kCharcoal,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _pickImage(ImageSource.camera);
                      Navigator.pop(context);
                    },
                    child: Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: kSageGreen.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 40,
                            color: kSageGreen,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Camera',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _pickImage(ImageSource.gallery);
                      Navigator.pop(context);
                    },
                    child: Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: kMutedGold.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.photo_library,
                            size: 40,
                            color: kMutedGold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Gallery',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_recipeImage != null) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _recipeImage = null);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete, color: kSoftTerracotta),
                  label: const Text(
                    'Remove Photo',
                    style: TextStyle(color: kSoftTerracotta),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecipeFeedScreenState extends State<RecipeFeedScreen> {
  // Filter state
  late RecipeFilter _filter;
  final bool _debugForceShow = false;
  final EdamamRecipeService _edamamRecipeService = EdamamRecipeService();
  String? _remoteError;
  Future<List<Map<String, dynamic>>>? _remoteRecipesFuture;
  List<Map<String, dynamic>>? _cachedFilteredRecipes;
  String? _lastFilterSignature;
  // Track last pantry for significant change detection
  static const int _cacheMaxAgeMins = 30;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Profile-based filter state
  late Map<String, dynamic> _appliedFilters;
  bool _showDietaryBanner = true; // Track if banner is visible

  // Infinite scroll pagination state
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 20;
  int _currentPage = 0;
  List<Map<String, dynamic>> _displayedRecipes = [];
  List<Map<String, dynamic>> _allFilteredRecipes = [];
  bool _isLoadingMore = false;
  bool _hasMoreRecipes = true;

  // Feed toggle state: 'forYou' or 'discover'
  String _selectedFeed = 'forYou';

  @override
  void initState() {
    super.initState();
    _filter = RecipeFilter(
      allergyIngredients: widget.userProfile.allergies,
      avoidedIngredients: widget.userProfile.avoided,
    );

    // Initialize applied filters from Profile
    _appliedFilters = {
      'diets': widget.userProfile.selectedLifestyles.toList(),
      'intolerances': widget.userProfile.allergies.toList(),
      'cuisines': <String>[],
      'mealTypes': <String>[],
      'cookingMethods': <String>[],
      'macroGoals': <String>[],
      'prepTime': '',
    };

    _remoteRecipesFuture = _fetchRemoteRecipes();

    // Add scroll listener for infinite scroll
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Scroll listener for infinite scroll pagination
  void _onScroll() {
    if (_isLoadingMore || !_hasMoreRecipes) return;

    // Load more when user scrolls to 80% of the list
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final threshold = maxScroll * 0.8;

    if (currentScroll >= threshold) {
      _loadMoreRecipes();
    }
  }

  /// Load next page of recipes
  void _loadMoreRecipes() {
    if (_isLoadingMore || !_hasMoreRecipes) return;

    setState(() {
      _isLoadingMore = true;
    });

    // Simulate a small delay for smooth UX
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;

      final startIndex = (_currentPage + 1) * _pageSize;
      final endIndex = (startIndex + _pageSize).clamp(
        0,
        _allFilteredRecipes.length,
      );

      if (startIndex >= _allFilteredRecipes.length) {
        setState(() {
          _hasMoreRecipes = false;
          _isLoadingMore = false;
        });
        return;
      }

      final newRecipes = _allFilteredRecipes.sublist(startIndex, endIndex);

      setState(() {
        _displayedRecipes.addAll(newRecipes);
        _currentPage++;
        _hasMoreRecipes = endIndex < _allFilteredRecipes.length;
        _isLoadingMore = false;
      });
    });
  }

  /// Reset pagination when filters change or new data is loaded
  void _resetPagination(List<Map<String, dynamic>> allRecipes) {
    _allFilteredRecipes = allRecipes;
    _currentPage = 0;
    _hasMoreRecipes = allRecipes.length > _pageSize;

    // Load first page
    final endIndex = _pageSize.clamp(0, allRecipes.length);
    _displayedRecipes = allRecipes.sublist(0, endIndex);
  }

  /// Check if a recipe violates a specific diet restriction
  /// by checking if any ingredient matches excluded food categories
  bool _recipeViolatesDiet(List<String> ingredients, String diet) {
    // Define keywords for each diet restriction
    final Map<String, List<String>> dietExclusions = {
      'vegetarian': [
        'chicken',
        'beef',
        'pork',
        'lamb',
        'turkey',
        'duck',
        'goose',
        'veal',
        'bacon',
        'ham',
        'sausage',
        'salami',
        'pepperoni',
        'prosciutto',
        'pancetta',
        'chorizo',
        'meat',
        'steak',
        'ribs',
        'brisket',
        'ground beef',
        'ground turkey',
        'ground pork',
        'fish',
        'salmon',
        'tuna',
        'cod',
        'tilapia',
        'halibut',
        'trout',
        'sardine',
        'anchovy',
        'mackerel',
        'shrimp',
        'prawn',
        'crab',
        'lobster',
        'clam',
        'mussel',
        'oyster',
        'scallop',
        'squid',
        'octopus',
        'calamari',
        'seafood',
        'shellfish',
      ],
      'vegan': [
        'chicken',
        'beef',
        'pork',
        'lamb',
        'turkey',
        'duck',
        'goose',
        'veal',
        'bacon',
        'ham',
        'sausage',
        'salami',
        'pepperoni',
        'prosciutto',
        'pancetta',
        'chorizo',
        'meat',
        'steak',
        'ribs',
        'brisket',
        'ground beef',
        'ground turkey',
        'ground pork',
        'fish',
        'salmon',
        'tuna',
        'cod',
        'tilapia',
        'halibut',
        'trout',
        'sardine',
        'anchovy',
        'mackerel',
        'shrimp',
        'prawn',
        'crab',
        'lobster',
        'clam',
        'mussel',
        'oyster',
        'scallop',
        'squid',
        'octopus',
        'calamari',
        'seafood',
        'shellfish',
        'milk',
        'cream',
        'cheese',
        'butter',
        'yogurt',
        'egg',
        'eggs',
        'honey',
        'gelatin',
        'whey',
        'casein',
        'ghee',
        'lard',
      ],
      'pescatarian': [
        'chicken',
        'beef',
        'pork',
        'lamb',
        'turkey',
        'duck',
        'goose',
        'veal',
        'bacon',
        'ham',
        'sausage',
        'salami',
        'pepperoni',
        'prosciutto',
        'pancetta',
        'chorizo',
        'meat',
        'steak',
        'ribs',
        'brisket',
        'ground beef',
        'ground turkey',
        'ground pork',
      ],
      'gluten-free': [
        'wheat',
        'flour',
        'bread',
        'pasta',
        'noodle',
        'spaghetti',
        'fettuccine',
        'penne',
        'macaroni',
        'barley',
        'rye',
        'couscous',
        'bulgur',
        'semolina',
        'seitan',
        'beer',
        'breadcrumb',
        'crouton',
        'tortilla',
        'pita',
        'naan',
        'bagel',
        'croissant',
        'muffin',
        'pancake',
        'waffle',
        'cake',
        'cookie',
        'cracker',
        'pretzel',
      ],
      'dairy-free': [
        'milk',
        'cream',
        'cheese',
        'butter',
        'yogurt',
        'whey',
        'casein',
        'ghee',
        'sour cream',
        'cream cheese',
        'cottage cheese',
        'ricotta',
        'mozzarella',
        'parmesan',
        'cheddar',
        'brie',
        'feta',
        'gouda',
        'swiss',
        'provolone',
        'ice cream',
      ],
      'keto': [
        'sugar',
        'bread',
        'pasta',
        'rice',
        'potato',
        'corn',
        'bean',
        'lentil',
        'chickpea',
        'oat',
        'wheat',
        'flour',
        'cereal',
        'banana',
        'grape',
        'mango',
        'pineapple',
        'honey',
        'syrup',
      ],
      'paleo': [
        'bread',
        'pasta',
        'rice',
        'oat',
        'wheat',
        'flour',
        'cereal',
        'bean',
        'lentil',
        'chickpea',
        'peanut',
        'soy',
        'tofu',
        'milk',
        'cheese',
        'yogurt',
        'sugar',
        'corn',
        'potato',
      ],
    };

    final exclusions = dietExclusions[diet] ?? [];
    if (exclusions.isEmpty) return false;

    for (final ingredient in ingredients) {
      for (final excluded in exclusions) {
        if (ingredient.contains(excluded)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Check if a recipe contains an ingredient the user is intolerant to
  bool _recipeContainsIntolerance(
    List<String> ingredients,
    String intolerance,
  ) {
    // Define keywords for each intolerance
    final Map<String, List<String>> intoleranceKeywords = {
      'dairy': [
        'milk',
        'cream',
        'cheese',
        'butter',
        'yogurt',
        'whey',
        'casein',
        'ghee',
        'sour cream',
        'cream cheese',
        'cottage cheese',
        'ricotta',
        'mozzarella',
        'parmesan',
        'cheddar',
        'brie',
        'feta',
        'gouda',
        'swiss',
        'provolone',
        'ice cream',
      ],
      'egg': ['egg', 'eggs', 'mayonnaise', 'meringue', 'custard'],
      'gluten': [
        'wheat',
        'flour',
        'bread',
        'pasta',
        'noodle',
        'spaghetti',
        'fettuccine',
        'penne',
        'macaroni',
        'barley',
        'rye',
        'couscous',
        'bulgur',
        'semolina',
        'seitan',
        'beer',
        'breadcrumb',
        'crouton',
      ],
      'peanut': ['peanut', 'peanuts', 'peanut butter'],
      'seafood': [
        'fish',
        'salmon',
        'tuna',
        'cod',
        'tilapia',
        'halibut',
        'trout',
        'sardine',
        'anchovy',
        'mackerel',
      ],
      'shellfish': [
        'shrimp',
        'prawn',
        'crab',
        'lobster',
        'clam',
        'mussel',
        'oyster',
        'scallop',
        'squid',
        'octopus',
        'calamari',
      ],
      'soy': ['soy', 'soya', 'tofu', 'tempeh', 'edamame', 'miso'],
      'tree nut': [
        'almond',
        'walnut',
        'cashew',
        'pistachio',
        'pecan',
        'hazelnut',
        'macadamia',
        'brazil nut',
        'chestnut',
        'pine nut',
      ],
      'wheat': [
        'wheat',
        'flour',
        'bread',
        'pasta',
        'noodle',
        'couscous',
        'bulgur',
        'semolina',
        'farina',
      ],
      'sesame': ['sesame', 'tahini'],
      'sulfite': ['wine', 'dried fruit', 'molasses'],
    };

    final keywords = intoleranceKeywords[intolerance.toLowerCase()] ?? [];
    if (keywords.isEmpty) return false;

    for (final ingredient in ingredients) {
      for (final keyword in keywords) {
        if (ingredient.contains(keyword)) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  void didUpdateWidget(RecipeFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userProfile != widget.userProfile) {
      setState(() {
        _filter = _filter.copyWith(
          allergyIngredients: widget.userProfile.allergies,
          avoidedIngredients: widget.userProfile.avoided,
        );
      });
    }

    // Refetch when pantry contents significantly change (not on every tiny change)

    if (_hasSignificantChange(
      oldWidget.sharedIngredients,
      widget.sharedIngredients,
    )) {
      setState(() {
        _remoteRecipesFuture = _fetchRemoteRecipes();
      });
    }
  }

  /// Get sorted list of pantry ingredient names for cache key/change detection
  List<String> _getPantryList() {
    return widget.sharedIngredients
        .where(
          (ing) => (ing.unitType == UnitType.volume
              ? (ing.amount as double) > 0
              : amountAsDouble(ing.amount) > 0),
        )
        .map((ing) => ing.name.toLowerCase())
        .toList()
      ..sort();
  }

  /// Detect if pantry changed significantly (added/removed items, not quantity tweaks)
  bool _hasSignificantChange(
    List<Ingredient> oldList,
    List<Ingredient> newList,
  ) {
    final oldNames = oldList
        .where(
          (ing) => (ing.unitType == UnitType.volume
              ? (ing.amount as double) > 0
              : amountAsDouble(ing.amount) > 0),
        )
        .map((ing) => ing.name)
        .toSet();

    final newNames = newList
        .where(
          (ing) => (ing.unitType == UnitType.volume
              ? (ing.amount as double) > 0
              : amountAsDouble(ing.amount) > 0),
        )
        .map((ing) => ing.name)
        .toSet();

    // Significant if items were added or removed (not just quantity changes)
    return oldNames != newNames;
  }

  /// Get cache key based on sorted pantry ingredients
  Future<String> _getCacheKey() async {
    final pantryNames = _getPantryList();
    if (pantryNames.isEmpty) return 'edamam_cache_v1_empty';
    return 'edamam_cache_v1_${pantryNames.join('_')}';
  }

  /// Check if cache is still valid (less than 30 minutes old)
  Future<bool> _isCacheValid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = await _getCacheKey();
      final timestampKey = '${cacheKey}_timestamp';

      final timestamp = prefs.getInt(timestampKey);
      if (timestamp == null) return false;

      final cacheAge = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(timestamp),
      );
      final isValid = cacheAge.inMinutes < _cacheMaxAgeMins;
      return isValid;
    } catch (e) {
      return false;
    }
  }

  /// Load recipes from cache
  Future<List<Map<String, dynamic>>?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = await _getCacheKey();
      final cachedJson = prefs.getString(cacheKey);

      if (cachedJson == null) {
        return null;
      }

      final decoded = jsonDecode(cachedJson) as List<dynamic>;
      final results = decoded.cast<Map<String, dynamic>>();
      return results;
    } catch (e) {
      return null;
    }
  }

  /// Save recipes to cache with timestamp
  Future<void> _saveToCache(List<Map<String, dynamic>> recipes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = await _getCacheKey();
      final timestampKey = '${cacheKey}_timestamp';

      final json = jsonEncode(recipes);
      await prefs.setString(cacheKey, json);
      await prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      // ignore: empty catch blocks
    }
  }

  /// Fetch recipes with cache-first strategy
  /// Set [forceRefresh] to true to bypass cache and fetch from network
  Future<List<Map<String, dynamic>>> _fetchRemoteRecipes({
    bool forceRefresh = false,
  }) async {
    final pantryNames = _getPantryList();

    // Try cache first (unless force refresh)
    // This allows showing cached recipes on app startup even if pantry hasn't loaded yet
    if (!forceRefresh) {
      if (await _isCacheValid()) {
        final cached = await _loadFromCache();
        // Only use cache if it has actual recipes (don't return empty cache)
        if (cached != null && cached.isNotEmpty) {
          _remoteError = null;
          return cached;
        }
      }
    }

    // If pantry is empty, don't fetch new recipes (only use cache)
    if (pantryNames.isEmpty) {
      _remoteError = null;
      return [];
    }

    // Cache miss or expired or forced refresh - fetch from network
    try {
      _remoteError = null;

      // Note: Edamam fetches recipes based on pantry items
      // Dietary filters will be applied client-side after generation
      // Fetch more recipes (100) for infinite scroll pagination
      final results = await _edamamRecipeService.fetchRecipesFromPantry(
        widget.sharedIngredients,
        forceRefresh: forceRefresh,
        maxResults: 100,
      );
      if (results.isNotEmpty) {
        // Only cache if we got actual results (don't cache empty responses)
        await _saveToCache(results);
      }
      return results;
    } catch (e) {
      _remoteError = e.toString();

      // On network error, try to fall back to stale cache if available
      try {
        final prefs = await SharedPreferences.getInstance();
        final cacheKey = await _getCacheKey();
        final cachedJson = prefs.getString(cacheKey);
        if (cachedJson != null) {
          final decoded = jsonDecode(cachedJson) as List<dynamic>;
          return decoded.cast<Map<String, dynamic>>();
        }
      } catch (_) {}

      throw Exception(_remoteError);
    }
  }

  // Mock recipes database
  // User-created recipes (no bundled mock data)
  static final List<Map<String, dynamic>> _userRecipes = [];

  // Cached fetched recipes from Edamam API (accessible to ProfileScreen for saved/cooked)
  static List<Map<String, dynamic>> _fetchedRecipesCache = [];

  /// Calculate recipe match percentage (case-insensitive, partial matching)
  double _getRecipeMatchPercentage(List<String> recipeIngredients) {
    if (recipeIngredients.isEmpty) return 0.0;
    if (widget.sharedIngredients.isEmpty) return 0.0;

    int matched = 0;
    for (var recipeIng in recipeIngredients) {
      if (FilterService.isBasicStaple(recipeIng)) {
        matched++;
        continue;
      }
      final hasIngredient = widget.sharedIngredients.any((pantryIng) {
        final hasQuantity =
            pantryIng.amount != null &&
            (pantryIng.unitType == UnitType.volume
                ? (pantryIng.amount as double) > 0
                : amountAsDouble(pantryIng.amount) > 0);
        if (!hasQuantity) return false;
        return FilterService.ingredientMatches(recipeIng, pantryIng.name);
      });
      if (hasIngredient) matched++;
    }

    return (matched / recipeIngredients.length) * 100.0;
  }

  /// Get count of missing ingredients
  int _getMissingIngredientsCount(List<String> recipeIngredients) {
    if (widget.sharedIngredients.isEmpty) {
      return recipeIngredients.length; // All missing if no pantry items
    }

    int missing = 0;
    for (var recipeIng in recipeIngredients) {
      if (FilterService.isBasicStaple(recipeIng)) {
        continue;
      }
      final hasIngredient = widget.sharedIngredients.any((pantryIng) {
        final hasQuantity =
            pantryIng.amount != null &&
            (pantryIng.unitType == UnitType.volume
                ? (pantryIng.amount as double) > 0
                : amountAsDouble(pantryIng.amount) > 0);
        if (!hasQuantity) return false;
        return FilterService.ingredientMatches(recipeIng, pantryIng.name);
      });
      if (!hasIngredient) missing++;
    }
    return missing;
  }

  /// Get list of missing ingredients
  List<String> _getMissingIngredients(List<String> recipeIngredients) {
    if (widget.sharedIngredients.isEmpty) {
      return recipeIngredients; // All missing if no pantry items
    }

    final missing = <String>[];
    for (var recipeIng in recipeIngredients) {
      if (FilterService.isBasicStaple(recipeIng)) {
        continue;
      }
      final hasIngredient = widget.sharedIngredients.any((pantryIng) {
        final hasQuantity =
            pantryIng.amount != null &&
            (pantryIng.unitType == UnitType.volume
                ? (pantryIng.amount as double) > 0
                : amountAsDouble(pantryIng.amount) > 0);
        if (!hasQuantity) return false;
        return FilterService.ingredientMatches(recipeIng, pantryIng.name);
      });
      if (!hasIngredient) missing.add(recipeIng);
    }
    return missing;
  }

  /// Check if recipe has all ingredients
  bool _isReadyToCook(List<String> recipeIngredients) {
    return _getMissingIngredientsCount(recipeIngredients) == 0;
  }

  /// Callback when AdvancedSearchPage applies filters
  void _onFiltersApplied(Map<String, dynamic> filters) {
    // Update UI immediately for responsive feel
    setState(() {
      _appliedFilters = filters;
    });

    // Refetch recipes after UI update (non-blocking)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _remoteRecipesFuture = _fetchRemoteRecipes();
        });
      }
    });
  }

  /// Check if any filters are currently active
  bool _hasActiveFilters() {
    final diets = (_appliedFilters['diets'] as List<String>?) ?? [];
    final intolerances =
        (_appliedFilters['intolerances'] as List<String>?) ?? [];
    final cuisines = (_appliedFilters['cuisines'] as List<String>?) ?? [];
    final mealTypes = (_appliedFilters['mealTypes'] as List<String>?) ?? [];
    final cookingMethods =
        (_appliedFilters['cookingMethods'] as List<String>?) ?? [];
    final macroGoals = (_appliedFilters['macroGoals'] as List<String>?) ?? [];
    final prepTime = (_appliedFilters['prepTime'] as String?) ?? '';
    final searchQuery = (_appliedFilters['searchQuery'] as String?) ?? '';

    return diets.isNotEmpty ||
        intolerances.isNotEmpty ||
        cuisines.isNotEmpty ||
        mealTypes.isNotEmpty ||
        cookingMethods.isNotEmpty ||
        macroGoals.isNotEmpty ||
        prepTime.isNotEmpty ||
        searchQuery.isNotEmpty;
  }

  /// Get list of active filter chips with their type and value
  List<Map<String, String>> _getActiveFilterChips() {
    final chips = <Map<String, String>>[];

    final diets = (_appliedFilters['diets'] as List<String>?) ?? [];
    final intolerances =
        (_appliedFilters['intolerances'] as List<String>?) ?? [];
    final cuisines = (_appliedFilters['cuisines'] as List<String>?) ?? [];
    final mealTypes = (_appliedFilters['mealTypes'] as List<String>?) ?? [];
    final cookingMethods =
        (_appliedFilters['cookingMethods'] as List<String>?) ?? [];
    final macroGoals = (_appliedFilters['macroGoals'] as List<String>?) ?? [];
    final prepTime = (_appliedFilters['prepTime'] as String?) ?? '';
    final searchQuery = (_appliedFilters['searchQuery'] as String?) ?? '';

    for (final diet in diets) {
      chips.add({'type': 'diets', 'value': diet});
    }
    for (final intolerance in intolerances) {
      chips.add({'type': 'intolerances', 'value': intolerance});
    }
    for (final cuisine in cuisines) {
      chips.add({'type': 'cuisines', 'value': cuisine});
    }
    for (final mealType in mealTypes) {
      chips.add({'type': 'mealTypes', 'value': mealType});
    }
    for (final method in cookingMethods) {
      chips.add({'type': 'cookingMethods', 'value': method});
    }
    for (final macro in macroGoals) {
      chips.add({'type': 'macroGoals', 'value': macro});
    }
    if (prepTime.isNotEmpty) {
      chips.add({'type': 'prepTime', 'value': prepTime});
    }
    if (searchQuery.isNotEmpty) {
      chips.add({'type': 'searchQuery', 'value': '"$searchQuery"'});
    }

    return chips;
  }

  /// Remove a specific filter
  void _removeFilter(String filterType, String value) {
    setState(() {
      if (filterType == 'prepTime') {
        _appliedFilters['prepTime'] = '';
      } else if (filterType == 'searchQuery') {
        _appliedFilters['searchQuery'] = '';
      } else {
        final list = (_appliedFilters[filterType] as List<String>?) ?? [];
        list.remove(value);
        _appliedFilters[filterType] = list;
      }
      // Refetch recipes with updated filters
      _remoteRecipesFuture = _fetchRemoteRecipes();
    });
  }

  /// Clear all filters
  void _clearAllFilters() {
    // Update UI immediately - no need to refetch since recipes are cached
    setState(() {
      _appliedFilters = {
        'diets': <String>[],
        'intolerances': <String>[],
        'cuisines': <String>[],
        'mealTypes': <String>[],
        'cookingMethods': <String>[],
        'macroGoals': <String>[],
        'prepTime': '',
        'searchQuery': '',
      };
      // Reset pagination to show all recipes
      _resetPagination(_allFilteredRecipes);
    });
  }

  /// Build the filter chips widget
  Widget _buildFilterChips() {
    final chips = _getActiveFilterChips();
    if (chips.isEmpty) return const SizedBox.shrink();

    // Compact horizontal strip with explicit small height so it always renders
    return SizedBox(
      height: 28,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // Clear All button
          GestureDetector(
            onTap: _clearAllFilters,
            child: Container(
              // Extra-thin Clear All chip with fixed height
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              margin: const EdgeInsets.only(right: 8),
              constraints: const BoxConstraints(
                minHeight: 16,
                maxHeight: 16,
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.grey.withOpacity(0.6),
                  width: 0.8,
                ),
              ),
              child: Text(
                'Clear All',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                  height: 1.0,
                ),
              ),
            ),
          ),
          // Individual filter chips
          ...chips.map((chip) {
            final type = chip['type']!;
            final value = chip['value']!;
            // Clean up display value (remove quotes for searchQuery)
            final displayValue = type == 'searchQuery' ? value : value;

            return Container(
              margin: const EdgeInsets.only(right: 8),
              child: Chip(
                // Minimal gap between label text and close icon
                labelPadding: const EdgeInsets.only(left: 8, right: 0),
                label: Text(
                  displayValue,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: kDeepForestGreen,
                  ),
                ),
                deleteIcon: const Icon(Icons.close, size: 13),
                deleteIconColor: kDeepForestGreen.withOpacity(0.7),
                onDeleted: () => _removeFilter(
                  type,
                  type == 'searchQuery' ? value.replaceAll('"', '') : value,
                ),
                backgroundColor: kDeepForestGreen.withOpacity(0.1),
                side: BorderSide(color: kDeepForestGreen.withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _remoteRecipesFuture,
        builder: (context, snapshot) {
          final isLoading = snapshot.connectionState == ConnectionState.waiting;
          final remoteRecipes = snapshot.data ?? [];
          final remoteError = snapshot.error?.toString() ?? _remoteError;

          // Cache fetched recipes for ProfileScreen's saved/cooked tabs
          // remoteRecipes are already converted by EdamamRecipeService.fetchRecipesFromPantry()
          if (remoteRecipes.isNotEmpty) {
            // Build set of IDs that are saved or cooked — never overwrite these
            // so that restored profile data survives a feed refresh
            final savedIds = <String>{
              ...widget.userProfile.savedRecipeIds,
              ...widget.userProfile.cookedRecipeIds,
            };

            // Start from existing cache (preserves restored saved/cooked entries)
            final recipesById = <String, Map<String, dynamic>>{
              for (final r in _fetchedRecipesCache)
                if (r['id']?.toString() != null) r['id'].toString(): r,
            };

            // Add new remote recipes, but never overwrite saved/cooked entries
            for (final recipe in remoteRecipes) {
              final id = recipe['id']?.toString();
              if (id != null && id.isNotEmpty && !savedIds.contains(id)) {
                recipesById[id] = recipe;
              }
            }

            _fetchedRecipesCache = recipesById.values.toList();
          }

          // Combine cached recipes with user recipes (no duplicates)
          // Use _fetchedRecipesCache which already has deduplicated remote recipes
          var allRecipes = <Map<String, dynamic>>[
            ..._fetchedRecipesCache,
            ..._userRecipes,
          ];

          // Safety check: If data is missing, show error
          if (allRecipes.isEmpty && !isLoading) {
            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 0,
                  backgroundColor: kBoneCreame,
                  title: const Text('Potluck'),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh Recipes',
                      onPressed: () {
                        setState(() {
                          _remoteRecipesFuture = _fetchRemoteRecipes(
                            forceRefresh: true,
                          );
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'Post a Recipe',
                      onPressed: () async {
                        final newRecipe = await Navigator.push<Recipe>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RecipeEntryScreen(
                              pantryIngredients: widget.sharedIngredients,
                            ),
                          ),
                        );

                        if (newRecipe != null && mounted) {
                          // Use empty string for imageUrl since we're not using ImagenService
                          final imageUrl = '';
                          setState(() {
                            final aspectChoices = [0.85, 0.88, 0.9, 0.92, 0.95];
                            final ar =
                                aspectChoices[Random().nextInt(
                                  aspectChoices.length,
                                )];
                            _userRecipes.insert(0, {
                              'id': newRecipe.id,
                              'title': newRecipe.title,
                              'ingredients': newRecipe.ingredients,
                              'cookTime': newRecipe.cookTimeMinutes,
                              'rating': newRecipe.rating,
                              'reviews': newRecipe.reviewCount,
                              'imageUrl': imageUrl,
                              'aspectRatio': ar,
                              'authorName': newRecipe.authorName,
                            });
                          });
                        }
                      },
                    ),
                  ],
                  bottom: PreferredSize(
                    preferredSize: Size.fromHeight(
                      _hasActiveFilters() ? 120 : 76,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push<Map<String, dynamic>>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AdvancedSearchPage(
                                    userProfile: widget.userProfile,
                                    onApplyFilters: _onFiltersApplied,
                                  ),
                                ),
                              );
                            },
                            child: AbsorbPointer(
                              child: TextField(
                                controller: _searchController,
                                onChanged: (value) {
                                  setState(() {
                                    _searchQuery = value.toLowerCase();
                                  });
                                },
                                decoration: InputDecoration(
                                  hintText: 'Search recipes...',
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    color: Colors.grey,
                                  ),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() {
                                              _searchQuery = '';
                                            });
                                          },
                                        )
                                      : null,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: kDeepForestGreen,
                                      width: 2,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: kDeepForestGreen,
                                      width: 2,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: kDeepForestGreen,
                                      width: 2,
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: kBoneCreame.withOpacity(0.5),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: _buildFilterChips(),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.restaurant_menu,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                        Text(
                          'No recipes available',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add a recipe or ingredients to get started!',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          // Cache filtering/sorting to avoid recomputation on tab switches
          final pantryKey = _getPantryList().join('|');
          final dietsKey =
              ((_appliedFilters['diets'] as List<dynamic>?) ?? [])
                  .map((e) => e.toString().toLowerCase())
                  .toList()
                ..sort();
          final intolerancesKey =
              ((_appliedFilters['intolerances'] as List<dynamic>?) ?? [])
                  .map((e) => e.toString().toLowerCase())
                  .toList()
                ..sort();
          final cuisinesKey =
              ((_appliedFilters['cuisines'] as List<dynamic>?) ?? [])
                  .map((e) => e.toString().toLowerCase())
                  .toList()
                ..sort();
          final mealTypesKey =
              ((_appliedFilters['mealTypes'] as List<dynamic>?) ?? [])
                  .map((e) => e.toString().toLowerCase())
                  .toList()
                ..sort();
          final cookingMethodsKey =
              ((_appliedFilters['cookingMethods'] as List<dynamic>?) ?? [])
                  .map((e) => e.toString().toLowerCase())
                  .toList()
                ..sort();
          final macroGoalsKey =
              ((_appliedFilters['macroGoals'] as List<dynamic>?) ?? [])
                  .map((e) => e.toString().toLowerCase())
                  .toList()
                ..sort();
          final prepTimeKey = (_appliedFilters['prepTime'] as String?) ?? '';
          final advancedSearchQuery =
              (_appliedFilters['searchQuery'] as String?) ?? '';
          final allIdsKey = allRecipes
              .map((r) => r['id']?.toString() ?? '')
              .join('|');
          final signature = [
            pantryKey,
            allIdsKey,
            dietsKey.join(','),
            intolerancesKey.join(','),
            cuisinesKey.join(','),
            mealTypesKey.join(','),
            cookingMethodsKey.join(','),
            macroGoalsKey.join(','),
            prepTimeKey,
            _searchQuery,
            advancedSearchQuery,
            _debugForceShow.toString(),
          ].join('::');

          List<Map<String, dynamic>> filteredRecipes;
          if (_lastFilterSignature == signature &&
              _cachedFilteredRecipes != null) {
            filteredRecipes = _cachedFilteredRecipes!;
            // Ensure pagination is initialized from cache
            if (_allFilteredRecipes.isEmpty ||
                _allFilteredRecipes != filteredRecipes) {
              _resetPagination(filteredRecipes);
            }
          } else {
            // Sort by pantry match percentage first (more matches = better), then by rating
            allRecipes.sort((a, b) {
              // Calculate match percentages
              final aIngredients = (a['ingredients'] as List<dynamic>? ?? [])
                  .map((e) => e.toString().toLowerCase().trim())
                  .toList();
              final bIngredients = (b['ingredients'] as List<dynamic>? ?? [])
                  .map((e) => e.toString().toLowerCase().trim())
                  .toList();

              final pantryNames = widget.sharedIngredients
                  .where(
                    (ing) =>
                        ing.amount != null &&
                        ((ing.unitType == UnitType.volume &&
                                (ing.amount as double) > 0) ||
                            (ing.unitType != UnitType.volume &&
                                amountAsDouble(ing.amount) > 0)),
                  )
                  .map((e) => e.name.toLowerCase().trim())
                  .toSet();

              int aMatches = 0, bMatches = 0;
              for (var ing in aIngredients) {
                if (FilterService.isBasicStaple(ing)) {
                  aMatches++;
                  continue;
                }
                if (pantryNames.any(
                  (p) => FilterService.ingredientMatches(ing, p),
                )) {
                  aMatches++;
                }
              }
              for (var ing in bIngredients) {
                if (FilterService.isBasicStaple(ing)) {
                  bMatches++;
                  continue;
                }
                if (pantryNames.any(
                  (p) => FilterService.ingredientMatches(ing, p),
                )) {
                  bMatches++;
                }
              }

              // Higher match count comes first
              final aMatchPct = aIngredients.isNotEmpty
                  ? (aMatches / aIngredients.length) * 100
                  : 0;
              final bMatchPct = bIngredients.isNotEmpty
                  ? (bMatches / bIngredients.length) * 100
                  : 0;

              // Compare match percentages first (descending)
              final matchComparison = bMatchPct.compareTo(aMatchPct);
              if (matchComparison != 0) return matchComparison;

              // If match is equal, use rating as tiebreaker
              final ratingA = a['rating'] as double? ?? 0.0;
              final ratingB = b['rating'] as double? ?? 0.0;
              return ratingB.compareTo(ratingA);
            });

            // Apply feed-based filtering first
            if (_selectedFeed == 'forYou') {
              // FOR YOU: Show pantry-based recipes (Edamam API recipes)
              filteredRecipes = allRecipes.where((recipe) {
                final authorName = recipe['authorName'] as String? ?? '';
                // Show only API-fetched recipes (not user-created)
                return authorName != 'You' && authorName != 'Anonymous';
              }).toList();
            } else {
              // DISCOVER: Show community/user-created recipes
              filteredRecipes = allRecipes.where((recipe) {
                final authorName = recipe['authorName'] as String? ?? '';
                // Show only user-created recipes
                return authorName == 'You' || authorName == 'Anonymous';
              }).toList();
            }

            // Apply ingredient matching and dietary filtering
            if (_debugForceShow) {
              // Keep current filtered recipes
            } else {
              filteredRecipes = filteredRecipes.where((recipe) {
                final ingredientsList =
                    recipe['ingredients'] as List<dynamic>? ?? [];
                final ingredients = ingredientsList
                    .map((s) => s.toString().toLowerCase().trim())
                    .toList();

                // Apply dietary filtering to ALL recipes
                if (dietsKey.isNotEmpty || intolerancesKey.isNotEmpty) {
                  // Check diet restrictions (vegetarian, vegan, etc.)
                  for (final diet in dietsKey) {
                    if (_recipeViolatesDiet(ingredients, diet)) {
                      return false;
                    }
                  }
                  // Check intolerances (dairy, gluten, etc.)
                  for (final intolerance in intolerancesKey) {
                    if (_recipeContainsIntolerance(ingredients, intolerance)) {
                      return false;
                    }
                  }
                }

                // For "For You" feed, recipes are already pantry-matched by Edamam API
                if (_selectedFeed == 'forYou') {
                  return true;
                }

                // For "Discover" feed, no additional filtering needed
                return true;
              }).toList();
            }

            // Apply search filter from main search bar
            if (_searchQuery.isNotEmpty) {
              filteredRecipes = filteredRecipes.where((recipe) {
                final title = (recipe['title'] as String).toLowerCase();
                return title.contains(_searchQuery);
              }).toList();
            }

            // Apply search filter from Advanced Search page
            if (advancedSearchQuery.isNotEmpty) {
              filteredRecipes = filteredRecipes.where((recipe) {
                final title = (recipe['title'] as String).toLowerCase();
                return title.contains(advancedSearchQuery);
              }).toList();
            }

            // Apply prep time filter
            if (prepTimeKey.isNotEmpty) {
              filteredRecipes = filteredRecipes.where((recipe) {
                final cookTime = recipe['cookTime'] as int? ?? 30;
                if (prepTimeKey.contains('15')) {
                  return cookTime <= 15;
                } else if (prepTimeKey.contains('30')) {
                  return cookTime <= 30;
                } else if (prepTimeKey.contains('45')) {
                  return cookTime <= 45;
                } else if (prepTimeKey.contains('1hr') ||
                    prepTimeKey.contains('slow')) {
                  return cookTime > 45;
                }
                return true;
              }).toList();
            }

            // Apply meal type filter
            if (mealTypesKey.isNotEmpty) {
              filteredRecipes = filteredRecipes.where((recipe) {
                final recipeMealTypes =
                    (recipe['mealTypes'] as List<dynamic>?)
                        ?.map((e) => e.toString().toLowerCase())
                        .toList() ??
                    ['lunch'];
                // Check if any selected meal type matches
                return mealTypesKey.any((selectedType) {
                  final normalizedSelected = selectedType
                      .replaceAll(' ', '')
                      .toLowerCase();
                  return recipeMealTypes.any((recipeType) {
                    final normalizedRecipe = recipeType
                        .replaceAll(' ', '')
                        .toLowerCase();
                    return normalizedRecipe.contains(normalizedSelected) ||
                        normalizedSelected.contains(normalizedRecipe) ||
                        // Handle main course = dinner/lunch
                        (normalizedSelected == 'maincourse' &&
                            (normalizedRecipe == 'dinner' ||
                                normalizedRecipe == 'lunch'));
                  });
                });
              }).toList();
            }

            // Apply macro goals filter
            if (macroGoalsKey.isNotEmpty) {
              filteredRecipes = filteredRecipes.where((recipe) {
                final nutrition = recipe['nutrition'];
                if (nutrition == null) {
                  return true; // Don't filter out recipes without nutrition info
                }

                // Extract nutrition values
                int calories = 0;
                double protein = 0;
                double carbs = 0;
                double fat = 0;

                if (nutrition is Map<String, dynamic>) {
                  calories = (nutrition['calories'] as num?)?.toInt() ?? 0;
                  protein = (nutrition['protein'] as num?)?.toDouble() ?? 0;
                  carbs = (nutrition['carbs'] as num?)?.toDouble() ?? 0;
                  fat = (nutrition['fat'] as num?)?.toDouble() ?? 0;
                }

                for (final goal in macroGoalsKey) {
                  if (goal.contains('high protein') && protein < 20) {
                    return false;
                  }
                  if (goal.contains('low carb') && carbs > 20) return false;
                  if (goal.contains('low calorie') && calories > 400) {
                    return false;
                  }
                  if (goal.contains('low fat') && fat > 15) return false;
                }
                return true;
              }).toList();
            }

            // Filter by selected ingredients from Pantry screen
            if (widget.selectedIngredientIds.isNotEmpty) {
              // Get the names of selected ingredients
              final selectedIngredientNames = widget.sharedIngredients
                  .where((ing) => widget.selectedIngredientIds.contains(ing.id))
                  .map((ing) => ing.name.toLowerCase().trim())
                  .toSet();

              // Filter recipes that contain at least one selected ingredient
              filteredRecipes = filteredRecipes.where((recipe) {
                final ingredientsList =
                    recipe['ingredients'] as List<dynamic>? ?? [];
                final ingredients = ingredientsList
                    .map((s) => s.toString().toLowerCase().trim())
                    .toList();

                // Check if recipe contains any selected ingredient
                return selectedIngredientNames.any(
                  (selected) => ingredients.any(
                    (recipeIng) =>
                        FilterService.ingredientMatches(recipeIng, selected),
                  ),
                );
              }).toList();

              // Sort to prioritize recipes with more selected ingredients
              filteredRecipes.sort((a, b) {
                final aIngredients = (a['ingredients'] as List<dynamic>? ?? [])
                    .map((e) => e.toString().toLowerCase().trim())
                    .toList();
                final bIngredients = (b['ingredients'] as List<dynamic>? ?? [])
                    .map((e) => e.toString().toLowerCase().trim())
                    .toList();

                int aMatches = 0, bMatches = 0;
                for (final selected in selectedIngredientNames) {
                  if (aIngredients.any(
                    (ing) => FilterService.ingredientMatches(ing, selected),
                  )) {
                    aMatches++;
                  }
                  if (bIngredients.any(
                    (ing) => FilterService.ingredientMatches(ing, selected),
                  )) {
                    bMatches++;
                  }
                }

                // Sort by number of matching selected ingredients (descending)
                return bMatches.compareTo(aMatches);
              });
            }

            _cachedFilteredRecipes = filteredRecipes;
            _lastFilterSignature = signature;

            // Reset pagination when filter changes
            _resetPagination(filteredRecipes);
          }

          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 0,
                backgroundColor: kBoneCreame,
                title: const Text('Potluck'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh Recipes',
                    onPressed: () {
                      setState(() {
                        _remoteRecipesFuture = _fetchRemoteRecipes(
                          forceRefresh: true,
                        );
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Post a Recipe',
                    onPressed: () async {
                      final newRecipe = await Navigator.push<Recipe>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RecipeEntryScreen(
                            pantryIngredients: widget.sharedIngredients,
                          ),
                        ),
                      );

                      if (newRecipe != null && mounted) {
                        // Use empty string for imageUrl since we're not using ImagenService
                        final imageUrl = '';
                        setState(() {
                          final aspectChoices = [0.85, 0.88, 0.9, 0.92, 0.95];
                          final ar =
                              aspectChoices[Random().nextInt(
                                aspectChoices.length,
                              )];
                          _userRecipes.insert(0, {
                            'id': newRecipe.id,
                            'title': newRecipe.title,
                            'ingredients': newRecipe.ingredients,
                            'cookTime': newRecipe.cookTimeMinutes,
                            'rating': newRecipe.rating,
                            'reviews': newRecipe.reviewCount,
                            'imageUrl': imageUrl,
                            'aspectRatio': ar,
                            'authorName': newRecipe.authorName,
                          });
                        });
                      }
                    },
                  ),
                ],
                bottom: PreferredSize(
                  // Slightly tighter header so recipes start closer to the search bar
                  preferredSize: Size.fromHeight(
                    _hasActiveFilters() ? 152 : 112,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Segmented Control Toggle
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Container(
                          decoration: BoxDecoration(
                            color: kDeepForestGreen.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedFeed = 'forYou';
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _selectedFeed == 'forYou'
                                          ? kDeepForestGreen
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: _selectedFeed == 'forYou'
                                          ? [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.1,
                                                ),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : [],
                                    ),
                                    child: Text(
                                      'For You',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: _selectedFeed == 'forYou'
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: _selectedFeed == 'forYou'
                                            ? kBoneCreame
                                            : kDeepForestGreen.withOpacity(0.6),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedFeed = 'discover';
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _selectedFeed == 'discover'
                                          ? kDeepForestGreen
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: _selectedFeed == 'discover'
                                          ? [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.1,
                                                ),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : [],
                                    ),
                                    child: Text(
                                      'Discover',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: _selectedFeed == 'discover'
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: _selectedFeed == 'discover'
                                            ? kBoneCreame
                                            : kDeepForestGreen.withOpacity(0.6),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Search bar with symmetric gap above and below the filter chips
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push<Map<String, dynamic>>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AdvancedSearchPage(
                                  userProfile: widget.userProfile,
                                  onApplyFilters: _onFiltersApplied,
                                ),
                              ),
                            );
                          },
                          child: AbsorbPointer(
                            child: TextField(
                              controller: _searchController,
                              onChanged: (value) {
                                setState(() {
                                  _searchQuery = value.toLowerCase();
                                });
                              },
                              decoration: InputDecoration(
                                hintText: 'Search recipes...',
                                prefixIcon: const Icon(
                                  Icons.search,
                                  color: Colors.grey,
                                ),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {
                                            _searchQuery = '';
                                          });
                                        },
                                      )
                                    : null,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: kDeepForestGreen,
                                    width: 2,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: kDeepForestGreen,
                                    width: 2,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: kDeepForestGreen,
                                    width: 2,
                                  ),
                                ),
                                filled: true,
                                fillColor: kBoneCreame.withOpacity(0.5),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: _buildFilterChips(),
                        ),
                    ],
                  ),
                ),
              ),
              // Dietary Restrictions Banner (dismissible)
              if (_showDietaryBanner &&
                  (widget.userProfile.allergies.isNotEmpty ||
                      widget.userProfile.avoided.isNotEmpty ||
                      widget.userProfile.selectedLifestyles.isNotEmpty))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: kDeepForestGreen.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: kDeepForestGreen.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: kDeepForestGreen,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Your Dietary Restrictions',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: kDeepForestGreen,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (widget
                                        .userProfile
                                        .allergies
                                        .isNotEmpty) ...[
                                      ...widget.userProfile.allergies.map(
                                        (allergy) => Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade50,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: Colors.red.shade200,
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Text(
                                            '⚠️ $allergy',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.red.shade700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (widget
                                        .userProfile
                                        .avoided
                                        .isNotEmpty) ...[
                                      ...widget.userProfile.avoided.map(
                                        (avoided) => Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.shade50,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: Colors.orange.shade200,
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Text(
                                            avoided,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.orange.shade700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (widget
                                        .userProfile
                                        .selectedLifestyles
                                        .isNotEmpty) ...[
                                      ...widget.userProfile.selectedLifestyles
                                          .map(
                                            (lifestyle) => Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: Colors.blue.shade200,
                                                  width: 0.5,
                                                ),
                                              ),
                                              child: Text(
                                                lifestyle,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.blue.shade700,
                                                ),
                                              ),
                                            ),
                                          ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DietaryHubScreen(
                                      userProfile: widget.userProfile,
                                      onProfileUpdated:
                                          widget.onProfileUpdated!,
                                    ),
                                  ),
                                ),
                                child: Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: kDeepForestGreen,
                                ),
                              ),
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _showDietaryBanner = false;
                                  });
                                },
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: kDeepForestGreen.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Selected Ingredients Filter Banner
              if (widget.selectedIngredientIds.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: kMutedGold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: kMutedGold.withOpacity(0.4),
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.filter_list, size: 20, color: kMutedGold),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Filtering by ${widget.selectedIngredientIds.length} selected ingredient${widget.selectedIngredientIds.length > 1 ? 's' : ''}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: kDeepForestGreen,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: widget.sharedIngredients
                                      .where(
                                        (ing) => widget.selectedIngredientIds
                                            .contains(ing.id),
                                      )
                                      .map(
                                        (ing) => Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: kMutedGold.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: kMutedGold.withOpacity(
                                                0.5,
                                              ),
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Text(
                                            ing.name,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: kDeepForestGreen,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              widget.onClearSelection?.call();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: kMutedGold.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: kDeepForestGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (isLoading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Finding recipes that match your pantry...'),
                      ],
                    ),
                  ),
                ),
              if (remoteError != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kSoftTerracotta.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        remoteError,
                        style: const TextStyle(color: kSoftTerracotta),
                      ),
                    ),
                  ),
                ),
              // Recipe grid with items
              if (widget.sharedIngredients.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_bag_outlined,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Add ingredients to get started!',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Browse all recipes or add items from your pantry',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: Padding(
                    // Remove extra top padding so recipes sit right under the header/banners
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: MasonryGridView.count(
                      // For You = 1 column; Discover = 2 columns
                      crossAxisCount: _selectedFeed == 'forYou' ? 1 : 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: _selectedFeed == 'forYou' ? 0 : 16,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _displayedRecipes.length,
                      itemBuilder: (context, index) {
                        final recipe = _displayedRecipes[index];
                        final ingredientsList =
                            recipe['ingredients'] as List<dynamic>? ?? [];
                        final ingredients = ingredientsList
                            .map((e) => e.toString())
                            .toList();

                        // Smart image URL: use existing URL if valid, otherwise use curated fallback
                        final recipeTitle = recipe['title'] as String;
                        final rawImageUrl = recipe['imageUrl'] as String?;
                        final imageUrl =
                            (rawImageUrl != null && rawImageUrl.isNotEmpty)
                            ? rawImageUrl
                            : ''; // No fallback - show no image

                        // Compute real rating & review count from community reviews
                        final recipeId = recipe['id'] as String;
                        final recipeReviews = widget.communityReviews
                            .where((r) => r.recipeId == recipeId)
                            .toList();
                        final realReviewCount = recipeReviews.length;
                        final realRating = realReviewCount > 0
                            ? recipeReviews
                                      .map((r) => r.rating)
                                      .reduce((a, b) => a + b) /
                                  realReviewCount
                            : 0.0; // Show 0 stars when no reviews

                        return RecipeCard(
                          sharedIngredients: widget.sharedIngredients,
                          onIngredientsUpdated: widget.onIngredientsUpdated,
                          recipeTitle: recipeTitle,
                          recipeIngredients: ingredients,
                          cookTime: recipe['cookTime'] as int,
                          rating: realRating.toDouble(),
                          reviewCount: realReviewCount,
                          matchPercentage: _getRecipeMatchPercentage(
                            ingredients,
                          ),
                          // Attach nutrition if available (supports Nutrition instance or Map from Edamam/Gemini)
                          nutrition: recipe['nutrition'] != null
                              ? (recipe['nutrition'] is Nutrition
                                    ? recipe['nutrition'] as Nutrition
                                    : Nutrition.fromMap(
                                        (recipe['nutrition']
                                            as Map<String, dynamic>),
                                      ))
                              : null,
                          // Pass instructions from API
                          instructions:
                              (recipe['instructions'] as List<dynamic>?)
                                  ?.map((e) => e.toString())
                                  .toList() ??
                              [],
                          missingCount: _getMissingIngredientsCount(
                            ingredients,
                          ),
                          missingIngredients: _getMissingIngredients(
                            ingredients,
                          ),
                          isReadyToCook: _isReadyToCook(ingredients),
                          isRecommendation: false,
                          userProfile: widget.userProfile,
                          onProfileUpdated: widget.onProfileUpdated,
                          recipeId: recipe['id'] as String,
                          imageUrl: imageUrl,
                          ingredientMeasurements:
                              (recipe['ingredientMeasurements']
                                      as Map<String, dynamic>?)
                                  ?.cast<String, String>() ??
                              {},
                          // Uniform card size in 1-column For You feed; variable in Discover
                          aspectRatio: _selectedFeed == 'forYou'
                              ? 1.0
                              : (recipe['aspectRatio'] as double?) ?? 1.0,
                          isAuthor: (recipe['authorName'] ?? '') == 'You',
                          onAddCommunityReview: widget.onAddCommunityReview,
                          communityReviews: widget.communityReviews,
                          sourceUrl: recipe['sourceUrl'] as String?,
                          defaultServings: (recipe['servings'] as int?) ?? 4,
                          dismissedRestockIds: widget.dismissedRestockIds,
                          authorName: recipe['authorName'] as String?,
                          authorAvatar: recipe['authorAvatar'] as String?,
                          authorId: recipe['authorId'] as String?,
                          isDiscoverFeed: _selectedFeed == 'discover',
                          onFollowAuthor: widget.onFollowAuthor,
                          isFollowing: widget.isFollowingAuthor(recipe['authorId'] as String?),
                          onDelete: (id) {
                            setState(() {
                              _userRecipes.removeWhere((r) => r['id'] == id);
                            });
                          },
                        );
                      },
                    ),
                  ),
                ),
              // Loading indicator for infinite scroll
              if (_isLoadingMore)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kDeepForestGreen,
                        ),
                      ),
                    ),
                  ),
                ),
              // "Load more" message or end of list
              if (!_isLoadingMore &&
                  _hasMoreRecipes &&
                  _displayedRecipes.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'Scroll for more recipes',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              // Bottom padding for navigation bar
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
    );
  }
}

class RecipeCard extends StatefulWidget {
  final List<Ingredient> sharedIngredients;
  final Function(List<Ingredient>) onIngredientsUpdated;
  final String recipeTitle;
  final List<String> recipeIngredients;
  final int cookTime;
  final double rating;
  final int reviewCount;
  final double matchPercentage;
  final int missingCount;
  final List<String> missingIngredients;
  final bool isReadyToCook;
  final bool isRecommendation;
  final bool isCookedTab;
  final UserProfile? userProfile;
  final Function(UserProfile)? onProfileUpdated;
  final String? recipeId;
  final String? imageUrl;
  final Function(String)? onDelete;
  final bool isAuthor;
  final double aspectRatio;
  final Nutrition? nutrition;
  final List<String> instructions;
  final Map<String, String> ingredientMeasurements;
  final Function(CommunityReview)? onAddCommunityReview;
  final List<CommunityReview> communityReviews;
  final String? sourceUrl;
  final int defaultServings;
  final Set<String> dismissedRestockIds;
  final String? authorName;
  final String? authorAvatar;
  final String? authorId;
  final bool isDiscoverFeed;
  final void Function(String? authorId)? onFollowAuthor;
  final bool isFollowing;
  /// When null: 18 for For You, 14 for Discover. Pass 14 for Profile saved/cooked.
  final double? titleFontSize;

  const RecipeCard({
    super.key,
    required this.sharedIngredients,
    required this.onIngredientsUpdated,
    required this.recipeTitle,
    required this.recipeIngredients,
    required this.cookTime,
    required this.rating,
    required this.reviewCount,
    required this.matchPercentage,
    required this.missingCount,
    required this.missingIngredients,
    required this.isReadyToCook,
    required this.isRecommendation,
    this.userProfile,
    this.onProfileUpdated,
    this.recipeId,
    this.imageUrl,
    this.onDelete,
    this.isAuthor = false,
    this.aspectRatio = 1.0,
    this.nutrition,
    this.instructions = const [],
    this.ingredientMeasurements = const {},
    this.isCookedTab = false,
    this.onAddCommunityReview,
    required this.communityReviews,
    this.sourceUrl,
    this.defaultServings = 4,
    this.dismissedRestockIds = const {},
    this.authorName,
    this.authorAvatar,
    this.authorId,
    this.isDiscoverFeed = false,
    this.onFollowAuthor,
    this.isFollowing = false,
    this.titleFontSize,
  });

  @override
  State<RecipeCard> createState() => _RecipeCardState();
}

class _RecipeCardState extends State<RecipeCard> {
  void _removeCookedRecipe(BuildContext context) {
    if (widget.userProfile == null || widget.recipeId == null) return;
    final updatedCookedIds = List<String>.from(
      widget.userProfile!.cookedRecipeIds,
    );
    updatedCookedIds.remove(widget.recipeId!);
    final updatedProfile = widget.userProfile!.copyWith(
      cookedRecipeIds: updatedCookedIds,
    );
    widget.onProfileUpdated?.call(updatedProfile);
  }

  late bool _isSaved;
  bool _quickAdded = false;

  @override
  void initState() {
    super.initState();
    _quickAdded = widget.isFollowing;
    _updateSavedState();
  }

  @override
  void didUpdateWidget(RecipeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userProfile != widget.userProfile) {
      _updateSavedState();
    }
    if (oldWidget.isFollowing != widget.isFollowing) {
      _quickAdded = widget.isFollowing;
    }
  }

  void _updateSavedState() {
    _isSaved =
        widget.userProfile != null &&
        widget.recipeId != null &&
        widget.userProfile!.savedRecipeIds.contains(widget.recipeId);
  }

  Future<void> _toggleSave(BuildContext context) async {
    if (widget.userProfile == null || widget.recipeId == null) return;

    setState(() {
      _isSaved = !_isSaved;
    });

    final updatedSavedIds = Set<String>.from(
      widget.userProfile!.savedRecipeIds,
    );

    if (_isSaved) {
      updatedSavedIds.add(widget.recipeId!);
      // Ensure the recipe image is cached locally so it never disappears
      await _ensureRecipeImageCached(widget.recipeId!, widget.imageUrl);
    } else {
      updatedSavedIds.remove(widget.recipeId!);
    }

    final updatedProfile = widget.userProfile!.copyWith(
      savedRecipeIds: updatedSavedIds.toList(),
    );

    widget.onProfileUpdated?.call(updatedProfile);
  }

  /// Download the recipe image (if needed) and update caches so that
  /// ProfileScreen and the potluck feed always use a persistent local file path.
  Future<void> _ensureRecipeImageCached(
    String recipeId,
    String? imageUrl,
  ) async {
    if (imageUrl == null || imageUrl.isEmpty) return;

    // If it's already a local file path, nothing to do.
    if (imageUrl.startsWith('/')) return;

    try {
      final localImagePath = await RecipeImageFileService.downloadAndSaveImage(
        imageUrl: imageUrl,
        recipeId: recipeId,
      );

      if (localImagePath == null) return;

      // Update in fetched recipes cache
      final fetchedIndex = _RecipeFeedScreenState._fetchedRecipesCache
          .indexWhere((r) => r['id'] == recipeId);
      if (fetchedIndex != -1) {
        _RecipeFeedScreenState._fetchedRecipesCache[fetchedIndex]['imageUrl'] =
            localImagePath;
      }

      // Update in user recipes cache
      final userIndex = _RecipeFeedScreenState._userRecipes
          .indexWhere((r) => r['id'] == recipeId);
      if (userIndex != -1) {
        _RecipeFeedScreenState._userRecipes[userIndex]['imageUrl'] =
            localImagePath;
      }
    } catch (_) {
      // Silently ignore download/cache failures; UI errorBuilders will handle it.
    }
  }

  void _editRecipe(BuildContext context) {
    if (widget.recipeId == null) return;

    // Find the recipe in user-created list
    final recipeMap = _RecipeFeedScreenState._userRecipes.firstWhere(
      (r) => r['id'] == widget.recipeId,
      orElse: () => <String, dynamic>{},
    );

    if (recipeMap.isEmpty) return;

    // Create a Recipe object
    final recipe = Recipe(
      id: recipeMap['id'],
      title: recipeMap['title'],
      imageUrl: recipeMap['imageUrl'] ?? '',
      ingredients: recipeMap['ingredients'],
      ingredientTags: {},
      cookTimeMinutes: recipeMap['cookTime'] ?? 30,
      rating: recipeMap['rating'] ?? 4.0,
      reviewCount: recipeMap['reviews'] ?? 0,
      createdDate: DateTime.now(),
      isSaved: false,
      mealTypes: ['lunch'],
      proteinGrams: 0,
      authorName: recipeMap['authorName'] ?? 'Anonymous',
      aspectRatio: recipeMap['aspectRatio'] ?? 1.0,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeEntryScreen(
          pantryIngredients: widget.sharedIngredients,
          existingRecipe: recipe,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ===== RECIPE CARD: READ-ONLY REVIEW PREVIEW =====
    // This Recipe Card uses INDEPENDENT rendering logic (NOT _buildReviewCard).
    // It displays ONLY the top review's comment text as a read-only preview.
    // NO Reply button, NO reply counts, NO reply logic.
    // All reply features are confined to Show All modal in RecipeDetailPage.
    // ===================================================

    // Show only top review comment on recipe card preview
    final reviewsForThis = widget.communityReviews
        .where((r) => r.recipeId == widget.recipeId)
        .toList();
    String? topReviewComment;
    if (reviewsForThis.isNotEmpty) {
      reviewsForThis.sort((a, b) => b.likes.compareTo(a.likes));
      topReviewComment = reviewsForThis.first.comment;
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RecipeDetailPage(
            sharedIngredients: widget.sharedIngredients,
            onIngredientsUpdated: widget.onIngredientsUpdated,
            recipeTitle: widget.recipeTitle,
            recipeIngredients: widget.recipeIngredients,
            ingredientMeasurements: widget.ingredientMeasurements,
            userProfile: widget.userProfile,
            onProfileUpdated: widget.onProfileUpdated,
            recipeId: widget.recipeId,
            onAddCommunityReview: widget.onAddCommunityReview,
            reviews: widget.communityReviews
                .where((r) => r.recipeId == widget.recipeId)
                .toList(),
            imageUrl: widget.imageUrl,
            cookTime: widget.cookTime,
            rating: widget.rating,
            nutrition: widget.nutrition,
            instructions: widget.instructions,
            sourceUrl: widget.sourceUrl,
            defaultServings: widget.defaultServings,
            dismissedRestockIds: widget.dismissedRestockIds,
          ),
        ),
      ),
      onDoubleTap: () => _toggleSave(context),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: widget.aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
                      // Check if it's a local file path or network URL
                      (widget.imageUrl!.startsWith('/')
                          ? Image.file(
                              File(widget.imageUrl!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) {
                                return Container(
                                  color: kBoneCreame,
                                  child: Center(
                                    child: Icon(
                                      Icons.restaurant,
                                      size: 60,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                );
                              },
                            )
                          : Image.network(
                              widget.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) {
                                // Fallback to empty container when image fails
                                return Container(
                                  color: kBoneCreame,
                                  child: Center(
                                    child: Icon(
                                      Icons.restaurant,
                                      size: 60,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                );
                              },
                            )),
                    if (widget.imageUrl == null || widget.imageUrl!.isEmpty)
                      Container(
                        color: kBoneCreame,
                        child: Center(
                          child: Icon(
                            Icons.restaurant,
                            size: 60,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.75),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.85),
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: Builder(
                                builder: (context) {
                                  final total = widget.recipeIngredients.length;
                                  final have = (total - widget.missingCount)
                                      .clamp(0, total);
                                  final raw = total > 0
                                      ? '$have/$total'
                                      : '0/0';

                                  final boldStyle = TextStyle(
                                    color: kDeepForestGreen,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                  );
                                  final normalStyle = TextStyle(
                                    color: kDeepForestGreen,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.3,
                                  );

                                  final spans = <TextSpan>[];
                                  final reg = RegExp(r'(\d+|/)');
                                  int last = 0;
                                  for (final m in reg.allMatches(raw)) {
                                    if (m.start > last) {
                                      spans.add(
                                        TextSpan(
                                          text: raw.substring(last, m.start),
                                          style: normalStyle,
                                        ),
                                      );
                                    }
                                    spans.add(
                                      TextSpan(
                                        text: m.group(0),
                                        style: boldStyle,
                                      ),
                                    );
                                    last = m.end;
                                  }
                                  if (last < raw.length) {
                                    spans.add(
                                      TextSpan(
                                        text: raw.substring(last),
                                        style: normalStyle,
                                      ),
                                    );
                                  }

                                  return RichText(
                                    textAlign: TextAlign.center,
                                    text: TextSpan(children: spans),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.userProfile != null && widget.recipeId != null)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: widget.isCookedTab
                            ? GestureDetector(
                                onTap: () => _removeCookedRecipe(context),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: BackdropFilter(
                                    filter: ui.ImageFilter.blur(
                                      sigmaX: 20,
                                      sigmaY: 20,
                                    ),
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withOpacity(0.75),
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.close,
                                          size: 20,
                                          color: kDeepForestGreen,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : (widget.isAuthor
                                  ? GestureDetector(
                                      onTap: () {
                                        if (widget.recipeId != null) {
                                          widget.onDelete?.call(
                                            widget.recipeId!,
                                          );
                                        }
                                      },
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(20),
                                        child: BackdropFilter(
                                          filter: ui.ImageFilter.blur(
                                            sigmaX: 20,
                                            sigmaY: 20,
                                          ),
                                          child: Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.white.withOpacity(
                                                0.75,
                                              ),
                                            ),
                                            child: const Center(
                                              child: Icon(
                                                Icons.close,
                                                size: 20,
                                                color: kDeepForestGreen,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                  : GestureDetector(
                                      onTap: () => _toggleSave(context),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(20),
                                        child: BackdropFilter(
                                          filter: ui.ImageFilter.blur(
                                            sigmaX: 20,
                                            sigmaY: 20,
                                          ),
                                          child: Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.white.withOpacity(
                                                0.75,
                                              ),
                                            ),
                                            child: Center(
                                              child: Icon(
                                                _isSaved
                                                    ? Icons.favorite
                                                    : Icons.favorite_outline,
                                                size: 20,
                                                color: kDeepForestGreen,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    )),
                      ),
                    // Username overlay for discover feed
                    if (widget.isDiscoverFeed && widget.authorName != null)
                      Positioned(
                        bottom: 12,
                        left: 12,
                        right: 12,
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Text(
                            widget.authorName!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Stack(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title with avatar for discover feed
                      if (widget.isDiscoverFeed && widget.authorName != null)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                widget.recipeTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Playfair Display',
                                  fontSize: widget.titleFontSize ?? (widget.isDiscoverFeed ? 14 : 18),
                                  fontWeight: FontWeight.bold,
                                  color: kDeepForestGreen,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            // Reserve space so avatar + quick add badge are never clipped
                            SizedBox(
                              width: 44,
                              child: Center(
                                child: GestureDetector(
                                  onTap: () {
                                    if (widget.authorId != null) {
                                      // TODO: Navigate to user profile
                                    }
                                  },
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: kDeepForestGreen,
                                        backgroundImage: widget.authorAvatar != null
                                            ? NetworkImage(widget.authorAvatar!)
                                            : null,
                                        child: widget.authorAvatar == null
                                            ? Text(
                                                widget.authorName?.isNotEmpty == true
                                                    ? widget.authorName![0].toUpperCase()
                                                    : 'U',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              )
                                            : null,
                                      ),
                                      if (widget.authorName != null)
                                        Positioned(
                                          bottom: -2,
                                          right: -8,
                                          child: GestureDetector(
                                            onTap: () {
                                              if (widget.onFollowAuthor != null && !_quickAdded) {
                                                widget.onFollowAuthor!(widget.authorId);
                                                setState(() {
                                                  _quickAdded = true;
                                                });
                                              } else if (widget.onFollowAuthor == null) {
                                                setState(() {
                                                  _quickAdded = !_quickAdded;
                                                });
                                              }
                                            },
                                            child: Container(
                                              width: 18,
                                              height: 18,
                                              decoration: BoxDecoration(
                                                color: _quickAdded
                                                    ? Colors.black
                                                    : Colors.grey.shade600,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 2,
                                                ),
                                              ),
                                              child: Icon(
                                                _quickAdded
                                                    ? Icons.check
                                                    : Icons.add,
                                                size: 10,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          widget.recipeTitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Playfair Display',
                            fontSize: widget.titleFontSize ?? (widget.isDiscoverFeed ? 14 : 18),
                            fontWeight: FontWeight.bold,
                            color: kDeepForestGreen,
                            height: 1.2,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: kSoftSlateGray,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            formatCookTime(widget.cookTime),
                            style: const TextStyle(
                              fontSize: 13,
                              color: kSoftSlateGray,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(Icons.star, size: 14, color: kMutedGold),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${widget.rating.toStringAsFixed(1)} (${widget.reviewCount})',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: kSoftSlateGray,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Nutrition badges removed from recipe cards per UX request
                      // Top review preview (one-line) shown on RecipeCard only
                      if (topReviewComment != null) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 0),
                          child: Text(
                            topReviewComment,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: kSoftSlateGray,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (widget.isAuthor)
                    Positioned(
                      top: -5,
                      right: -5,
                      child: GestureDetector(
                        onTap: () => _editRecipe(context),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.edit,
                              size: 16,
                              color: Color.fromARGB(255, 87, 91, 94),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= RESTOCK SELECTION DIALOG =================
class _RestockSelectionDialog extends StatefulWidget {
  final List<String> recipeIngredients;

  const _RestockSelectionDialog({required this.recipeIngredients});

  @override
  State<_RestockSelectionDialog> createState() =>
      _RestockSelectionDialogState();
}

class _RestockSelectionDialogState extends State<_RestockSelectionDialog> {
  final Set<String> _selectedIngredients = {};

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: kBoneCreame,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kDeepForestGreen,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    'Kitchen Check:',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Lora',
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Need to restock anything?',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
            // Ingredient list
            Flexible(
              child: Scrollbar(
                thumbVisibility: true,
                thickness: 6,
                radius: const Radius.circular(3),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.recipeIngredients.length,
                  itemBuilder: (context, index) {
                    final ingredient = widget.recipeIngredients[index];
                    final isSelected = _selectedIngredients.contains(
                      ingredient,
                    );

                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            _selectedIngredients.add(ingredient);
                          } else {
                            _selectedIngredients.remove(ingredient);
                          }
                        });
                      },
                      title: Text(
                        ingredient[0].toUpperCase() + ingredient.substring(1),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: kDeepForestGreen,
                        ),
                      ),
                      activeColor: kDeepForestGreen,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 0,
                      ),
                      dense: true,
                    );
                  },
                ),
              ),
            ),
            // Action buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kBoneCreame,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop(<String>{});
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade700),
                        backgroundColor: Colors.grey.shade100,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop(_selectedIngredients);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kDeepForestGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      child: Text(
                        _selectedIngredients.isEmpty
                            ? 'Done'
                            : 'Add to Restock (${_selectedIngredients.length})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= 3. DETAIL PAGE =================
class RecipeDetailPage extends StatefulWidget {
  final List<Ingredient> sharedIngredients;
  final Function(List<Ingredient>) onIngredientsUpdated;
  final String recipeTitle;
  final List<String> recipeIngredients;
  final Map<String, String> ingredientMeasurements;
  final UserProfile? userProfile;
  final Function(UserProfile)? onProfileUpdated;
  final String? recipeId;
  final Function(CommunityReview)? onAddCommunityReview;
  final List<CommunityReview> reviews;
  final String? imageUrl;
  final int cookTime;
  final double rating;
  final List<String> instructions;
  final Nutrition? nutrition;
  final String? sourceUrl;
  final int defaultServings;
  final Set<String> dismissedRestockIds;

  const RecipeDetailPage({
    super.key,
    required this.sharedIngredients,
    required this.onIngredientsUpdated,
    required this.recipeTitle,
    required this.recipeIngredients,
    this.ingredientMeasurements = const {},
    this.userProfile,
    this.onProfileUpdated,
    this.recipeId,
    this.onAddCommunityReview,
    required this.reviews,
    this.imageUrl,
    this.cookTime = 30,
    this.rating = 4.5,
    this.nutrition,
    this.instructions = const [],
    this.sourceUrl,
    this.defaultServings = 4,
    this.dismissedRestockIds = const {},
  });

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  late bool _isSaved;
  final GlobalKey _reviewsKey = GlobalKey();
  static const int _initialReviewsToShow = 1;
  // Track which reviews the current user has liked locally
  final Set<String> _likedReviewIds = {};
  // Track which replies the current user has liked locally
  final Set<String> _likedReplyIds = {};
  // Track which reviews' replies are expanded
  final Set<String> _expandedReviewIds = {};
  // Reference to modal's setState for rebuilding when replies are added
  StateSetter? _modalSetState;
  // Serving size selection
  late int _selectedServings;

  // Real instructions fetched via RecipeInstructionService
  List<String> _realInstructions = [];
  bool _isLoadingInstructions = true;
  String? _instructionError;

  // Real ingredients with measurements fetched via RecipeIngredientService
  Map<String, String> _realIngredientMeasurements = {};
  bool _isLoadingIngredients = true;

  // US/Metric toggle for ingredient measurements
  bool _useMetric = false;

  Future<void> _openSourceUrl() async {
    var url = widget.sourceUrl?.trim() ?? '';
    if (url.isEmpty) return;
    if (!url.contains('://')) {
      url = 'https://$url';
    }
    final uri = Uri.tryParse(Uri.encodeFull(url));
    if (uri == null) return;

    try {
      // Try launching directly — skip canLaunchUrl to avoid iOS channel errors
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        // Unable to open link
      }
    } catch (e) {
      // Platform channel not ready or other error — show friendly message
      if (!mounted) return;
    }
  }

  @override
  void initState() {
    super.initState();
    _isSaved =
        widget.userProfile != null &&
        widget.recipeId != null &&
        widget.userProfile!.savedRecipeIds.contains(widget.recipeId);
    _selectedServings = widget.defaultServings;
    // Use consolidated service for BOTH measurements and instructions in ONE API call
    _fetchRecipeData();
  }

  /// Fetch both measurements and instructions in a single Gemini API call.
  /// This saves API quota by combining two requests into one.
  Future<void> _fetchRecipeData() async {
    if (widget.recipeId == null) {
      setState(() {
        _isLoadingIngredients = false;
        _isLoadingInstructions = false;
      });
      return;
    }

    try {
      final data = await RecipeDataService.getRecipeData(
        recipeId: widget.recipeId!,
        title: widget.recipeTitle,
        ingredients: deduplicateIngredients(widget.recipeIngredients),
        existingMeasurements: widget.ingredientMeasurements,
        sourceUrl: widget.sourceUrl,
      );

      if (mounted) {
        setState(() {
          _realIngredientMeasurements = data.measurements;
          _realInstructions = data.instructions;
          _isLoadingIngredients = false;
          _isLoadingInstructions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _instructionError = e.toString();
          _isLoadingIngredients = false;
          _isLoadingInstructions = false;
        });
      }
    }
  }

  Future<void> _toggleSaveRecipe() async {
    if (widget.userProfile == null || widget.recipeId == null) return;

    setState(() {
      _isSaved = !_isSaved;
    });

    final updatedSavedIds = Set<String>.from(
      widget.userProfile!.savedRecipeIds,
    );

    if (_isSaved) {
      updatedSavedIds.add(widget.recipeId!);

      // Download and save image locally when saving recipe
      // IMPORTANT: Do this BEFORE calling onProfileUpdated to ensure local path is in cache
      if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
        // Try to download the original image first
        var localImagePath = await RecipeImageFileService.downloadAndSaveImage(
          imageUrl: widget.imageUrl!,
          recipeId: widget.recipeId!,
        );

        // If original image download failed and URL has AWS signature, don't use fallback
        if (localImagePath == null && widget.imageUrl!.contains('X-Amz-')) {
          debugPrint(
            'Original image download failed for recipe ${widget.recipeId} - no fallback used',
          );
          // No fallback - just show no image
        }

        // Update recipe's imageUrl to local path if download successful
        if (localImagePath != null) {
          _updateRecipeImagePath(widget.recipeId!, localImagePath);
          debugPrint(
            'Image saved locally for recipe ${widget.recipeId}: $localImagePath',
          );
        } else {
          debugPrint('Failed to download image for recipe ${widget.recipeId}');
        }
      }
    } else {
      updatedSavedIds.remove(widget.recipeId!);

      // Delete local image file when unsaving
      if (widget.imageUrl != null && widget.imageUrl!.startsWith('/')) {
        await RecipeImageFileService.deleteImageFile(widget.imageUrl!);
      }
    }

    final updatedProfile = widget.userProfile!.copyWith(
      savedRecipeIds: updatedSavedIds.toList(),
    );

    // Call onProfileUpdated AFTER image is downloaded and cache is updated
    widget.onProfileUpdated?.call(updatedProfile);
  }

  /// Update recipe's image URL to local file path in cache
  void _updateRecipeImagePath(String recipeId, String localPath) {
    // Update in fetched recipes cache
    final recipeIndex = _RecipeFeedScreenState._fetchedRecipesCache.indexWhere(
      (r) => r['id'] == recipeId,
    );
    if (recipeIndex != -1) {
      _RecipeFeedScreenState._fetchedRecipesCache[recipeIndex]['imageUrl'] =
          localPath;
    }

    // Update in user recipes cache
    final userRecipeIndex = _RecipeFeedScreenState._userRecipes.indexWhere(
      (r) => r['id'] == recipeId,
    );
    if (userRecipeIndex != -1) {
      _RecipeFeedScreenState._userRecipes[userRecipeIndex]['imageUrl'] =
          localPath;
    }
  }

  Future<void> _onMadeThis() async {
    // Show dialog to let user select which ingredients to restock
    final selectedIngredients = await showDialog<Set<String>>(
      context: context,
      builder: (BuildContext context) {
        return _RestockSelectionDialog(
          recipeIngredients: widget.recipeIngredients,
        );
      },
    );

    // If user cancelled, do nothing
    if (selectedIngredients == null) return;

    // Move selected ingredients to restock (set needsPurchase = true)
    final updatedIngredients = List<Ingredient>.from(widget.sharedIngredients);

    for (final selectedIngredient in selectedIngredients) {
      final selectedLower = selectedIngredient.toLowerCase().trim();

      // Find matching pantry ingredient using fuzzy matching
      for (int i = 0; i < updatedIngredients.length; i++) {
        final pantryNameLower = updatedIngredients[i].name.toLowerCase().trim();

        if (selectedLower == pantryNameLower ||
            selectedLower.contains(pantryNameLower) ||
            pantryNameLower.contains(selectedLower)) {
          // Mark as needs purchase by setting amount to 0 (moves to restock tab)
          updatedIngredients[i] = updatedIngredients[i].copyWith(
            amount: switch (updatedIngredients[i].unitType) {
              UnitType.volume => 0.0,
              UnitType.count => 0,
              UnitType.weight => 0,
            },
          );
          break;
        }
      }
    }

    widget.onIngredientsUpdated(updatedIngredients);

    // Add recipe to cookedRecipeIds if not already present
    if (widget.userProfile != null && widget.recipeId != null) {
      final cookedIds = List<String>.from(widget.userProfile!.cookedRecipeIds);
      if (!cookedIds.contains(widget.recipeId!)) {
        cookedIds.add(widget.recipeId!);

        // Download and save image locally when marking as cooked
        // IMPORTANT: Do this BEFORE calling onProfileUpdated to ensure local path is in cache
        if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
          // Try to download the original image first
          var localImagePath =
              await RecipeImageFileService.downloadAndSaveImage(
                imageUrl: widget.imageUrl!,
                recipeId: widget.recipeId!,
              );

          // If original image download failed and URL has AWS signature, don't use fallback
          if (localImagePath == null && widget.imageUrl!.contains('X-Amz-')) {
            debugPrint(
              'Original image download failed for cooked recipe ${widget.recipeId} - no fallback used',
            );
            // No fallback - just show no image
          }

          // Update recipe's imageUrl to local path if download successful
          if (localImagePath != null) {
            _updateRecipeImagePath(widget.recipeId!, localImagePath);
            debugPrint(
              'Image saved locally for cooked recipe ${widget.recipeId}: $localImagePath',
            );
          } else {
            debugPrint(
              'Failed to download image for cooked recipe ${widget.recipeId}',
            );
          }
        }

        final updatedProfile = widget.userProfile!.copyWith(
          cookedRecipeIds: cookedIds,
        );

        // Call onProfileUpdated AFTER image is downloaded and cache is updated
        widget.onProfileUpdated?.call(updatedProfile);
      }
    }

    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selectedIngredients.isEmpty
                ? 'Recipe marked as cooked!'
                : 'Recipe marked as cooked! ${selectedIngredients.length} item${selectedIngredients.length > 1 ? 's' : ''} moved to restock.',
          ),
          backgroundColor: kDeepForestGreen,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use real AI-extracted instructions, fall back to widget.instructions
    final displayInstructions = _realInstructions.isNotEmpty
        ? _realInstructions
        : (widget.instructions.isNotEmpty ? widget.instructions : <String>[]);
    final sourceUrl = widget.sourceUrl?.trim() ?? '';
    final hasSourceUrl = sourceUrl.isNotEmpty;
    final sourceHost = Uri.tryParse(sourceUrl)?.host ?? '';

    return Scaffold(
      backgroundColor: kBoneCreame,
      appBar: AppBar(
        backgroundColor: kBoneCreame,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kDeepForestGreen),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.recipeTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: kDeepForestGreen,
            fontFamily: 'Lora',
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (widget.userProfile != null && widget.recipeId != null) ...[
            IconButton(
              icon: const Icon(Icons.ios_share, color: kDeepForestGreen),
              onPressed: () async {
                // Use a standard URL format that Messages will recognize
                final shareText =
                    '${widget.recipeTitle}\n\nView this recipe: https://potluck.app/recipes/${widget.recipeId}';

                // Compute safe origin rect for iPad/Tablet popovers
                Rect shareOrigin = Rect.zero;
                try {
                  final RenderBox? box =
                      context.findRenderObject() as RenderBox?;
                  if (box != null) {
                    shareOrigin = box.localToGlobal(Offset.zero) & box.size;
                  }
                } catch (_) {
                  shareOrigin = Rect.zero;
                }

                try {
                  XFile? xImage;

                  // Get the same image URL that's used in the potluck feed
                  final feedImageUrl =
                      (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
                      ? widget.imageUrl!
                      : ''; // No fallback - show no image

                  // Try to get image from local file path
                  if (feedImageUrl.startsWith('/')) {
                    final file = File(feedImageUrl);
                    if (await file.exists()) {
                      xImage = XFile(
                        file.path,
                        name: 'recipe_${widget.recipeId}.jpg',
                        mimeType: 'image/jpeg',
                      );
                    }
                  }

                  // Try to download network image (including curated Pexels URLs)
                  if (xImage == null &&
                      feedImageUrl.isNotEmpty &&
                      (feedImageUrl.startsWith('http://') ||
                          feedImageUrl.startsWith('https://'))) {
                    HttpClient? httpClient;
                    try {
                      httpClient = HttpClient();
                      final request = await httpClient.getUrl(
                        Uri.parse(feedImageUrl),
                      );
                      final response = await request.close();
                      if (response.statusCode == 200) {
                        final bytes = await response.fold<List<int>>(<int>[], (
                          prev,
                          el,
                        ) {
                          prev.addAll(el);
                          return prev;
                        });

                        xImage = XFile.fromData(
                          Uint8List.fromList(bytes),
                          name: 'recipe_${widget.recipeId}.jpg',
                          mimeType: 'image/jpeg',
                        );
                      }
                    } finally {
                      httpClient?.close(force: true);
                    }
                  }

                  // Try to share image + text first
                  if (xImage != null) {
                    await Share.shareXFiles(
                      [xImage],
                      subject: widget.recipeTitle,
                      text: shareText,
                      sharePositionOrigin: shareOrigin,
                    );
                  } else {
                    // Fallback: share text only
                    await Share.share(
                      shareText,
                      subject: widget.recipeTitle,
                      sharePositionOrigin: shareOrigin,
                    );
                  }
                } catch (e) {
                  // Final fallback: copy to clipboard
                  try {
                    await Clipboard.setData(ClipboardData(text: shareText));
                  } catch (_) {}
                }
              },
            ),
            IconButton(
              icon: Icon(
                _isSaved ? Icons.favorite : Icons.favorite_outline,
                color: kDeepForestGreen,
              ),
              onPressed: _toggleSaveRecipe,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Recipe Image Hero
            Container(
              height: 280,
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: widget.imageUrl != null && widget.imageUrl!.isNotEmpty
                    ? (widget.imageUrl!.startsWith('/')
                          ? Image.file(
                              File(widget.imageUrl!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  _buildPlaceholderImage(),
                            )
                          : Image.network(
                              widget.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  _buildPlaceholderImage(),
                            ))
                    : _buildPlaceholderImage(),
              ),
            ),
            const SizedBox(height: 24),

            // Recipe Title and Meta
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.recipeTitle,
                    style: const TextStyle(
                      fontFamily: 'Lora',
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: kDeepForestGreen,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Cook time and rating row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: kDeepForestGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.access_time,
                              size: 16,
                              color: kDeepForestGreen,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formatCookTime(widget.cookTime),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: kDeepForestGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: kMutedGold.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, size: 16, color: kMutedGold),
                            const SizedBox(width: 4),
                            Text(
                              widget.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: kDeepForestGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Recipe Complete Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _onMadeThis,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kDeepForestGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Mark as Cooked',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Ingredients Section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 248, 243, 234),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: kDeepForestGreen.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.shopping_basket,
                                color: kDeepForestGreen,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Ingredients',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Lora',
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: kDeepForestGreen,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Header row with servings selector and US/Metric switch
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              // Left column: Serving size selector (flex: 3)
                              Expanded(
                                flex: 3,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kDeepForestGreen.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: kDeepForestGreen.withOpacity(
                                          0.2,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        GestureDetector(
                                          onTap: _selectedServings > 1
                                              ? () {
                                                  setState(() {
                                                    _selectedServings--;
                                                  });
                                                }
                                              : null,
                                          child: Icon(
                                            Icons.remove,
                                            size: 18,
                                            color: _selectedServings > 1
                                                ? kDeepForestGreen
                                                : Colors.grey.shade400,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          child: Text(
                                            '$_selectedServings servings',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: kDeepForestGreen,
                                            ),
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _selectedServings++;
                                            });
                                          },
                                          child: const Icon(
                                            Icons.add,
                                            size: 18,
                                            color: kDeepForestGreen,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              // Gutter
                              const SizedBox(width: 16),
                              // Right column: US/Metric switch (flex: 2)
                              Expanded(
                                flex: 2,
                                child: Container(
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Stack(
                                    children: [
                                      // Sliding selection background
                                      AnimatedPositioned(
                                        duration: const Duration(
                                          milliseconds: 250,
                                        ),
                                        curve: Curves.easeInOut,
                                        left: _useMetric ? null : 0,
                                        right: _useMetric ? 0 : null,
                                        top: 2,
                                        bottom: 2,
                                        width: 60,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: kDeepForestGreen,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // US segment
                                      Positioned(
                                        left: 0,
                                        top: 0,
                                        bottom: 0,
                                        width: 60,
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _useMetric = false;
                                            });
                                          },
                                          child: Center(
                                            child: Text(
                                              'US',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: _useMetric
                                                    ? FontWeight.w500
                                                    : FontWeight.w700,
                                                color: _useMetric
                                                    ? Colors.grey.shade600
                                                    : Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Metric segment
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        bottom: 0,
                                        width: 60,
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _useMetric = true;
                                            });
                                          },
                                          child: Center(
                                            child: Text(
                                              'Metric',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: _useMetric
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                color: _useMetric
                                                    ? Colors.white
                                                    : Colors.grey.shade600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: widget.recipeIngredients.length,
                          itemBuilder: (context, index) {
                            final ingredient = widget.recipeIngredients[index];

                            // Filter out empty ingredient names
                            if (ingredient.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            final haveIt =
                                FilterService.isBasicStaple(ingredient) ||
                                widget.sharedIngredients.any((ing) {
                                  final nameMatch =
                                      FilterService.ingredientMatches(
                                        ingredient,
                                        ing.name,
                                      );
                                  final hasQuantity =
                                      ing.amount != null &&
                                      (ing.unitType == UnitType.volume
                                          ? (ing.amount as double) > 0
                                          : amountAsDouble(ing.amount) > 0);
                                  return nameMatch && hasQuantity;
                                });

                            // Get clean measurement from API and format with fractions
                            // E.g., "1/2 cup", "2 1/3 cups", etc.
                            // Scale by serving size
                            // Prefer Gemini-fetched measurements over Edamam
                            String rawMeasurement;
                            if (_isLoadingIngredients) {
                              rawMeasurement =
                                  widget.ingredientMeasurements[ingredient] ??
                                  '1 serving';
                            } else {
                              // Try exact match first (case-insensitive)
                              final ingredientLower = ingredient
                                  .toLowerCase()
                                  .trim();
                              rawMeasurement =
                                  _realIngredientMeasurements[ingredientLower] ??
                                  // Try partial match if exact match fails
                                  _findPartialMeasurementMatch(
                                    ingredientLower,
                                    _realIngredientMeasurements,
                                  ) ??
                                  // Fall back to Edamam measurements
                                  widget.ingredientMeasurements[ingredient] ??
                                  '1 serving';
                            }
                            String displayMeasurement;
                            final numMatch = RegExp(
                              r'([\d./]+(?:\s+[\d./]+)?)',
                            ).firstMatch(rawMeasurement);
                            if (numMatch != null) {
                              final matchedNum = numMatch.group(1)!.trim();
                              // Parse fraction or mixed number
                              double baseValue;
                              if (matchedNum.contains('/')) {
                                final parts = matchedNum.split(RegExp(r'\s+'));
                                double whole = 0;
                                String fractionPart = matchedNum;
                                if (parts.length == 2) {
                                  whole = double.tryParse(parts[0]) ?? 0;
                                  fractionPart = parts[1];
                                }
                                final fracParts = fractionPart.split('/');
                                if (fracParts.length == 2) {
                                  final num =
                                      double.tryParse(fracParts[0]) ?? 0;
                                  final den =
                                      double.tryParse(fracParts[1]) ?? 1;
                                  baseValue = whole + (den > 0 ? num / den : 0);
                                } else {
                                  baseValue =
                                      double.tryParse(matchedNum) ?? 1.0;
                                }
                              } else {
                                baseValue = double.tryParse(matchedNum) ?? 1.0;
                              }
                              final scaledValue =
                                  baseValue *
                                  _selectedServings /
                                  widget.defaultServings;

                              // Extract unit from raw measurement and abbreviate it
                              // Remove the number part to get just the unit
                              final unitPart = rawMeasurement
                                  .replaceFirst(RegExp(r'[\d./\s]+'), '')
                                  .trim();

                              // Convert to metric if toggle is on
                              double finalValue = scaledValue;
                              String finalUnit = unitPart;
                              if (_useMetric && unitPart.isNotEmpty) {
                                final converted = convertToMetric(
                                  scaledValue,
                                  unitPart,
                                );
                                finalValue = converted.$1;
                                finalUnit = converted.$2;
                              }

                              final abbreviatedUnit = finalUnit.isNotEmpty
                                  ? abbreviateUnit(finalUnit)
                                  : '';

                              // Format the value - use fractions for US, decimals for metric
                              String formattedValue;
                              if (_useMetric) {
                                formattedValue = finalValue >= 10
                                    ? finalValue.round().toString()
                                    : finalValue.toStringAsFixed(
                                        finalValue.truncateToDouble() ==
                                                finalValue
                                            ? 0
                                            : 1,
                                      );
                              } else {
                                formattedValue = decimalToFraction(finalValue);
                              }

                              displayMeasurement = abbreviatedUnit.isNotEmpty
                                  ? '$formattedValue $abbreviatedUnit'
                                  : formattedValue;
                            } else {
                              // No number found — use raw measurement with abbreviation
                              final parts = rawMeasurement.trim().split(
                                RegExp(r'\s+'),
                              );
                              if (parts.length >= 2) {
                                final unitPart = parts.sublist(1).join(' ');
                                final abbreviatedUnit = abbreviateUnit(
                                  unitPart,
                                );
                                displayMeasurement =
                                    '${parts[0]} $abbreviatedUnit';
                              } else {
                                displayMeasurement = rawMeasurement.trim();
                              }
                            }

                            final isLast =
                                index == widget.recipeIngredients.length - 1;

                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      // Left Column: Ingredient Names (flex: 3)
                                      Expanded(
                                        flex: 3,
                                        child: Row(
                                          children: [
                                            Icon(
                                              haveIt
                                                  ? Icons.check_circle
                                                  : Icons.circle_outlined,
                                              color: haveIt
                                                  ? kSageGreen
                                                  : kSoftTerracotta,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                ingredient.capitalize(),
                                                textAlign: TextAlign.left,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: haveIt
                                                      ? kDeepForestGreen
                                                      : kSoftTerracotta,
                                                  fontWeight: haveIt
                                                      ? FontWeight.w500
                                                      : FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Gutter
                                      const SizedBox(width: 16),
                                      // Right Column: Measurements (flex: 2)
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          displayMeasurement,
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Divider (except after last item)
                                if (!isLast)
                                  Divider(
                                    height: 1,
                                    color: Colors.grey.shade300,
                                    thickness: 0.5,
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Nutrition Section removed from here and will be shown
                  // below the "How to Make" instructions to improve flow.

                  // Instructions Section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 248, 243, 234),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: kMutedGold.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.menu_book,
                                color: kMutedGold,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'How to Make',
                              style: TextStyle(
                                fontFamily: 'Lora',
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: kDeepForestGreen,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Show loading spinner while fetching real instructions
                        if (_isLoadingInstructions) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: kDeepForestGreen,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Loading instructions...',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: kSoftSlateGray,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (_instructionError != null &&
                            _realInstructions.isEmpty &&
                            widget.instructions.isEmpty) ...[
                          // Error state with retry
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Column(
                              children: [
                                Text(
                                  'Could not load instructions.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: kSoftSlateGray,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _isLoadingInstructions = true;
                                      _instructionError = null;
                                    });
                                    _fetchRecipeData();
                                  },
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('Retry'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: kDeepForestGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          // Show instruction steps
                          ...displayInstructions.asMap().entries.map((entry) {
                            return _buildInstructionStep(
                              entry.key + 1,
                              entry.value,
                            );
                          }),
                        ],
                        // Source link at the bottom of instructions
                        if (hasSourceUrl) ...[
                          const SizedBox(height: 16),
                          Center(
                            child: TextButton.icon(
                              onPressed: _openSourceUrl,
                              icon: Icon(
                                Icons.open_in_new,
                                size: 16,
                                color: kDeepForestGreen.withOpacity(0.7),
                              ),
                              label: Text(
                                'View original on ${sourceHost.isNotEmpty ? sourceHost : "source site"}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: kDeepForestGreen.withOpacity(0.7),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  // Canonical NutritionSummaryBar relocated here (below instructions)
                  if (widget.nutrition != null) ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 248, 243, 234),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: kMutedGold.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.local_dining,
                                  color: kMutedGold,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Nutrition Facts',
                                style: TextStyle(
                                  fontFamily: 'Lora',
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: kDeepForestGreen,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          NutritionSummaryBar(
                            nutrition: widget.nutrition!,
                            servingMultiplier:
                                _selectedServings / widget.defaultServings,
                          ),
                          const SizedBox(height: 12),
                          ExpansionTile(
                            title: const Text(
                              'Additional Nutritional Info',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: kDeepForestGreen,
                              ),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                                child: CompactNutritionDetails(
                                  nutrition: widget.nutrition!,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Duplicate nutrition block removed — canonical NutritionSummaryBar shown earlier

                  // Reviews (always visible)
                  Container(
                    key: _reviewsKey,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 248, 243, 234),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: kSageGreen.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.rate_review,
                                color: kSageGreen,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Reviews',
                              style: TextStyle(
                                fontFamily: 'Lora',
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: kDeepForestGreen,
                              ),
                            ),
                          ],
                        ),

                        // (Sticky Show Less will be shown inside the expanded review list)

                        // Community images (if any)
                        if (widget.reviews.any(
                          (r) => r.imageUrl != null && r.imageUrl!.isNotEmpty,
                        )) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 100,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: widget.reviews
                                  .where(
                                    (r) =>
                                        r.imageUrl != null &&
                                        r.imageUrl!.isNotEmpty,
                                  )
                                  .length,
                              itemBuilder: (context, index) {
                                final review = widget.reviews
                                    .where(
                                      (r) =>
                                          r.imageUrl != null &&
                                          r.imageUrl!.isNotEmpty,
                                    )
                                    .toList()[index];
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: _buildCommunityDishThumbnail(review),
                                );
                              },
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),
                        // Review cards or empty state
                        if (widget.reviews.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text(
                                'No reviews yet. Be the first to share!',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: kSoftSlateGray,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          )
                        else ...[
                          // Use SIMPLE review cards here (no Reply button)
                          // Reply functionality is ONLY available in Show All modal
                          ..._buildSimpleReviewCards(),

                          // Show All opens bottom drawer (short underline centered)
                          const SizedBox(height: 12),
                          if (widget.reviews.length > _initialReviewsToShow)
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: _openReviewsDrawer,
                                  style: TextButton.styleFrom(
                                    foregroundColor: kDeepForestGreen,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                  ),
                                  child: const Text('Show All'),
                                ),
                                Center(
                                  child: Container(
                                    margin: const EdgeInsets.only(top: 2),
                                    width: 64,
                                    height: 2,
                                    decoration: BoxDecoration(
                                      color: kDeepForestGreen,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],

                        const SizedBox(height: 16),
                        // Write a Review button (always visible) - filled with white text
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _openReviewModal,
                            icon: const Icon(Icons.edit, size: 18),
                            label: const Text('Write a Review'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kDeepForestGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 100), // Bottom padding for nav bar
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Builder(
        builder: (context) {
          final shoppingListCount = widget.sharedIngredients
              .where(
                (ing) =>
                    ing.needsPurchase &&
                    !widget.dismissedRestockIds.contains(ing.id),
              )
              .length;

          return SizedBox(
            height: 80, // Fixed height to match main navigation
            child: PotluckNavigationBar(
              currentIndex: 1,
              onTap: (index) {
                // Close detail and return to root so main navigation becomes visible.
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              shoppingListCount: shoppingListCount,
            ),
          );
        },
      ),
    );
  }

  /// Find a measurement match for an ingredient using partial/fuzzy matching
  String? _findPartialMeasurementMatch(
    String ingredientLower,
    Map<String, String> measurements,
  ) {
    // Try to find a key that contains the ingredient name or vice versa
    for (final entry in measurements.entries) {
      final key = entry.key.toLowerCase().trim();

      // Exact match
      if (key == ingredientLower) {
        return entry.value;
      }

      // Partial match - ingredient contains key or key contains ingredient
      if (ingredientLower.contains(key) || key.contains(ingredientLower)) {
        return entry.value;
      }

      // Word-based matching - check if any significant words match
      final ingredientWords = ingredientLower.split(RegExp(r'\s+'));
      final keyWords = key.split(RegExp(r'\s+'));

      for (final iWord in ingredientWords) {
        if (iWord.length < 3) continue; // Skip short words
        for (final kWord in keyWords) {
          if (kWord.length < 3) continue;
          if (iWord == kWord ||
              iWord.contains(kWord) ||
              kWord.contains(iWord)) {
            return entry.value;
          }
        }
      }
    }

    return null;
  }

  Widget _buildPlaceholderImage() {
    return Container(
      color: kBoneCreame,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.restaurant,
              size: 60,
              color: kDeepForestGreen.withOpacity(0.3),
            ),
            const SizedBox(height: 8),
            Text(
              'Delicious awaits!',
              style: TextStyle(
                color: kDeepForestGreen.withOpacity(0.5),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionStep(int stepNumber, String instruction) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: kDeepForestGreen,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                '$stepNumber',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              instruction,
              style: const TextStyle(
                fontSize: 15,
                color: kSoftSlateGray,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityDishThumbnail(CommunityReview review) {
    return GestureDetector(
      onTap: () => _showFullScreenImage(review),
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Image.file(
                File(review.imageUrl!),
                fit: BoxFit.cover,
                width: 120,
                height: 120,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 120,
                  height: 120,
                  color: Colors.grey.shade300,
                  child: const Icon(
                    Icons.image_not_supported,
                    color: Colors.grey,
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.white,
                  child: Text(
                    review.userName.isNotEmpty
                        ? review.userName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: kDeepForestGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullScreenImage(CommunityReview review) {
    final imageReviews = widget.reviews
        .where((r) => r.imageUrl != null && r.imageUrl!.isNotEmpty)
        .toList();
    final initialIndex = imageReviews.indexWhere((r) => r.id == review.id);
    final pageController = PageController(initialPage: initialIndex);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.black,
        child: PageView.builder(
          controller: pageController,
          itemCount: imageReviews.length,
          itemBuilder: (context, pageIndex) {
            final currentReview = imageReviews[pageIndex];
            return Stack(
              children: [
                Center(
                  child: Image.file(
                    File(currentReview.imageUrl!),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.image_not_supported,
                      color: Colors.white,
                      size: 50,
                    ),
                  ),
                ),
                Positioned(
                  top: 40,
                  right: 20,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              currentReview.userName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Row(
                              children: List.generate(5, (index) {
                                return Icon(
                                  index < currentReview.rating
                                      ? Icons.star
                                      : Icons.star_border,
                                  size: 16,
                                  color: kMutedGold,
                                );
                              }),
                            ),
                          ],
                        ),
                        if (currentReview.comment.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            currentReview.comment,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          _formatDate(currentReview.createdDate),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ========== ARCHITECTURAL SEPARATION ==========
  // This class maintains strict separation of review rendering logic:
  //
  // 1. MAIN DETAIL PAGE (simple preview - NO reply functionality):
  //    - Uses _buildSimpleReviewCards() → _buildSimpleReviewCard()
  //    - Shows comment only - NO Reply button, NO reply counts
  //    - Users must click "Show All" to access reply functionality
  //
  // 2. SHOW ALL MODAL VIEW (full-featured):
  //    - _openReviewsDrawer() → _buildReviewCard() → complete review with replies
  //    - _buildReviewCard() contains Reply button, Show/Hide toggle, reply rendering
  //    - ONLY location where Reply button and reply functionality exists
  //
  // Recipe Card (feed preview) uses independent _topReviewComment for one-line preview.
  // All reply logic is confined to the Show All modal only.
  // =============================================

  /// Builds SIMPLE review cards for main detail page (NO reply functionality)
  /// This is used in the main RecipeDetailPage view before clicking "Show All"
  List<Widget> _buildSimpleReviewCards() {
    // Sort reviews by likes (highest first)
    final sortedReviews = List<CommunityReview>.from(widget.reviews)
      ..sort((a, b) => b.likes.compareTo(a.likes));

    // Show only top N reviews
    final reviewsToShow = sortedReviews.take(_initialReviewsToShow).toList();

    return reviewsToShow
        .map((review) => _buildSimpleReviewCard(review))
        .toList();
  }

  /// Builds SIMPLE review card - comment only, NO Reply button, NO reply counts
  /// Used in the main detail page view (before clicking Show All)
  Widget _buildSimpleReviewCard(CommunityReview review) {
    const double avatarSize = 40.0;
    final parts = review.userName.split(' ');
    String initials = '';
    if (parts.isNotEmpty) {
      initials = parts
          .where((p) => p.isNotEmpty)
          .map((p) => p[0].toUpperCase())
          .take(2)
          .join();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 248, 243, 234),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              color: kSageGreen.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initials.isNotEmpty ? initials : '?',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: kDeepForestGreen,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name and rating row
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        review.userName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: kDeepForestGreen,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Star rating
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(5, (index) {
                        return Icon(
                          index < review.rating
                              ? Icons.star
                              : Icons.star_border,
                          size: 12,
                          color: kMutedGold,
                        );
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Comment text only - NO reply info
                Text(
                  review.comment,
                  style: const TextStyle(
                    fontSize: 14,
                    color: kSoftSlateGray,
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Like count + Heart at top-right
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${review.likes}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  setState(() {
                    final liked = _likedReviewIds.contains(review.id);
                    final newLikes = liked
                        ? review.likes - 1
                        : review.likes + 1;
                    if (liked) {
                      _likedReviewIds.remove(review.id);
                    } else {
                      _likedReviewIds.add(review.id);
                    }

                    final index = widget.reviews.indexWhere(
                      (r) => r.id == review.id,
                    );
                    if (index != -1) {
                      widget.reviews[index] = CommunityReview(
                        id: review.id,
                        recipeId: review.recipeId,
                        userName: review.userName,
                        userAvatarUrl: review.userAvatarUrl,
                        rating: review.rating,
                        comment: review.comment,
                        imageUrl: review.imageUrl,
                        createdDate: review.createdDate,
                        likes: newLikes,
                        replies: review.replies,
                      );
                    }
                  });
                },
                child: Icon(
                  _likedReviewIds.contains(review.id)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  size: 16,
                  color: _likedReviewIds.contains(review.id)
                      ? Colors.red
                      : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Renders FULL review card with Reply button, Show/Hide toggle, and replies.
  /// ONLY used in Show All modal (_openReviewsDrawer).
  /// ONLY used in Show All modal (_openReviewsDrawer).
  /// Contains all reply-related logic and nested array mapping.
  Widget _buildReviewCard(CommunityReview review) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 248, 243, 234),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: avatar (initials) + name and rating
              Builder(
                builder: (context) {
                  const double avatarSize = 40.0;
                  final parts = review.userName.split(' ');
                  String initials = '';
                  if (parts.isNotEmpty) {
                    initials = parts
                        .where((p) => p.isNotEmpty)
                        .map((p) => p[0].toUpperCase())
                        .take(2)
                        .join();
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: BoxDecoration(
                          color: kSageGreen.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            initials.isNotEmpty ? initials : '?',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: kDeepForestGreen,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  fit: FlexFit.loose,
                                  child: Text(
                                    review.userName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: kDeepForestGreen,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _formatDate(review.createdDate),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: kCharcoal,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: List.generate(5, (index) {
                                return Icon(
                                  index < review.rating
                                      ? Icons.star
                                      : Icons.star_border,
                                  size: 16,
                                  color: kMutedGold,
                                );
                              }),
                            ),
                          ],
                        ),
                      ),

                      // Like count + Heart at top-right
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${review.likes}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              final liked = _likedReviewIds.contains(review.id);
                              final newLikes = liked
                                  ? review.likes - 1
                                  : review.likes + 1;
                              if (liked) {
                                _likedReviewIds.remove(review.id);
                              } else {
                                _likedReviewIds.add(review.id);
                              }

                              final index = widget.reviews.indexWhere(
                                (r) => r.id == review.id,
                              );
                              if (index != -1) {
                                widget.reviews[index] = CommunityReview(
                                  id: review.id,
                                  recipeId: review.recipeId,
                                  userName: review.userName,
                                  userAvatarUrl: review.userAvatarUrl,
                                  rating: review.rating,
                                  comment: review.comment,
                                  imageUrl: review.imageUrl,
                                  createdDate: review.createdDate,
                                  likes: newLikes,
                                  replies: review.replies,
                                );
                              }

                              // Update both modal and main page state
                              if (_modalSetState != null) {
                                _modalSetState!(() {});
                              }
                              setState(() {});
                            },
                            child: Icon(
                              _likedReviewIds.contains(review.id)
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 18,
                              color: _likedReviewIds.contains(review.id)
                                  ? Colors.red
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 12),

              // Comment body aligned with start of username
              Padding(
                padding: const EdgeInsets.only(left: 52.0),
                child: Text(
                  review.comment,
                  style: const TextStyle(
                    fontSize: 15,
                    color: kSoftSlateGray,
                    height: 1.6,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Reply button (subtle) aligned with comment; toggle shown on next indented line
              Padding(
                padding: const EdgeInsets.only(left: 52.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => _showReplyInput(review),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Reply',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (review.replies.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 12.0),
                        child: GestureDetector(
                          onTap: () {
                            // Use modal setState to update the toggle in the modal
                            if (_modalSetState != null) {
                              _modalSetState!(() {
                                if (_expandedReviewIds.contains(review.id)) {
                                  _expandedReviewIds.remove(review.id);
                                } else {
                                  _expandedReviewIds.add(review.id);
                                }
                              });
                            }
                          },
                          child: Text(
                            _expandedReviewIds.contains(review.id)
                                ? 'Hide ${review.replies.length} ${review.replies.length == 1 ? 'reply' : 'replies'}'
                                : 'Show ${review.replies.length} ${review.replies.length == 1 ? 'reply' : 'replies'}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Display replies (only when expanded)
              if (_expandedReviewIds.contains(review.id) &&
                  review.replies.isNotEmpty) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 52.0),
                  child: Builder(
                    builder: (context) {
                      // Get fresh review data to ensure we have latest replies
                      final freshReview = widget.reviews.firstWhere(
                        (r) => r.id == review.id,
                        orElse: () => review,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: freshReview.replies.map((reply) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      reply.userName,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: kDeepForestGreen,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _formatDate(reply.createdDate),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const Spacer(),
                                    // Like count and heart for replies
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${reply.likes}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        GestureDetector(
                                          onTap: () {
                                            final liked = _likedReplyIds
                                                .contains(reply.id);
                                            final newLikes = liked
                                                ? reply.likes - 1
                                                : reply.likes + 1;

                                            // Update tracking
                                            if (liked) {
                                              _likedReplyIds.remove(reply.id);
                                            } else {
                                              _likedReplyIds.add(reply.id);
                                            }

                                            // Update the reply in the review
                                            final reviewIndex = widget.reviews
                                                .indexWhere(
                                                  (r) => r.id == review.id,
                                                );
                                            if (reviewIndex != -1) {
                                              final replyIndex = widget
                                                  .reviews[reviewIndex]
                                                  .replies
                                                  .indexWhere(
                                                    (rep) => rep.id == reply.id,
                                                  );
                                              if (replyIndex != -1) {
                                                final updatedReplies =
                                                    List<ReviewReply>.from(
                                                      widget
                                                          .reviews[reviewIndex]
                                                          .replies,
                                                    );
                                                updatedReplies[replyIndex] =
                                                    ReviewReply(
                                                      id: reply.id,
                                                      userName: reply.userName,
                                                      comment: reply.comment,
                                                      createdDate:
                                                          reply.createdDate,
                                                      likes: newLikes,
                                                    );
                                                widget.reviews[reviewIndex] =
                                                    CommunityReview(
                                                      id: review.id,
                                                      recipeId: review.recipeId,
                                                      userName: review.userName,
                                                      userAvatarUrl:
                                                          review.userAvatarUrl,
                                                      rating: review.rating,
                                                      comment: review.comment,
                                                      imageUrl: review.imageUrl,
                                                      createdDate:
                                                          review.createdDate,
                                                      likes: review.likes,
                                                      replies: updatedReplies,
                                                    );
                                              }
                                            }

                                            // Update both modal and main page state
                                            if (_modalSetState != null) {
                                              _modalSetState!(() {});
                                            }
                                            setState(() {});
                                          },
                                          child: Icon(
                                            _likedReplyIds.contains(reply.id)
                                                ? Icons.favorite
                                                : Icons.favorite_border,
                                            size: 14,
                                            color:
                                                _likedReplyIds.contains(
                                                  reply.id,
                                                )
                                                ? Colors.red
                                                : Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  reply.comment,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: kSoftSlateGray,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
              ],

              const SizedBox(height: 8),

              // Metadata row removed (date moved to header)
            ],
          ),
        ),
      ],
    );
  }

  // ========== END OF SHOW ALL MODAL REVIEW RENDERING ==========
  // _buildReviewCard() above is the ONLY method that renders reviews with replies.
  // It contains all Reply button logic, Show/Hide toggle, and nested reply array mapping.
  // It is called ONLY from _openReviewsDrawer() modal.
  // The main detail page uses _buildSimpleReviewCards() which has NO reply functionality.
  // ============================================================

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    final minutes = difference.inMinutes;
    if (minutes < 60) {
      final m = minutes <= 0 ? 0 : minutes;
      return '${m}m';
    }

    final hours = difference.inHours;
    if (hours < 24) {
      return '${hours}h';
    }

    final days = difference.inDays;
    if (days < 7) {
      return '${days}d';
    }

    final weeks = (days / 7).floor();
    return '${weeks}w';
  }

  // Review survey is shown in a modal via _openReviewModal

  void _submitReviewOnly({
    required int rating,
    required String comment,
    File? imageFile,
  }) {
    // Create and add community review (no ingredient deduction)
    if (widget.recipeId != null) {
      final review = CommunityReview(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        recipeId: widget.recipeId!,
        userName: widget.userProfile?.userName ?? 'Anonymous',
        userAvatarUrl: widget.userProfile?.avatarUrl,
        rating: rating,
        comment: comment,
        imageUrl: imageFile?.path,
        createdDate: DateTime.now(),
        likes: Random().nextInt(20),
      );

      // Add review to local state for immediate display
      setState(() {
        widget.reviews.insert(0, review);
      });

      // Also notify parent to update global list
      widget.onAddCommunityReview?.call(review);
    }

    // Survey is shown in a modal; no inline flag to update
  }

  void _openReviewsDrawer() {
    // Keep replies collapsed by default (user clicks Show to expand)
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      isDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Capture the setModalState so we can use it from _addReplyToReview
            _modalSetState = setModalState;

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.80,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                // Sort reviews by likes (most liked first)
                final sortedReviews = List<CommunityReview>.from(widget.reviews)
                  ..sort((a, b) => b.likes.compareTo(a.likes));

                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Grabber bar at the top center
                      Padding(
                        padding: const EdgeInsets.only(top: 10.0, bottom: 12.0),
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                          ),
                        ),
                      ),

                      // Header: title and close button
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Reviews',
                              style: TextStyle(
                                fontFamily: 'Lora',
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: kDeepForestGreen,
                              ),
                            ),
                            // Close X button in top-right
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(
                                Icons.close,
                                color: kDeepForestGreen,
                                size: 24,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),

                      const Divider(height: 1, thickness: 1),

                      // Scrollable reviews list
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          itemCount: sortedReviews.length,
                          itemBuilder: (context, index) {
                            final review = sortedReviews[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _buildReviewCard(review),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    ).whenComplete(() {
      // Collapse replies that belong to this recipe's reviews when the drawer closes
      setState(() {
        for (var r in widget.reviews) {
          _expandedReviewIds.remove(r.id);
        }
      });
      // Clear modal state reference
      _modalSetState = null;
    });
  }

  void _showReplyInput(CommunityReview review) {
    final TextEditingController replyController = TextEditingController();

    // Ensure replies are visible when replying
    setState(() {
      _expandedReviewIds.add(review.id);
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Reply to ${review.userName}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: kDeepForestGreen,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: replyController,
              maxLines: 3,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Write your reply...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: kBoneCreame.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  var replyText = replyController.text.trim();
                  if (replyText.isNotEmpty) {
                    // Ensure first character is capitalized
                    if (replyText.length == 1) {
                      replyText = replyText.toUpperCase();
                    } else {
                      replyText =
                          replyText[0].toUpperCase() + replyText.substring(1);
                    }
                    _addReplyToReview(review, replyText);
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kDeepForestGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Post Reply',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _addReplyToReview(CommunityReview review, String replyText) {
    final newReply = ReviewReply(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userName: widget.userProfile?.userName ?? 'Anonymous',
      comment: replyText,
      createdDate: DateTime.now(),
    );

    // Update page state
    setState(() {
      final index = widget.reviews.indexWhere((r) => r.id == review.id);
      if (index != -1) {
        final updatedReplies = [...widget.reviews[index].replies, newReply];
        widget.reviews[index] = CommunityReview(
          id: review.id,
          recipeId: review.recipeId,
          userName: review.userName,
          userAvatarUrl: review.userAvatarUrl,
          rating: review.rating,
          comment: review.comment,
          imageUrl: review.imageUrl,
          createdDate: review.createdDate,
          likes: review.likes,
          replies: updatedReplies,
        );
        // Keep the replies expanded when a new reply is added
        _expandedReviewIds.add(review.id);
      }
    });

    // Also trigger modal rebuild to show new reply immediately
    if (_modalSetState != null) {
      _modalSetState!(() {
        // Modal state setter - forces modal to rebuild with new reply visible
      });
    }

    // Reply input modal is closed by the button's onPressed handler
    // Do NOT pop again here - that would close the reviews modal
  }

  void _openReviewModal() {
    final picker = ImagePicker();

    showGeneralDialog(
      context: context,
      barrierLabel: 'Write a review',
      barrierDismissible: true,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: 0.72,
            widthFactor: 1.0,
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.all(0),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: _ReviewSurveyContent(
                      picker: picker,
                      onSubmit: (rating, comment, imageFile) {
                        _submitReviewOnly(
                          rating: rating,
                          comment: comment,
                          imageFile: imageFile,
                        );
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim, secAnim, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: child,
        );
      },
    );
  }
}

// Separate stateful widget for review survey to properly manage state
class _ReviewSurveyContent extends StatefulWidget {
  final Function(int rating, String comment, File? imageFile) onSubmit;
  final ImagePicker picker;

  const _ReviewSurveyContent({required this.onSubmit, required this.picker});

  @override
  State<_ReviewSurveyContent> createState() => _ReviewSurveyContentState();
}

class _ReviewSurveyContentState extends State<_ReviewSurveyContent> {
  int _rating = 0;
  File? _selectedImage;
  final TextEditingController _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Share Your Experience',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: kDeepForestGreen,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            final isSelected = index < _rating;
            return IconButton(
              icon: Icon(
                isSelected ? Icons.star : Icons.star_border,
                color: kMutedGold,
                size: 28,
              ),
              onPressed: () {
                setState(() {
                  _rating = index + 1;
                });
              },
            );
          }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _commentController,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'How did it turn out? Any tips?',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: kBoneCreame.withOpacity(0.5),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () async {
            final source = await showDialog<ImageSource>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Choose Image Source'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, ImageSource.camera),
                    child: const Text('Camera'),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, ImageSource.gallery),
                    child: const Text('Gallery'),
                  ),
                ],
              ),
            );
            if (source != null) {
              try {
                final pickedFile = await widget.picker.pickImage(
                  source: source,
                );
                if (pickedFile != null) {
                  setState(() {
                    _selectedImage = File(pickedFile.path);
                  });
                }
              } catch (e) {
                // Image picking error - silently handle
              }
            }
          },
          child: Container(
            height: 80,
            width: double.infinity,
            decoration: BoxDecoration(
              color: kBoneCreame,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kMutedGold, width: 2),
            ),
            child: _selectedImage != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      _selectedImage!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt, size: 24, color: kMutedGold),
                        SizedBox(height: 4),
                        Text(
                          'Tap to add photo',
                          style: TextStyle(
                            color: kMutedGold,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              var comment = _commentController.text.trim();
              if (comment.isNotEmpty) {
                if (comment.length == 1) {
                  comment = comment.toUpperCase();
                } else {
                  comment = comment[0].toUpperCase() + comment.substring(1);
                }
              }
              widget.onSubmit(_rating, comment, _selectedImage);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kDeepForestGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Share Review',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}

// ================= 5. PROFILE SCREEN - SAVED RECIPES =================
class ProfileScreen extends StatefulWidget {
  final List<Ingredient> pantryIngredients;
  final Function(List<Ingredient>) onIngredientsUpdated;
  final UserProfile userProfile;
  final Function(UserProfile) onProfileUpdated;
  final Function(CommunityReview)? onAddCommunityReview;
  final List<CommunityReview> communityReviews;
  final int followerCount;

  const ProfileScreen({
    super.key,
    this.pantryIngredients = const [],
    required this.onIngredientsUpdated,
    required this.userProfile,
    required this.onProfileUpdated,
    this.onAddCommunityReview,
    required this.communityReviews,
    this.followerCount = 0,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class PotluckProfileHeader extends StatelessWidget {
  final String userName;
  final String? avatarUrl;
  final VoidCallback? onAvatarTap;

  const PotluckProfileHeader({
    super.key,
    required this.userName,
    this.avatarUrl,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: kBoneCreame,
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: onAvatarTap,
            child: Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: kMutedGold, width: 1.5),
                  ),
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.white,
                    backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
                        ? (avatarUrl!.startsWith('/')
                              ? FileImage(File(avatarUrl!))
                              : NetworkImage(avatarUrl!) as ImageProvider)
                        : null,
                    child: avatarUrl == null || avatarUrl!.isEmpty
                        ? Icon(Icons.person, size: 60, color: kMutedGold)
                        : null,
                  ),
                ),
                if (onAvatarTap != null)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: kDeepForestGreen,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            userName.contains(' ') ? userName : '@$userName',
            style: const TextStyle(
              fontFamily: 'Lora',
              fontWeight: FontWeight.bold,
              fontSize: 24,
              color: kDeepForestGreen,
              letterSpacing: 0.5,
            ),
          ),
          if (userName.isNotEmpty && !userName.contains(' '))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Your unique handle',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: kSoftSlateGray,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileScreenState extends State<ProfileScreen> {
  late UserProfile _profile;
  final String _selectedMealFilter = '';
  final String _searchQuery = '';
  String _selectedTab = 'Saved'; // New state for tab selection
  final ImagePicker _imagePicker = ImagePicker();
  late List<CommunityReview> _communityReviews;

  @override
  void initState() {
    super.initState();
    _profile = widget.userProfile;
    _communityReviews = widget.communityReviews;
  }

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userProfile != widget.userProfile ||
        oldWidget.communityReviews != widget.communityReviews) {
      setState(() {
        _profile = widget.userProfile;
        _communityReviews = widget.communityReviews;
      });
    }
  }

  void _onProfileUpdated(UserProfile updatedProfile) {
    setState(() {
      _profile = updatedProfile;
    });
    widget.onProfileUpdated(updatedProfile);
  }

  Future<void> _changeProfilePicture() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Change Profile Picture',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: kDeepForestGreen,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: kSageGreen.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: kSageGreen,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Camera',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: kMutedGold.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.photo_library,
                          color: kMutedGold,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Gallery',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_profile.avatarUrl != null &&
                _profile.avatarUrl!.isNotEmpty) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  // Remove profile picture
                  setState(() {
                    _profile = _profile.copyWith(avatarUrl: '');
                  });
                  widget.onProfileUpdated(_profile);
                  Navigator.pop(context);
                },
                child: const Text(
                  'Remove Photo',
                  style: TextStyle(color: kSoftTerracotta),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (source != null) {
      try {
        final pickedFile = await _imagePicker.pickImage(source: source);
        if (pickedFile != null) {
          setState(() {
            _profile = _profile.copyWith(avatarUrl: pickedFile.path);
          });
          widget.onProfileUpdated(_profile);
        }
      } catch (e) {
        // Image picking error - silently handle
      }
    }
  }

  /// Count cooked recipes that actually exist in recipes (for stat display)
  int _getCookedRecipesCount() {
    // Look at both user recipes and fetched Gemini recipes
    final allRecipeIds = <dynamic>{
      ..._RecipeFeedScreenState._userRecipes.map((map) => map['id'] as String),
      ..._RecipeFeedScreenState._fetchedRecipesCache.map(
        (map) => map['id'] as String,
      ),
    };

    return _profile.cookedRecipeIds
        .where((id) => allRecipeIds.contains(id))
        .length;
  }

  /// Count shared recipes (recipes posted by the user) that exist in user-created recipes (for stat display)
  int _getSharedRecipesCount() {
    return _RecipeFeedScreenState._userRecipes
        .where((recipe) => recipe['authorName'] == 'You')
        .length;
  }

  List<Recipe> _getSavedRecipes() {
    // Combine user-created recipes with fetched Gemini recipes
    final allRecipeMaps = [
      ..._RecipeFeedScreenState._userRecipes,
      ..._RecipeFeedScreenState._fetchedRecipesCache,
    ];

    // Convert maps to Recipe objects and filter by saved IDs
    final aspectChoices = [0.85, 0.88, 0.9, 0.92, 0.95];
    final random = Random();

    final savedRecipes = <Recipe>[];
    for (var map in allRecipeMaps) {
      final id = map['id'] as String;
      if (_profile.savedRecipeIds.contains(id)) {
        final imageUrl = map['imageUrl'] as String?;
        final image = map['image'] as String?;

        // Calculate real rating & review count from community reviews
        final recipeReviews = _communityReviews
            .where((r) => r.recipeId == id)
            .toList();
        final realReviewCount = recipeReviews.length;
        final realRating = realReviewCount > 0
            ? recipeReviews.map((r) => r.rating).reduce((a, b) => a + b) /
                  realReviewCount
            : 0.0; // Show 0 stars when no reviews

        savedRecipes.add(
          Recipe(
            id: id,
            title: map['title'] as String? ?? 'Untitled',
            imageUrl: imageUrl ?? image ?? '',
            ingredients: (map['ingredients'] as List<dynamic>? ?? [])
                .map((e) => e.toString())
                .toList(),
            ingredientTags: {},
            ingredientMeasurements:
                (map['ingredientMeasurements'] as Map<String, dynamic>?)
                    ?.cast<String, String>() ??
                {},
            cookTimeMinutes: map['cookTime'] as int? ?? 30,
            rating: realRating,
            reviewCount: realReviewCount,
            createdDate: DateTime.now(),
            isSaved: true,
            mealTypes: ['lunch'],
            proteinGrams: 0,
            authorName: map['authorName'] as String? ?? 'Gemini',
            aspectRatio: aspectChoices[random.nextInt(aspectChoices.length)],
            nutrition: map['nutrition'] != null
                ? Nutrition.fromMap(map['nutrition'] as Map<String, dynamic>)
                : null,
            sourceUrl: map['sourceUrl'] as String?,
          ),
        );
      }
    }
    return savedRecipes;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Profile Header
          PotluckProfileHeader(
            userName: _profile.userName,
            avatarUrl: _profile.avatarUrl,
            onAvatarTap: _changeProfilePicture,
          ),

          // Kitchen Stats
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 248, 243, 234),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNewStatItem(
                    _getCookedRecipesCount().toString(),
                    'MADE',
                    Icons.restaurant_menu,
                  ),
                  Container(
                    width: 1,
                    height: 60,
                    color: kMutedGold.withOpacity(0.5),
                  ),
                  _buildNewStatItem(
                    _getSharedRecipesCount().toString(),
                    'SHARED',
                    Icons.room_service,
                  ),
                  Container(
                    width: 1,
                    height: 60,
                    color: kMutedGold.withOpacity(0.5),
                  ),
                  _buildAnimatedStatItem(
                    widget.followerCount,
                    'FOLLOWERS',
                    Icons.people,
                  ),
                ],
              ),
            ),
          ),

          // Tab Bar Section
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _buildTabButton('Saved'),
                _buildTabButton('Cooked'),
                _buildTabButton('My Dishes'),
                _buildTabButton('Dietary'),
              ],
            ),
          ),

          // Dynamic Content based on selected tab
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
            child: _buildTabContentNonSliver(),
          ),
        ],
      ),
    );
  }

  /// Build tab content as regular widgets (non-sliver) for SingleChildScrollView
  Widget _buildTabContentNonSliver() {
    switch (_selectedTab) {
      case 'Saved':
        return _buildSavedRecipesContentNonSliver();
      case 'Cooked':
        return _buildCookedRecipesContentNonSliver();
      case 'My Dishes':
        return _buildMyPlatesContentNonSliver();
      case 'Dietary':
        return _buildMyPalateContentNonSliver();
      default:
        return _buildSavedRecipesContentNonSliver();
    }
  }

  Widget _buildSavedRecipesContentNonSliver() {
    var savedRecipes = _getSavedRecipes();
    savedRecipes = FilterService.filterRecipes(savedRecipes, _profile);
    if (_profile.selectedLifestyles.contains('high-protein')) {
      savedRecipes = FilterService.sortByProtein(savedRecipes, true);
    }
    if (_searchQuery.isNotEmpty) {
      savedRecipes = savedRecipes
          .where(
            (recipe) =>
                recipe.title.toLowerCase().contains(_searchQuery.toLowerCase()),
          )
          .toList();
    }
    if (_selectedMealFilter.isNotEmpty) {
      savedRecipes = savedRecipes
          .where((recipe) => recipe.mealTypes.contains(_selectedMealFilter))
          .toList();
    }
    if (savedRecipes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(
                Icons.favorite_outline,
                size: 48,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              Text(
                _searchQuery.isNotEmpty
                    ? 'No recipes found'
                    : 'No saved recipes yet',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }
    // Use MasonryGridView for staggered layout like Potluck feed
    return MasonryGridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: savedRecipes.length,
      itemBuilder: (context, index) {
        final recipe = savedRecipes[index];
        final imageUrlToUse = recipe.imageUrl.isNotEmpty ? recipe.imageUrl : '';

        // Pantry match logic (same as Potluck feed)
        double matchPercentage = 0.0;
        int missingCount = 0;
        List<String> missingIngredients = const [];
        if (widget.pantryIngredients.isNotEmpty) {
          final pantryNames = widget.pantryIngredients
              .where(
                (ing) =>
                    ing.amount != null &&
                    ((ing.unitType == UnitType.volume &&
                            (ing.amount as double) > 0) ||
                        (ing.unitType != UnitType.volume &&
                            amountAsDouble(ing.amount) > 0)),
              )
              .map((ing) => ing.name.toLowerCase().trim())
              .toSet();
          int matched = 0;
          for (var recipeIng in recipe.ingredients) {
            if (FilterService.isBasicStaple(recipeIng)) {
              matched++;
              continue;
            }
            final hasIngredient = pantryNames.any(
              (pantryNameLower) =>
                  FilterService.ingredientMatches(recipeIng, pantryNameLower),
            );
            if (hasIngredient) matched++;
          }
          matchPercentage = (matched / recipe.ingredients.length) * 100.0;
          missingIngredients = recipe.ingredients.where((recipeIng) {
            if (FilterService.isBasicStaple(recipeIng)) {
              return false;
            }
            final hasIngredient = pantryNames.any(
              (pantryNameLower) =>
                  FilterService.ingredientMatches(recipeIng, pantryNameLower),
            );
            return !hasIngredient;
          }).toList();
          missingCount = missingIngredients.length;
        } else {
          missingCount = recipe.ingredients.length;
          missingIngredients = List<String>.from(recipe.ingredients);
        }

        return RecipeCard(
          sharedIngredients: widget.pantryIngredients,
          onIngredientsUpdated: widget.onIngredientsUpdated,
          recipeTitle: recipe.title,
          recipeIngredients: recipe.ingredients,
          ingredientMeasurements: recipe.ingredientMeasurements,
          cookTime: recipe.cookTimeMinutes,
          rating: recipe.rating,
          reviewCount: recipe.reviewCount,
          matchPercentage: matchPercentage,
          missingCount: missingCount,
          missingIngredients: missingIngredients,
          isReadyToCook: missingCount == 0,
          isRecommendation: false,
          userProfile: _profile,
          onProfileUpdated: _onProfileUpdated,
          recipeId: recipe.id,
          imageUrl: imageUrlToUse,
          aspectRatio: 0.9,
          nutrition: recipe.nutrition,
          titleFontSize: 14,
          onAddCommunityReview: widget.onAddCommunityReview,
          communityReviews: widget.communityReviews,
          sourceUrl: recipe.sourceUrl,
        );
      },
    );
  }

  Widget _buildCookedRecipesContentNonSliver() {
    // Combine user-created recipes with fetched Gemini recipes
    final allRecipeMaps = [
      ..._RecipeFeedScreenState._userRecipes,
      ..._RecipeFeedScreenState._fetchedRecipesCache,
    ];

    // Convert all recipe maps to Recipe objects
    final aspectChoices = [0.85, 0.88, 0.9, 0.92, 0.95];
    final random = Random();

    final cookedRecipes = <Recipe>[];
    for (var map in allRecipeMaps) {
      final id = map['id'] as String;
      if (_profile.cookedRecipeIds.contains(id)) {
        final imageUrl = map['imageUrl'] as String?;
        final image = map['image'] as String?;

        // Calculate real rating & review count from community reviews
        final recipeReviews = _communityReviews
            .where((r) => r.recipeId == id)
            .toList();
        final realReviewCount = recipeReviews.length;
        final realRating = realReviewCount > 0
            ? recipeReviews.map((r) => r.rating).reduce((a, b) => a + b) /
                  realReviewCount
            : 0.0; // Show 0 stars when no reviews

        cookedRecipes.add(
          Recipe(
            id: id,
            title: map['title'] as String? ?? 'Untitled',
            imageUrl: imageUrl ?? image ?? '',
            ingredients: (map['ingredients'] as List<dynamic>? ?? [])
                .map((e) => e.toString())
                .toList(),
            ingredientTags: {},
            ingredientMeasurements:
                (map['ingredientMeasurements'] as Map<String, dynamic>?)
                    ?.cast<String, String>() ??
                {},
            cookTimeMinutes: map['cookTime'] as int? ?? 30,
            rating: realRating,
            reviewCount: realReviewCount,
            createdDate: DateTime.now(),
            isSaved: false,
            mealTypes: ['lunch'],
            proteinGrams: 0,
            authorName: map['authorName'] as String? ?? 'Gemini',
            aspectRatio: aspectChoices[random.nextInt(aspectChoices.length)],
            nutrition: map['nutrition'] != null
                ? Nutrition.fromMap(map['nutrition'] as Map<String, dynamic>)
                : null,
            sourceUrl: map['sourceUrl'] as String?,
          ),
        );
      }
    }

    if (cookedRecipes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(Icons.restaurant, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'No cooked recipes yet',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }
    // Use MasonryGridView for staggered layout like Potluck feed
    return MasonryGridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cookedRecipes.length,
      itemBuilder: (context, index) {
        final recipe = cookedRecipes[index];
        final imageUrlToUse = recipe.imageUrl.isNotEmpty ? recipe.imageUrl : '';

        // Pantry match logic (same as Potluck feed)
        double matchPercentage = 0.0;
        int missingCount = 0;
        List<String> missingIngredients = const [];
        if (widget.pantryIngredients.isNotEmpty) {
          final pantryNames = widget.pantryIngredients
              .where(
                (ing) =>
                    ing.amount != null &&
                    ((ing.unitType == UnitType.volume &&
                            (ing.amount as double) > 0) ||
                        (ing.unitType != UnitType.volume &&
                            amountAsDouble(ing.amount) > 0)),
              )
              .map((ing) => ing.name.toLowerCase().trim())
              .toSet();
          int matched = 0;
          for (var recipeIng in recipe.ingredients) {
            if (FilterService.isBasicStaple(recipeIng)) {
              matched++;
              continue;
            }
            final hasIngredient = pantryNames.any(
              (pantryNameLower) =>
                  FilterService.ingredientMatches(recipeIng, pantryNameLower),
            );
            if (hasIngredient) matched++;
          }
          matchPercentage = (matched / recipe.ingredients.length) * 100.0;
          missingIngredients = recipe.ingredients.where((recipeIng) {
            if (FilterService.isBasicStaple(recipeIng)) {
              return false;
            }
            final hasIngredient = pantryNames.any(
              (pantryNameLower) =>
                  FilterService.ingredientMatches(recipeIng, pantryNameLower),
            );
            return !hasIngredient;
          }).toList();
          missingCount = missingIngredients.length;
        } else {
          missingCount = recipe.ingredients.length;
          missingIngredients = List<String>.from(recipe.ingredients);
        }

        return RecipeCard(
          sharedIngredients: widget.pantryIngredients,
          onIngredientsUpdated: widget.onIngredientsUpdated,
          recipeTitle: recipe.title,
          recipeIngredients: recipe.ingredients,
          ingredientMeasurements: recipe.ingredientMeasurements,
          cookTime: recipe.cookTimeMinutes,
          rating: recipe.rating,
          reviewCount: recipe.reviewCount,
          matchPercentage: matchPercentage,
          missingCount: missingCount,
          missingIngredients: missingIngredients,
          isReadyToCook: missingCount == 0,
          isRecommendation: false,
          userProfile: _profile,
          onProfileUpdated: _onProfileUpdated,
          recipeId: recipe.id,
          imageUrl: imageUrlToUse,
          aspectRatio: 0.9,
          nutrition: recipe.nutrition,
          isCookedTab: true,
          titleFontSize: 14,
          onAddCommunityReview: widget.onAddCommunityReview,
          communityReviews: widget.communityReviews,
          sourceUrl: recipe.sourceUrl,
        );
      },
    );
  }

  Widget _buildMyPlatesContentNonSliver() {
    // Convert all recipe maps to Recipe objects
    final aspectChoices = [0.85, 0.88, 0.9, 0.92, 0.95];
    final random = Random();
    final allRecipes = _RecipeFeedScreenState._userRecipes.map((map) {
      final id = map['id'] as String;
      // Calculate real rating & review count from community reviews
      final recipeReviews = _communityReviews
          .where((r) => r.recipeId == id)
          .toList();
      final realReviewCount = recipeReviews.length;
      final realRating = realReviewCount > 0
          ? recipeReviews.map((r) => r.rating).reduce((a, b) => a + b) /
                realReviewCount
          : 0.0;
      return Recipe(
        id: id,
        title: map['title'] as String,
        imageUrl:
            (map['imageUrl'] as String?) ??
            (map['image'] as String?) ??
            (map['images'] is List && (map['images'] as List).isNotEmpty
                ? (map['images'] as List).first['url'] as String?
                : null) ??
            '',
        ingredients: (map['ingredients'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        ingredientTags: {},
        ingredientMeasurements:
            (map['ingredientMeasurements'] as Map<String, dynamic>?)
                ?.cast<String, String>() ??
            {},
        cookTimeMinutes: map['cookTime'] as int? ?? 30,
        rating: realRating,
        reviewCount: realReviewCount,
        createdDate: DateTime.now(),
        isSaved: false,
        mealTypes: ['lunch'],
        proteinGrams: 0,
        authorName: map['authorName'] as String? ?? 'Anonymous',
        aspectRatio: aspectChoices[random.nextInt(aspectChoices.length)],
      );
    }).toList();

    final myRecipes = allRecipes
        .where((recipe) => recipe.authorName == 'You')
        .toList();
    if (myRecipes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(Icons.share, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'No shared recipes yet',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              Text(
                'Share your favorite recipes with the community',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    // Use MasonryGridView for staggered layout like Potluck feed
    return MasonryGridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: myRecipes.length,
      itemBuilder: (context, index) {
        final recipe = myRecipes[index];
        final imageUrlToUse = recipe.imageUrl.isNotEmpty ? recipe.imageUrl : '';

        // Pantry match logic (same as Potluck feed)
        double matchPercentage = 0.0;
        int missingCount = 0;
        List<String> missingIngredients = const [];
        if (widget.pantryIngredients.isNotEmpty) {
          final pantryNames = widget.pantryIngredients
              .where(
                (ing) =>
                    ing.amount != null &&
                    ((ing.unitType == UnitType.volume &&
                            (ing.amount as double) > 0) ||
                        (ing.unitType != UnitType.volume &&
                            amountAsDouble(ing.amount) > 0)),
              )
              .map((ing) => ing.name.toLowerCase().trim())
              .toSet();
          int matched = 0;
          for (var recipeIng in recipe.ingredients) {
            if (FilterService.isBasicStaple(recipeIng)) {
              matched++;
              continue;
            }
            final hasIngredient = pantryNames.any(
              (pantryNameLower) =>
                  FilterService.ingredientMatches(recipeIng, pantryNameLower),
            );
            if (hasIngredient) matched++;
          }
          matchPercentage = (matched / recipe.ingredients.length) * 100.0;
          missingIngredients = recipe.ingredients.where((recipeIng) {
            if (FilterService.isBasicStaple(recipeIng)) {
              return false;
            }
            final hasIngredient = pantryNames.any(
              (pantryNameLower) =>
                  FilterService.ingredientMatches(recipeIng, pantryNameLower),
            );
            return !hasIngredient;
          }).toList();
          missingCount = missingIngredients.length;
        } else {
          missingCount = recipe.ingredients.length;
          missingIngredients = List<String>.from(recipe.ingredients);
        }

        return RecipeCard(
          sharedIngredients: widget.pantryIngredients,
          onIngredientsUpdated: widget.onIngredientsUpdated,
          recipeTitle: recipe.title,
          recipeIngredients: recipe.ingredients,
          ingredientMeasurements: recipe.ingredientMeasurements,
          cookTime: recipe.cookTimeMinutes,
          rating: recipe.rating,
          reviewCount: recipe.reviewCount,
          matchPercentage: matchPercentage,
          missingCount: missingCount,
          missingIngredients: missingIngredients,
          isReadyToCook: missingCount == 0,
          isRecommendation: false,
          userProfile: _profile,
          onProfileUpdated: _onProfileUpdated,
          recipeId: recipe.id,
          imageUrl: imageUrlToUse,
          aspectRatio: 0.9,
          nutrition: recipe.nutrition,
          isAuthor: true, // Since it's the user's recipe
          titleFontSize: 14,
          onAddCommunityReview: widget.onAddCommunityReview,
          communityReviews: widget.communityReviews,
          onDelete: (id) {
            // Allow deleting user's own recipes
            setState(() {
              _RecipeFeedScreenState._userRecipes.removeWhere(
                (r) => r['id'] == id,
              );
            });
          },
        );
      },
    );
  }

  Widget _buildMyPalateContentNonSliver() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dietary Hub Button
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DietaryHubScreen(
                userProfile: _profile,
                onProfileUpdated: widget.onProfileUpdated,
              ),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: kBoneCreame,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kMutedGold, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.restaurant_menu, color: kDeepForestGreen, size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dietary Requirements',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: kDeepForestGreen,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage allergies & preferences',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 16, color: kMutedGold),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Allergies
        if (_profile.allergies.isNotEmpty) ...[
          Text(
            'Allergies',
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
            children: _profile.allergies.map((allergy) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  allergy,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.red.shade700,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],

        // Avoided Ingredients
        if (_profile.avoided.isNotEmpty) ...[
          Text(
            'Avoided Ingredients',
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
            children: _profile.avoided.map((avoided) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text(
                  avoided,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.orange.shade700,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],

        // Lifestyles (including custom lifestyles)
        if (_profile.selectedLifestyles.isNotEmpty ||
            _profile.customLifestyles.isNotEmpty) ...[
          Text(
            'Lifestyles',
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
            children: [
              // Regular lifestyles
              ..._profile.selectedLifestyles.map((lifestyle) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    lifestyle
                        .replaceAll('-', ' ')
                        .split(' ')
                        .map((w) => w[0].toUpperCase() + w.substring(1))
                        .join(' '),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.blue.shade700,
                    ),
                  ),
                );
              }),
              // Custom lifestyles (only active ones)
              ..._profile.customLifestyles
                  .where(
                    (custom) =>
                        _profile.activeCustomLifestyles.contains(custom.id),
                  )
                  .map((custom) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Text(
                        custom.name.isNotEmpty
                            ? custom.name[0].toUpperCase() +
                                  custom.name.substring(1)
                            : custom.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    );
                  }),
            ],
          ),
          const SizedBox(height: 24),
        ],

        // Empty state if no preferences
        if (_profile.allergies.isEmpty &&
            _profile.avoided.isEmpty &&
            _profile.selectedLifestyles.isEmpty) ...[
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(
                    Icons.restaurant_menu,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No dietary requirements set',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add allergies, avoided ingredients, or lifestyles to personalize your experience',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNewStatItem(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: kMutedGold, size: 24),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: kDeepForestGreen,
            ),
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            color: kSoftSlateGray,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedStatItem(int targetValue, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: kMutedGold, size: 24),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            targetValue.toString(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: kDeepForestGreen,
            ),
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            color: kSoftSlateGray,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildTabButton(String tabName) {
    final isSelected = _selectedTab == tabName;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTab = tabName;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: isSelected
              ? BoxDecoration(
                  color: kDeepForestGreen.withOpacity(0.18), // darker fill
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: kDeepForestGreen.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                )
              : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                tabName.toUpperCase(),
                style: TextStyle(
                  fontSize: 13, // Bigger font size
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.bold, // Bold
                  letterSpacing: 1.0,
                  color: isSelected ? kDeepForestGreen : kSoftSlateGray,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= DIETARY HUB SCREEN =================
class DietaryHubScreen extends StatefulWidget {
  final UserProfile userProfile;
  final Function(UserProfile) onProfileUpdated;

  const DietaryHubScreen({
    super.key,
    required this.userProfile,
    required this.onProfileUpdated,
  });

  @override
  State<DietaryHubScreen> createState() => _DietaryHubScreenState();
}

class _DietaryHubScreenState extends State<DietaryHubScreen> {
  late UserProfile _profile;
  late TextEditingController _searchController;

  static const Map<String, String> _lifestyleDescriptions = {
    'vegan': 'No animal products',
    'vegetarian': 'No meat or fish',
    'keto': 'Low carb, high fat',
    'paleo': 'No grains or processed foods',
    'gluten-free': 'No gluten',
    'pescatarian': 'Fish ok, no land meat',
    'kosher': 'Kosher dietary laws',
    'high-protein': 'High protein focus',
    'dairy-free': 'No dairy products',
    'low-sodium': 'Low salt intake',
    'halal': 'Halal dietary laws',
  };

  static const Map<String, String> _lifestyleFullDefinitions = {
    'vegan': 'No animal products, including meat, dairy, eggs, and honey.',
    'vegetarian': 'No meat or fish, but dairy and eggs are allowed.',
    'keto': 'Low carbohydrate, high fat diet focused on maintaining ketosis.',
    'paleo':
        'Emphasizes whole foods while avoiding grains, legumes, and processed foods.',
    'gluten-free':
        'Eliminates all products containing gluten, a protein found in wheat and other grains.',
    'pescatarian': 'Vegetarian diet that includes fish and seafood.',
    'kosher':
        'Follows Jewish dietary laws with specific restrictions on foods and preparation methods.',
    'high-protein':
        'Diet focused on high protein intake to support muscle development and recovery.',
    'dairy-free':
        'Eliminates all dairy products including milk, cheese, butter, and yogurt.',
    'low-sodium':
        'Restricts salt and high-sodium foods to support heart health and blood pressure management.',
    'halal':
        'Follows Islamic dietary laws allowing only permissible foods prepared according to Islamic guidelines.',
  };

  @override
  void initState() {
    super.initState();
    _profile = widget.userProfile;
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleAllergy(String ingredient) {
    // Capitalize ingredient
    final capitalizedIngredient = ingredient.isNotEmpty
        ? ingredient[0].toUpperCase() + ingredient.substring(1)
        : ingredient;

    setState(() {
      if (_profile.allergies.contains(capitalizedIngredient)) {
        _profile.allergies.remove(capitalizedIngredient);
      } else {
        _profile.allergies.add(capitalizedIngredient);
      }
    });
    _updateProfile();
  }

  void _toggleAvoidance(String ingredient) {
    // Capitalize ingredient
    final capitalizedIngredient = ingredient.isNotEmpty
        ? ingredient[0].toUpperCase() + ingredient.substring(1)
        : ingredient;

    setState(() {
      if (_profile.avoided.contains(capitalizedIngredient)) {
        _profile.avoided.remove(capitalizedIngredient);
      } else {
        _profile.avoided.add(capitalizedIngredient);
      }
    });
    _updateProfile();
  }

  void _toggleLifestyle(String lifestyle) {
    setState(() {
      if (_profile.selectedLifestyles.contains(lifestyle)) {
        _profile.selectedLifestyles.remove(lifestyle);
      } else {
        _profile.selectedLifestyles.add(lifestyle);
      }
    });
    _updateProfile();
  }

  void _toggleCustomLifestyle(String customId) {
    setState(() {
      if (_profile.activeCustomLifestyles.contains(customId)) {
        _profile.activeCustomLifestyles.remove(customId);
      } else {
        _profile.activeCustomLifestyles.add(customId);
      }
    });
    _updateProfile();
  }

  void _deleteCustomLifestyle(String id) {
    setState(() {
      _profile.customLifestyles.removeWhere((cl) => cl.id == id);
      _profile.activeCustomLifestyles.remove(id);
    });
    _updateProfile();
  }

  void _updateProfile() {
    final updated = _profile.copyWith(
      allergies: _profile.allergies,
      avoided: _profile.avoided,
      selectedLifestyles: _profile.selectedLifestyles,
      customLifestyles: _profile.customLifestyles,
      activeCustomLifestyles: _profile.activeCustomLifestyles,
    );
    widget.onProfileUpdated(updated);
  }

  List<String> _getSearchResults() {
    if (_searchController.text.isEmpty) return [];
    final allIngredients = [
      ...FilterService.getAllergyRiskIngredients(),
      ...FilterService.getCommonAvoidanceIngredients(),
    ];
    return allIngredients
        .where(
          (ing) =>
              ing.toLowerCase().contains(_searchController.text.toLowerCase()),
        )
        .toSet()
        .toList();
  }

  bool _hasSearchResults() {
    return _getSearchResults().isNotEmpty;
  }

  String _getSearchQuery() {
    return _searchController.text.trim();
  }

  void _showClassificationDialog(String ingredient) {
    // Capitalize ingredient
    final capitalizedIngredient = ingredient.isNotEmpty
        ? ingredient[0].toUpperCase() + ingredient.substring(1)
        : ingredient;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Classify: $capitalizedIngredient',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'How should we handle this?',
              style: TextStyle(fontSize: 16, color: Colors.black),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _toggleAllergy(ingredient);
                      _clearSearchAfterAdd();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 169, 72, 72),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text(
                            'Allergy',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Will hide recipes entirely',
                            style: TextStyle(color: Colors.black, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _toggleAvoidance(ingredient);
                      _clearSearchAfterAdd();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 232, 207, 137),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text(
                            'Avoid',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Will show an avoid label',
                            style: TextStyle(color: Colors.black, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  void _clearSearchAfterAdd() {
    setState(() {
      _searchController.clear();
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dietary Hub'),
        backgroundColor: kBoneCreame,
        foregroundColor: kDeepForestGreen,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          children: [
            // Smart Search Bar
            _buildSearchSection(),
            const SizedBox(height: 20),

            // Active Restrictions Display
            _buildActiveRestrictionsSection(),
            const SizedBox(height: 20),

            // Lifestyle Grid
            _buildLifestyleGridSection(),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchSection() {
    final results = _getSearchResults();
    final hasResults = _hasSearchResults();
    final searchQuery = _getSearchQuery();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search for restrictions...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ),
        if (searchQuery.isNotEmpty && !hasResults) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showClassificationDialog(searchQuery),
              icon: const Icon(Icons.add),
              label: Text('Add "$searchQuery" as custom'),
            ),
          ),
        ] else if (hasResults) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) {
                final ingredient = results[index];
                final isAdded =
                    _profile.allergies.contains(ingredient) ||
                    _profile.avoided.contains(ingredient);

                return ListTile(
                  title: Text(ingredient),
                  onTap: isAdded
                      ? null
                      : () => _showClassificationDialog(ingredient),
                  trailing: isAdded
                      ? Icon(
                          Icons.check_circle,
                          color: _profile.allergies.contains(ingredient)
                              ? Colors.red
                              : Colors.grey,
                        )
                      : const Icon(
                          Icons.add_circle_outline,
                          color: Colors.grey,
                        ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActiveRestrictionsSection() {
    final allergies = _profile.allergies.toList();
    final avoided = _profile.avoided.toList();
    final lifestyles = _profile.selectedLifestyles.toList();
    final activeCustomLifestyles = _profile.customLifestyles
        .where((cl) => _profile.activeCustomLifestyles.contains(cl.id))
        .toList();

    // Always show the section if any restriction is set (including lifestyles)
    if (allergies.isEmpty &&
        avoided.isEmpty &&
        lifestyles.isEmpty &&
        activeCustomLifestyles.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'My Restrictions',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: [
            // Show lifestyle chips even if allergies/avoided are empty
            ...lifestyles.map(
              (lifestyle) => _buildRestrictionChip(lifestyle, 'lifestyle'),
            ),
            ...activeCustomLifestyles.map(
              (custom) => _buildCustomRestrictionChip(custom),
            ),
            ...allergies.map(
              (allergy) => _buildRestrictionChip(allergy, 'allergy'),
            ),
            ...avoided.map((avoid) => _buildRestrictionChip(avoid, 'avoid')),
          ],
        ),
      ],
    );
  }

  Widget _buildCustomRestrictionChip(CustomLifestyle custom) {
    return Chip(
      label: Text(
        custom.name.isNotEmpty
            ? custom.name[0].toUpperCase() + custom.name.substring(1)
            : custom.name,
        style: TextStyle(
          color: Colors.blue.shade700,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: Colors.blue.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onDeleted: () {
        setState(() {
          _profile.activeCustomLifestyles.remove(custom.id);
        });
        _updateProfile();
      },
    );
  }

  Widget _buildRestrictionChip(String label, String type) {
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

    // Capitalize lifestyle name for chip display
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
      onDeleted: () {
        setState(() {
          if (type == 'allergy') {
            _profile.allergies.remove(label);
          } else if (type == 'avoid') {
            _profile.avoided.remove(label);
          } else if (type == 'lifestyle') {
            _profile.selectedLifestyles.remove(label);
          }
        });
        _updateProfile();
      },
    );
  }

  Widget _buildLifestyleGridSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lifestyles',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.0,
          children: [
            // Default lifestyles
            ..._lifestyleDescriptions.entries.map((entry) {
              final lifestyle = entry.key;
              final description = entry.value;
              final isSelected = _profile.selectedLifestyles.contains(
                lifestyle,
              );

              return _buildLifestyleChip(lifestyle, description, isSelected);
            }),
            // Custom lifestyles
            ..._profile.customLifestyles.map((custom) {
              final isSelected = _profile.activeCustomLifestyles.contains(
                custom.id,
              );
              return _buildCustomLifestyleChip(custom, isSelected);
            }),
            // Add custom button
            _buildAddCustomChip(),
          ],
        ),
      ],
    );
  }

  Widget _buildLifestyleChip(
    String lifestyle,
    String description,
    bool isSelected,
  ) {
    return GestureDetector(
      onTap: () => _toggleLifestyle(lifestyle),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF0F7F4) : kBoneCreame,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? kDeepForestGreen
                : kSoftSlateGray.withValues(alpha: 0.2),
            width: 1.5,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: kDeepForestGreen.withValues(alpha: 0.08),
                blurRadius: 12,
                spreadRadius: 2,
              ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                lifestyle
                    .replaceAll('-', ' ')
                    .split(' ')
                    .map((w) => w[0].toUpperCase() + w.substring(1))
                    .join(' '),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? const Color(0xFF10B981) : Colors.black87,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _showLifestyleDefinition(lifestyle),
              child: Icon(
                Icons.info_outline,
                size: 14,
                color: isSelected
                    ? const Color.fromARGB(255, 114, 200, 171)
                    : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLifestyleDefinition(String lifestyle) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(lifestyle.replaceAll('-', ' ').toUpperCase()),
        content: Text(
          _lifestyleFullDefinitions[lifestyle] ?? 'No definition available.',
          style: const TextStyle(fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showCustomLifestyleDefinition(CustomLifestyle custom) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(custom.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Excludes:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: custom.blockList.map((ingredient) {
                return Chip(
                  label: Text(ingredient),
                  backgroundColor: const Color(0xFFECFDF5),
                  side: const BorderSide(color: Color(0xFF10B981)),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildAddCustomChip() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showCreateCustomLifestyleModal,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300, width: 1.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                'Custom',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateCustomLifestyleModal() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController ingredientController = TextEditingController();
    final Set<String> selectedIngredients = {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey, width: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Create Custom Lifestyle',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name field
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: 'Name your lifestyle',
                          hintText: 'e.g., No Nightshades',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Selected ingredients tags
                      if (selectedIngredients.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Selected Ingredients',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: selectedIngredients.map((ing) {
                                return Chip(
                                  label: Text(ing),
                                  onDeleted: () {
                                    setModalState(() {
                                      selectedIngredients.remove(ing);
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),

                      // Add ingredient field
                      TextField(
                        controller: ingredientController,
                        decoration: InputDecoration(
                          labelText: 'Add ingredient',
                          hintText: 'Type any ingredient and press Add',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () {
                              final ingredient = ingredientController.text
                                  .trim();
                              if (ingredient.isNotEmpty) {
                                setModalState(() {
                                  selectedIngredients.add(ingredient);
                                  ingredientController.clear();
                                });
                              }
                            },
                          ),
                        ),
                        onSubmitted: (value) {
                          final ingredient = ingredientController.text.trim();
                          if (ingredient.isNotEmpty) {
                            setModalState(() {
                              selectedIngredients.add(ingredient);
                              ingredientController.clear();
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
                // Save button
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey, width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed:
                              selectedIngredients.isEmpty ||
                                  nameController.text.isEmpty
                              ? null
                              : () {
                                  _saveCustomLifestyle(
                                    nameController.text,
                                    selectedIngredients.toList(),
                                  );
                                  Navigator.pop(context);
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                (selectedIngredients.isNotEmpty &&
                                    nameController.text.isNotEmpty)
                                ? const Color(0xFF10B981)
                                : Colors.grey,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Save Lifestyle'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _saveCustomLifestyle(String name, List<String> blockList) {
    // Capitalize each ingredient
    final capitalizedBlockList = blockList
        .map(
          (ingredient) => ingredient.isNotEmpty
              ? ingredient[0].toUpperCase() + ingredient.substring(1)
              : ingredient,
        )
        .toList();

    final newCustom = CustomLifestyle(
      id: DateTime.now().toString(),
      name: name,
      blockList: capitalizedBlockList,
    );

    setState(() {
      _profile.customLifestyles.add(newCustom);
      _profile.activeCustomLifestyles.add(newCustom.id);
    });
    _updateProfile();
  }

  Widget _buildCustomLifestyleChip(CustomLifestyle custom, bool isSelected) {
    return Dismissible(
      key: Key(custom.id),
      direction: DismissDirection.endToStart,
      onDismissed: (direction) {
        _deleteCustomLifestyle(custom.id);
      },
      background: Container(
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: () => _toggleCustomLifestyle(custom.id),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFF0F7F4) : kBoneCreame,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? kDeepForestGreen
                  : kSoftSlateGray.withValues(alpha: 0.2),
              width: 1.5,
            ),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: kDeepForestGreen.withValues(alpha: 0.08),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Stack(
            children: [
              // Centered text taking up full 2 lines
              Center(
                child: Text(
                  custom.name.isNotEmpty
                      ? custom.name[0].toUpperCase() + custom.name.substring(1)
                      : custom.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? const Color(0xFF10B981)
                        : Colors.black87,
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Info icon in right-center position
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => _showCustomLifestyleDefinition(custom),
                  child: Icon(
                    Icons.info_outline,
                    size: 14,
                    color: isSelected
                        ? const Color.fromARGB(255, 114, 200, 171)
                        : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= DIETARY RESTRICTIONS MODAL =================
class DietaryRestrictionsModal extends StatefulWidget {
  final UserProfile profile;
  final Function(String) onAllergyToggle;
  final Function(String) onAvoidedToggle;
  final Function(String) onLifestyleToggle;
  final Function(String) onAddCustomRestriction;
  final Function(String) onRemoveCustomRestriction;
  final VoidCallback onClearAllFilters;
  final List<Ingredient> pantryIngredients;

  const DietaryRestrictionsModal({
    super.key,
    required this.profile,
    required this.onAllergyToggle,
    required this.onAvoidedToggle,
    required this.onLifestyleToggle,
    required this.onAddCustomRestriction,
    required this.onRemoveCustomRestriction,
    required this.onClearAllFilters,
    required this.pantryIngredients,
  });

  @override
  State<DietaryRestrictionsModal> createState() =>
      _DietaryRestrictionsModalState();
}

class _DietaryRestrictionsModalState extends State<DietaryRestrictionsModal>
    with SingleTickerProviderStateMixin {
  late TextEditingController _searchController;
  late TextEditingController _customRestrictionController;
  String _searchQuery = '';
  late Set<String> _localAllergies;
  late Set<String> _localAvoided;
  late Set<String> _localLifestyles;
  late List<String> _localCustomRestrictions;
  late TabController _tabController;

  // Lifestyles with descriptions
  static const Map<String, String> _lifestyles = {
    'vegan': 'No animal products',
    'vegetarian': 'No meat or fish',
    'keto': 'Low carb, high fat',
    'paleo': 'No grains or processed foods',
    'gluten-free': 'No gluten',
    'pescatarian': 'Fish ok, no land meat',
    'kosher': 'Kosher dietary laws',
    'high-protein': 'Prioritize high protein',
  };

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _customRestrictionController = TextEditingController();
    _tabController = TabController(length: 3, vsync: this);

    // Create local copies for immediate UI updates
    _localAllergies = Set.from(widget.profile.allergies);
    _localAvoided = Set.from(widget.profile.avoided);
    _localLifestyles = Set.from(widget.profile.selectedLifestyles);
    _localCustomRestrictions = List.from(widget.profile.customRestrictions);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customRestrictionController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _toggleIngredient(String ingredient, bool isAllergy) {
    // Update local state immediately for UI feedback
    setState(() {
      if (isAllergy) {
        if (_localAllergies.contains(ingredient)) {
          _localAllergies.remove(ingredient);
        } else {
          _localAllergies.add(ingredient);
        }
      } else {
        if (_localAvoided.contains(ingredient)) {
          _localAvoided.remove(ingredient);
        } else {
          _localAvoided.add(ingredient);
        }
      }
    });

    // Call parent callback asynchronously
    Future.microtask(() {
      if (isAllergy) {
        widget.onAllergyToggle(ingredient);
      } else {
        widget.onAvoidedToggle(ingredient);
      }
    });
  }

  void _toggleLifestyle(String lifestyle) {
    setState(() {
      if (_localLifestyles.contains(lifestyle)) {
        _localLifestyles.remove(lifestyle);
      } else {
        _localLifestyles.add(lifestyle);
      }
    });

    Future.microtask(() => widget.onLifestyleToggle(lifestyle));
  }

  void _addCustomRestriction() {
    final restriction = _customRestrictionController.text.trim();
    if (restriction.isNotEmpty &&
        !_localCustomRestrictions.contains(restriction)) {
      setState(() {
        _localCustomRestrictions.add(restriction);
      });
      widget.onAddCustomRestriction(restriction);
      _customRestrictionController.clear();
    }
  }

  void _removeCustomRestriction(String restriction) {
    setState(() {
      _localCustomRestrictions.remove(restriction);
    });
    widget.onRemoveCustomRestriction(restriction);
  }

  Color _getLifestyleColor(String lifestyle) {
    switch (lifestyle) {
      case 'vegan':
        return Colors.green;
      case 'vegetarian':
        return Colors.lime;
      case 'keto':
        return Colors.purple;
      case 'paleo':
        return Colors.brown;
      case 'gluten-free':
        return Colors.amber;
      case 'pescatarian':
        return Colors.blue;
      case 'kosher':
        return Colors.deepOrange;
      case 'high-protein':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Dietary Requirements',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.grey,
                        ),
                        onPressed: widget.onClearAllFilters,
                        tooltip: 'Clear all filters',
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Tab Bar
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Ingredients'),
                Tab(text: 'Lifestyles'),
                Tab(text: 'Custom'),
              ],
            ),
            Divider(color: Colors.grey.shade200),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // ===== INGREDIENTS TAB =====
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Search Bar
                      TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          setState(() => _searchQuery = value);
                        },
                        decoration: InputDecoration(
                          hintText: 'Search ingredients...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Allergies Section - only allergy risk ingredients
                      _buildRestrictionSection(
                        'Allergies',
                        '⚠️',
                        Colors.red.shade200,
                        _localAllergies,
                        (ingredient) => _toggleIngredient(ingredient, true),
                        FilterService.getAllergyRiskIngredients(),
                        true,
                      ),
                      const SizedBox(height: 24),

                      // Avoided Ingredients Section - only common avoidance ingredients
                      _buildRestrictionSection(
                        'Avoid',
                        '👎',
                        Colors.orange.shade200,
                        _localAvoided,
                        (ingredient) => _toggleIngredient(ingredient, false),
                        FilterService.getCommonAvoidanceIngredients(),
                        false,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),

                  // ===== LIFESTYLES TAB =====
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Select your dietary lifestyle(s)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: _lifestyles.entries.map((entry) {
                          final lifestyle = entry.key;
                          final description = entry.value;
                          final isSelected = _localLifestyles.contains(
                            lifestyle,
                          );
                          final color = _getLifestyleColor(lifestyle);

                          return GestureDetector(
                            onTap: () => _toggleLifestyle(lifestyle),
                            child: Container(
                              width:
                                  (MediaQuery.of(context).size.width - 48) / 2,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? color.withOpacity(0.15)
                                    : Colors.grey.shade50,
                                border: Border.all(
                                  color: isSelected
                                      ? color
                                      : Colors.grey.shade300,
                                  width: isSelected ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          lifestyle
                                              .replaceAll('-', ' ')
                                              .split(' ')
                                              .map(
                                                (w) =>
                                                    w[0].toUpperCase() +
                                                    w.substring(1),
                                              )
                                              .join(' '),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected
                                                ? Colors.black87
                                                : Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        Icon(
                                          Icons.check_circle,
                                          color: color,
                                          size: 20,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    description,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),

                  // ===== CUSTOM RESTRICTIONS TAB =====
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Add custom restrictions',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _customRestrictionController,
                              onSubmitted: (_) => _addCustomRestriction(),
                              decoration: InputDecoration(
                                hintText: 'Enter restriction...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _addCustomRestriction,
                            icon: const Icon(Icons.add),
                            label: const Text('Add'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (_localCustomRestrictions.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Your Custom Restrictions (${_localCustomRestrictions.length})',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _localCustomRestrictions.map((restriction) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                border: Border.all(color: Colors.blue.shade200),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    restriction,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () =>
                                        _removeCustomRestriction(restriction),
                                    child: Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.blue.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestrictionSection(
    String title,
    String emoji,
    Color color,
    Set<String> restrictedItems,
    Function(String) onToggle,
    List<String> ingredients,
    bool isAllergy,
  ) {
    final filteredIngredients = ingredients
        .where(
          (ing) =>
              _searchQuery.isEmpty ||
              ing.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();

    if (filteredIngredients.isEmpty && _searchQuery.isNotEmpty) {
      return SizedBox.shrink();
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
}

// ================= 7. HUB SCREEN (Profile + Dietary Hub) =================
class HubScreen extends StatefulWidget {
  final List<Ingredient> pantryIngredients;
  final Function(List<Ingredient>) onIngredientsUpdated;
  final UserProfile userProfile;
  final Function(UserProfile) onProfileUpdated;
  final Function(CommunityReview)? onAddCommunityReview;
  final List<CommunityReview> communityReviews;
  final int followerCount;

  const HubScreen({
    super.key,
    this.pantryIngredients = const [],
    required this.onIngredientsUpdated,
    required this.userProfile,
    required this.onProfileUpdated,
    this.onAddCommunityReview,
    required this.communityReviews,
    this.followerCount = 0,
  });

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  late UserProfile _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.userProfile;
  }

  @override
  void didUpdateWidget(HubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userProfile != widget.userProfile) {
      setState(() {
        _profile = widget.userProfile;
      });
    }
  }

  void _showSettingsMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: kBoneCreame,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Settings',
              style: TextStyle(
                fontFamily: 'Lora',
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: kDeepForestGreen,
              ),
            ),
            const SizedBox(height: 8),
            if (FirebaseService.currentUser?.email != null)
              Text(
                FirebaseService.currentUser!.email!,
                style: TextStyle(fontSize: 13, color: kSoftSlateGray),
              ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.logout, color: kDeepForestGreen),
              title: const Text('Sign Out'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onTap: () async {
                Navigator.pop(ctx);
                await FirebaseService.signOut();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_forever, color: Colors.red.shade700),
              title: Text('Delete Account', style: TextStyle(color: Colors.red.shade700)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteAccount(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBoneCreame,
        title: const Text('Delete Account?', style: TextStyle(color: kDeepForestGreen)),
        content: const Text(
          'This will permanently delete your account, recipes, and followers. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseService.deleteAccount();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: kBoneCreame,
        foregroundColor: kDeepForestGreen,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, size: 24),
            tooltip: 'Settings',
            onPressed: () => _showSettingsMenu(context),
          ),
        ],
      ),
      body: ProfileScreen(
        pantryIngredients: widget.pantryIngredients,
        onIngredientsUpdated: widget.onIngredientsUpdated,
        userProfile: _profile,
        onProfileUpdated: widget.onProfileUpdated,
        onAddCommunityReview: widget.onAddCommunityReview,
        communityReviews: widget.communityReviews,
        followerCount: widget.followerCount,
      ),
    );
  }
}

// ================= 8. SHOPPING LIST SCREEN =================
class ShoppingListScreen extends StatefulWidget {
  final List<Ingredient> pantryIngredients;
  final Function(String ingredientId) onRestock;
  final Function(List<Ingredient>) onAddIngredients;
  final Function(String ingredientId)? onDismissRestock;

  const ShoppingListScreen({
    super.key,
    required this.pantryIngredients,
    required this.onRestock,
    required this.onAddIngredients,
    this.onDismissRestock,
  });

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

// Shopping list model for multiple lists
class ShoppingList {
  final String id;
  String name;
  List<ShoppingItem> items;

  ShoppingList({
    required this.id,
    required this.name,
    List<ShoppingItem>? items,
  }) : items = items ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'items': items.map((i) => i.toJson()).toList(),
  };

  factory ShoppingList.fromJson(Map<String, dynamic> json) {
    return ShoppingList(
      id: json['id'],
      name: json['name'],
      items:
          (json['items'] as List<dynamic>?)
              ?.map((i) => ShoppingItem.fromJson(i))
              .toList() ??
          [],
    );
  }
}

class ShoppingItem {
  final String id;
  final String name;
  String quantity;
  final String unit;
  final bool isFromRestock;
  bool isChecked;

  ShoppingItem({
    required this.id,
    required this.name,
    this.quantity = '1',
    required this.unit,
    required this.isFromRestock,
    this.isChecked = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'quantity': quantity,
    'unit': unit,
    'isFromRestock': isFromRestock,
    'isChecked': isChecked,
  };

  factory ShoppingItem.fromJson(Map<String, dynamic> json) {
    return ShoppingItem(
      id: json['id'],
      name: json['name'],
      quantity: json['quantity'] ?? '1',
      unit: json['unit'] ?? 'ea',
      isFromRestock: json['isFromRestock'] ?? false,
      isChecked: json['isChecked'] ?? false,
    );
  }
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  String _currentPage = 'lists'; // Start on 'lists' tab (renamed from 'active')
  List<ShoppingItem> _restockItems = []; // Initialize as empty list
  List<ShoppingList> _shoppingLists = [];
  String? _selectedListId;
  Set<String> _dismissedRestockIds = {}; // Track dismissed restock items
  final TextEditingController _manualAddController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController(
    text: '1',
  );

  @override
  void initState() {
    super.initState();
    _loadDismissedRestockIds().then((_) {
      // Build restock list after loading dismissed IDs
      _restockItems = widget.pantryIngredients
          .where(
            (ing) =>
                ing.needsPurchase && !_dismissedRestockIds.contains(ing.id),
          )
          .map(
            (ing) => ShoppingItem(
              id: ing.id,
              name: ing.name,
              unit: ing.baseUnit,
              isFromRestock: true,
            ),
          )
          .toList();
      if (mounted) setState(() {});
    });
    _loadShoppingLists(); // Then load shopping lists (async)
  }

  @override
  void didUpdateWidget(ShoppingListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rebuild restock list when pantry changes
    if (oldWidget.pantryIngredients != widget.pantryIngredients) {
      _buildRestockList();
    }
  }

  @override
  void dispose() {
    _manualAddController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _loadShoppingLists() async {
    final prefs = await SharedPreferences.getInstance();
    final listsJson = prefs.getStringList('shopping_lists') ?? [];

    setState(() {
      _shoppingLists = listsJson
          .map((json) => ShoppingList.fromJson(jsonDecode(json)))
          .toList();

      // Create default list if none exist
      if (_shoppingLists.isEmpty) {
        _shoppingLists.add(
          ShoppingList(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: 'My Shopping List',
          ),
        );
        _saveShoppingLists();
      }

      _selectedListId = _shoppingLists.first.id;
    });
  }

  Future<void> _saveShoppingLists() async {
    final prefs = await SharedPreferences.getInstance();
    final listsJson = _shoppingLists
        .map((list) => jsonEncode(list.toJson()))
        .toList();
    await prefs.setStringList('shopping_lists', listsJson);
  }

  void _buildRestockList() {
    // Items with quantity = 0 appear in restock list (excluding dismissed ones)
    setState(() {
      _restockItems = widget.pantryIngredients
          .where(
            (ing) =>
                ing.needsPurchase && !_dismissedRestockIds.contains(ing.id),
          )
          .map(
            (ing) => ShoppingItem(
              id: ing.id,
              name: ing.name,
              unit: ing.baseUnit,
              isFromRestock: true,
            ),
          )
          .toList();
    });
  }

  Future<void> _loadDismissedRestockIds() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getStringList('dismissed_restock_ids') ?? [];
    _dismissedRestockIds = Set<String>.from(dismissed);
  }

  Future<void> _saveDismissedRestockIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'dismissed_restock_ids',
      _dismissedRestockIds.toList(),
    );
  }

  ShoppingList? get _selectedList {
    if (_selectedListId == null) return null;
    try {
      return _shoppingLists.firstWhere((l) => l.id == _selectedListId);
    } catch (_) {
      return _shoppingLists.isNotEmpty ? _shoppingLists.first : null;
    }
  }

  void _moveToList(ShoppingItem item) {
    if (_selectedList == null) return;
    setState(() {
      _restockItems.removeWhere((i) => i.id == item.id);
      _selectedList!.items.add(item);
    });
    _saveShoppingLists();
  }

  void _dismissFromRestock(String itemId) {
    setState(() {
      _restockItems.removeWhere((i) => i.id == itemId);
      _dismissedRestockIds.add(itemId);
    });
    _saveDismissedRestockIds();
    widget.onDismissRestock?.call(itemId);
  }

  void _addManualItem() {
    final name = _manualAddController.text.trim();
    final quantity = _quantityController.text.trim();
    if (name.isNotEmpty && _selectedList != null) {
      setState(() {
        _selectedList!.items.add(
          ShoppingItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: name,
            quantity: quantity.isNotEmpty ? quantity : '1',
            unit: 'ea',
            isFromRestock: false,
          ),
        );
      });
      _manualAddController.clear();
      _quantityController.text = '1';
      _saveShoppingLists();
    }
  }

  void _removeFromList(String itemId) {
    if (_selectedList == null) return;
    setState(() {
      _selectedList!.items.removeWhere((i) => i.id == itemId);
    });
    _saveShoppingLists();
  }

  void _checkOffItem(ShoppingItem item) {
    // When checked, update pantry if it came from restock
    if (item.isFromRestock) {
      widget.onRestock(item.id);
    }

    setState(() {
      item.isChecked = true;
    });

    // Remove after brief delay for visual feedback
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _removeFromList(item.id);
      }
    });
  }

  void _createNewList() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New List'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'List name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  final newList = ShoppingList(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: controller.text.trim(),
                  );
                  _shoppingLists.add(newList);
                  _selectedListId = newList.id;
                });
                _saveShoppingLists();
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: kDeepForestGreen),
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showListOptions(ShoppingList list) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              list.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: kDeepForestGreen,
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.edit, color: kDeepForestGreen),
              title: const Text('Rename List'),
              onTap: () {
                Navigator.pop(context);
                _renameList(list);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: kSoftTerracotta),
              title: const Text(
                'Delete List',
                style: TextStyle(color: kSoftTerracotta),
              ),
              onTap: () {
                Navigator.pop(context);
                _deleteList(list);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _renameList(ShoppingList list) {
    final controller = TextEditingController(text: list.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename List'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  list.name = controller.text.trim();
                });
                _saveShoppingLists();
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: kDeepForestGreen),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _deleteList(ShoppingList list) {
    if (_shoppingLists.length <= 1) {
      // Can't delete the last list
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete List?'),
        content: Text('Are you sure you want to delete "${list.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _shoppingLists.removeWhere((l) => l.id == list.id);
                if (_selectedListId == list.id) {
                  _selectedListId = _shoppingLists.first.id;
                }
              });
              _saveShoppingLists();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: kSoftTerracotta),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopping List'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Toggle between pages
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _currentPage = 'lists'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _currentPage == 'lists'
                            ? kDeepForestGreen
                            : Colors.grey.shade100,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          bottomLeft: Radius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Lists (${_selectedList?.items.length ?? 0})',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _currentPage == 'lists'
                              ? Colors.white
                              : kCharcoal,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _currentPage = 'restock'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _currentPage == 'restock'
                            ? kDeepForestGreen
                            : Colors.grey.shade100,
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Restock (${_restockItems.length})',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _currentPage == 'restock'
                              ? Colors.white
                              : kCharcoal,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Page content
          Expanded(
            child: _currentPage == 'restock'
                ? _buildRestockPage()
                : _buildListsPage(),
          ),
        ],
      ),
    );
  }

  Widget _buildRestockPage() {
    if (_restockItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 60, color: kSageGreen),
            const SizedBox(height: 12),
            Text(
              'All stocked up!',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Text(
              'No ingredients need restocking',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      itemCount: _restockItems.length,
      itemBuilder: (context, index) {
        final item = _restockItems[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Out of stock',
                        style: TextStyle(fontSize: 12, color: kSoftTerracotta),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => _moveToList(item),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kSageGreen,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  child: const Text(
                    'Add to List',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => _dismissFromRestock(item.id),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildListsPage() {
    return Column(
      children: [
        // All lists horizontal scroll view
        if (_shoppingLists.length > 1)
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _shoppingLists.length + 1, // +1 for add button
              itemBuilder: (context, index) {
                if (index == _shoppingLists.length) {
                  // Add new list button
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: _createNewList,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.grey.shade300,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add, size: 18, color: kDeepForestGreen),
                            const SizedBox(width: 4),
                            Text(
                              'New List',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: kDeepForestGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                final list = _shoppingLists[index];
                final isSelected = list.id == _selectedListId;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedListId = list.id;
                      });
                    },
                    onLongPress: () => _showListOptions(list),
                    child: Container(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 8,
                        top: 8,
                        bottom: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? kDeepForestGreen
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? kDeepForestGreen
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            list.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : kCharcoal,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white.withOpacity(0.2)
                                  : kDeepForestGreen.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              list.items.length.toString(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.white
                                    : kDeepForestGreen,
                              ),
                            ),
                          ),
                          // X button to delete list (only if more than 1 list)
                          if (_shoppingLists.length > 1) ...[
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => _deleteList(list),
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: isSelected
                                    ? Colors.white70
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        if (_shoppingLists.length > 1) const SizedBox(height: 12),
        // Single list header (shown when only 1 list exists)
        if (_shoppingLists.length == 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _shoppingLists.first.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: kDeepForestGreen,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.add_circle_outline,
                    color: kDeepForestGreen,
                  ),
                  onPressed: _createNewList,
                  tooltip: 'Create new list',
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: kDeepForestGreen),
                  onSelected: (value) {
                    if (_selectedList == null) return;
                    if (value == 'rename') {
                      _renameList(_selectedList!);
                    } else if (value == 'delete') {
                      _deleteList(_selectedList!);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        // Manual add input with quantity
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _manualAddController,
                  decoration: InputDecoration(
                    hintText: 'Add item...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Qty',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addManualItem,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kDeepForestGreen,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Checklist
        Expanded(
          child: _selectedList == null || _selectedList!.items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shopping_cart_outlined,
                        size: 60,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Your list is empty',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add items above or from the Restock tab',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: _selectedList!.items.length,
                  itemBuilder: (context, index) {
                    final item = _selectedList!.items[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: item.isChecked
                            ? Colors.grey.shade100
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: item.isChecked
                              ? Colors.grey.shade300
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: ListTile(
                        leading: GestureDetector(
                          onTap: () => _checkOffItem(item),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: item.isChecked
                                  ? kSageGreen
                                  : Colors.transparent,
                              border: Border.all(
                                color: item.isChecked
                                    ? kSageGreen
                                    : Colors.grey.shade400,
                              ),
                            ),
                            child: item.isChecked
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 20,
                                  )
                                : null,
                          ),
                        ),
                        title: Text(
                          item.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: item.isChecked
                                ? Colors.grey.shade500
                                : kCharcoal,
                            decoration: item.isChecked
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        subtitle: item.quantity != '1'
                            ? Text(
                                'Qty: ${item.quantity}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              )
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => _removeFromList(item.id),
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ================= 9. ADD INGREDIENT SCREEN DUPLICATE CLEANUP =================
// Note: This section and all code until the end of the file needs to be removed
// All classes after _ShoppingListScreenState should be deleted as they are duplicates or orphaned code

// ================= 3. ADD INGREDIENTS SCREEN =================
class AddIngredientScreen extends StatefulWidget {
  final Function(int) onSwitchTab;
  final Function(List<Ingredient>) onAddIngredients;

  const AddIngredientScreen({
    super.key,
    required this.onSwitchTab,
    required this.onAddIngredients,
  });

  @override
  State<AddIngredientScreen> createState() => _AddIngredientScreenState();
}

class _AddIngredientScreenState extends State<AddIngredientScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _ingredientController = TextEditingController();
  final List<Ingredient> _quickAddedIngredients = [];
  IngredientCategory _selectedCategory = IngredientCategory.produce;

  @override
  void dispose() {
    _ingredientController.dispose();
    super.dispose();
  }

  void _addQuickIngredient() {
    final name = _ingredientController.text.trim();

    if (name.isEmpty) {
      return;
    }

    // Use default values - count type with amount 1
    final ingredient = Ingredient(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      category: _selectedCategory,
      unitType: UnitType.count,
      amount: 1,
      baseUnit: 'ea',
    );

    setState(() {
      _quickAddedIngredients.add(ingredient);
      _ingredientController.clear();
      _selectedCategory = IngredientCategory.produce;
    });
  }

  void _removeQuickIngredient(int index) {
    setState(() {
      _quickAddedIngredients.removeAt(index);
    });
  }

  Future<void> _processImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null && mounted) {
        // Navigate to confirmation screen with the image
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ConfirmDetectedItemsScreen(
              imageFile: File(image.path),
              onAddIngredients: widget.onAddIngredients,
            ),
          ),
        );
      }
    } catch (e) {
      // Image selection error - silently handle
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Add Ingredients'),
        backgroundColor: kBoneCreame,
        foregroundColor: kDeepForestGreen,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24.0,
              40.0,
              24.0,
              80.0 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // Camera and Gallery Buttons (Side by Side)
                Row(
                  children: [
                    Expanded(
                      child: _buildOptionButton(
                        icon: Icons.camera_alt,
                        label: 'Scan Fridge',
                        subtitle: 'Take a Photo',
                        onTap: () => _processImage(ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildOptionButton(
                        icon: Icons.image,
                        label: 'Upload Image',
                        subtitle: 'From Gallery',
                        onTap: () => _processImage(ImageSource.gallery),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                // Quick Add Section
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick Add',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: kDeepForestGreen,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Name field
                    TextField(
                      controller: _ingredientController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Ingredient Name',
                        hintText: 'e.g., Tomatoes, Milk',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Category pill boxes
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Category',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: IngredientCategory.values.map((category) {
                            final isSelected = _selectedCategory == category;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedCategory = category;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? kDeepForestGreen
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? kDeepForestGreen
                                        : Colors.grey.shade300,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Text(
                                  category.displayName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Add button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _addQuickIngredient,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kDeepForestGreen,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Add Ingredient',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Display added ingredients
                    if (_quickAddedIngredients.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _quickAddedIngredients.asMap().entries.map((
                          entry,
                        ) {
                          final index = entry.key;
                          final ing = entry.value;
                          // Format quantity based on unit type
                          final quantityStr = ing.unitType == UnitType.volume
                              ? (() {
                                  final amount = ing.amount as double;
                                  // Remove .0 from whole numbers
                                  if (amount == amount.round()) {
                                    return amount.round().toString();
                                  }
                                  return amount.toStringAsFixed(1);
                                })()
                              : ing.amount.toString();
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: kSageGreen.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: kSageGreen),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      ing.name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: kDeepForestGreen,
                                      ),
                                    ),
                                    Text(
                                      '$quantityStr ${ing.baseUnit}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: kSoftSlateGray,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => _removeQuickIngredient(index),
                                  child: Icon(
                                    Icons.close,
                                    size: 16,
                                    color: kDeepForestGreen,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    if (_quickAddedIngredients.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            if (_quickAddedIngredients.isEmpty) return;
                            // Copy the list before clearing
                            final ingredientsToAdd = List<Ingredient>.from(
                              _quickAddedIngredients,
                            );
                            // Clear local state first
                            setState(() {
                              _quickAddedIngredients.clear();
                            });
                            // Add ingredients to pantry
                            widget.onAddIngredients(ingredientsToAdd);
                            // Switch tab after a frame to avoid rebuild issues
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                widget.onSwitchTab(0);
                              }
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kSageGreen,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Save Ingredients',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    bool isFullWidth = false,
  }) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: isFullWidth ? 20 : 28,
          horizontal: 24,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kDeepForestGreen, width: 2),
          boxShadow: [
            BoxShadow(
              color: kDeepForestGreen.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: isFullWidth
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 36, color: kDeepForestGreen),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: kDeepForestGreen,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: kSoftSlateGray),
                      ),
                    ],
                  ),
                ],
              )
            : Column(
                children: [
                  Icon(icon, size: 48, color: kDeepForestGreen),
                  const SizedBox(height: 16),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: kDeepForestGreen,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: kSoftSlateGray),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
      ),
    );

    return isFullWidth
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}

// ================= CONFIRM DETECTED ITEMS SCREEN =================
class ConfirmDetectedItemsScreen extends StatefulWidget {
  final File imageFile;
  final Function(List<Ingredient>) onAddIngredients;

  const ConfirmDetectedItemsScreen({
    super.key,
    required this.imageFile,
    required this.onAddIngredients,
  });

  @override
  State<ConfirmDetectedItemsScreen> createState() =>
      _ConfirmDetectedItemsScreenState();
}

class _ConfirmDetectedItemsScreenState
    extends State<ConfirmDetectedItemsScreen> {
  late Future<List<Ingredient>> _detectionFuture;
  List<Ingredient> _detectedItems = [];
  bool _isLoading = true;
  String? _errorMessage;
  final ScrollController _ingredientsScrollController = ScrollController();

  // Rate limit protection
  DateTime? _lastApiCallTime;
  static const int _minSecondsBetweenCalls = 60;

  @override
  void initState() {
    super.initState();
    _detectionFuture = _detectAndClassifyWithGemini();
  }

  @override
  void dispose() {
    _ingredientsScrollController.dispose();
    super.dispose();
  }

  /// Check if rate limit protection allows API call
  bool _canMakeApiCall() {
    if (_lastApiCallTime == null) return true;

    final secondsElapsed = DateTime.now()
        .difference(_lastApiCallTime!)
        .inSeconds;
    return secondsElapsed >= _minSecondsBetweenCalls;
  }

  /// Get seconds remaining until next API call is allowed
  int _getSecondsUntilNextCall() {
    if (_lastApiCallTime == null) return 0;

    final secondsElapsed = DateTime.now()
        .difference(_lastApiCallTime!)
        .inSeconds;
    final remaining = _minSecondsBetweenCalls - secondsElapsed;
    return remaining > 0 ? remaining : 0;
  }

  /// Main method: Detect and classify ingredients using Gemini 2.0 Flash
  /// Single API call combines detection AND categorization - NO RETRIES
  Future<List<Ingredient>> _detectAndClassifyWithGemini() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // ===== RATE LIMIT PROTECTION =====
      if (!_canMakeApiCall()) {
        final secondsToWait = _getSecondsUntilNextCall();
        throw Exception(
          'Rate limit: Please wait $secondsToWait seconds before trying again (1 request per 60 seconds)',
        );
      }

      // Read and encode the image
      final bytes = await widget.imageFile.readAsBytes();
      final compressedBytes = await _compressImage(bytes);
      final base64Image = base64Encode(compressedBytes);

      // ===== SINGLE API CALL (NO RETRIES) =====
      // Using Gemini 2.0 Flash for ingredient detection (image analysis)
      final response = await http.post(
        Uri.parse(GeminiConfig.detectionEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text':
                      'Identify all visible ingredients in this food image. Return a JSON array with objects containing name, category, unit, and amount for each ingredient.',
                },
                {
                  'inline_data': {
                    'mime_type': 'image/jpeg',
                    'data': base64Image,
                  },
                },
              ],
            },
          ],
          'generationConfig': {
            'temperature': 0.2,
            'topP': 0.95,
            'topK': 40,
            'maxOutputTokens': 8192,
            'responseMimeType': 'application/json',
          },
        }),
      );

      // ===== ERROR HANDLING (NO RETRIES - SINGLE ATTEMPT ONLY) =====
      if (response.statusCode == 429) {
        // Rate limit from Gemini API - inform user with wait time
        final retryAfter = response.headers['retry-after'];
        final waitSeconds = retryAfter != null
            ? int.tryParse(retryAfter) ?? 60
            : 60;
        throw Exception(
          'API rate limit (429): The service is temporarily unavailable. Please wait at least $waitSeconds seconds and try again.',
        );
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception(
          'Authentication failed (${response.statusCode}): Please verify your API key is valid and has the necessary permissions.',
        );
      } else if (response.statusCode == 400) {
        final errorBody = jsonDecode(response.body);
        final errorMessage =
            errorBody['error']?['message'] ?? 'Invalid request';
        throw Exception('Invalid request (400): $errorMessage');
      } else if (response.statusCode == 500 || response.statusCode == 503) {
        throw Exception(
          'Server error (${response.statusCode}): The Gemini service is temporarily unavailable. Please try again in a moment.',
        );
      } else if (response.statusCode != 200) {
        throw Exception(
          'API error (${response.statusCode}): Failed to process image. Please try again.',
        );
      }

      // Parse the response
      final data = jsonDecode(response.body);

      // Check for API errors in the response body
      if (data.containsKey('error')) {
        final error = data['error'];
        final message = error['message'] ?? 'Unknown error';
        throw Exception('API error: $message');
      }

      // Safety check for expected response structure
      if (!data.containsKey('candidates') ||
          data['candidates'].isEmpty ||
          !data['candidates'][0].containsKey('content')) {
        throw Exception('Unexpected response format from Gemini API');
      }

      final responseText =
          data['candidates'][0]['content']['parts'][0]['text'] as String;

      // Convert to Ingredient objects
      final ingredients = _parseGeminiResponse(responseText);

      if (!mounted) return []; // Widget was disposed

      setState(() {
        _detectedItems = ingredients;
        _isLoading = false;
      });

      return ingredients;
    } catch (e) {
      if (!mounted) return []; // Widget was disposed

      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
      return [];
    }
  }

  /// Compress image to reduce API payload size and stay under rate limits
  /// Returns original bytes if small enough, otherwise returns as-is
  /// (Flutter's built-in codec doesn't support JPEG encoding, so we skip resize)
  Future<Uint8List> _compressImage(Uint8List bytes) async => bytes;

  /// Parse Gemini's JSON response into Ingredient objects
  /// Safely handles both raw JSON and markdown-wrapped JSON
  List<Ingredient> _parseGeminiResponse(String responseText) {
    try {
      // Clean response: remove markdown code blocks if present
      String cleanedText = responseText.trim();
      if (cleanedText.startsWith('```json')) {
        cleanedText = cleanedText.substring(7); // Remove ```json
      } else if (cleanedText.startsWith('```')) {
        cleanedText = cleanedText.substring(3); // Remove ```
      }
      if (cleanedText.endsWith('```')) {
        cleanedText = cleanedText.substring(
          0,
          cleanedText.length - 3,
        ); // Remove trailing ```
      }
      cleanedText = cleanedText.trim();

      // Parse the JSON array
      final data = jsonDecode(cleanedText) as List;

      // Convert each item to an Ingredient
      return data.map((item) {
        final categoryStr = item['category'] as String? ?? '';
        final category = _stringToCategory(categoryStr);
        final unit = item['unit'] as String? ?? 'ea';
        final name = item['name'] as String? ?? 'Unknown Item';
        final unitType = _getUnitTypeFromString(unit);

        // Parse amount from AI response, with fallback to defaults
        dynamic amount = item['amount'];
        if (amount == null) {
          // Fallback to default amount if AI didn't provide one
          amount = unitType == UnitType.volume ? 1.0 : 1;
        } else {
          // Ensure correct type based on unitType
          if (unitType == UnitType.volume) {
            amount = (amount as num).toDouble();
          } else {
            final parsed = (amount as num).toDouble();
            amount = parsed == parsed.roundToDouble() ? parsed.toInt() : parsed;
          }
        }

        return Ingredient(
          id:
              DateTime.now().millisecondsSinceEpoch.toString() +
              Random().nextInt(10000).toString(),
          name: name,
          category: category,
          unitType: unitType,
          amount: amount,
          baseUnit: unit,
        );
      }).toList();
    } catch (e) {
      throw Exception(
        'Failed to parse ingredient data. The API response was not in the expected format.',
      );
    }
  }

  /// Convert category string to enum (handles both display names and normalized names)
  IngredientCategory _stringToCategory(String categoryStr) {
    final normalized = categoryStr.toLowerCase().trim();

    // Handle the new format which uses display names
    switch (normalized) {
      case 'proteins':
        return IngredientCategory.proteins;
      case 'produce':
        return IngredientCategory.produce;
      case 'dairy & refrigerated':
      case 'dairyrefrigerated':
      case 'dairy':
        return IngredientCategory.dairyRefrigerated;
      case 'grains & legumes':
      case 'grainslegumes':
      case 'grains':
        return IngredientCategory.grainsLegumes;
      case 'canned goods':
      case 'cannedgoods':
      case 'canned':
        return IngredientCategory.cannedGoods;
      case 'condiments & sauces':
      case 'condimentssauces':
      case 'condiments':
        return IngredientCategory.condimentsSauces;
      case 'spices & seasonings':
      case 'spicesseasonings':
      case 'spices':
        return IngredientCategory.spicesSeasonings;
      case 'frozen':
        return IngredientCategory.frozen;
      case 'baking':
        return IngredientCategory.baking;
      case 'snacks & extras':
      case 'snacksextras':
      case 'snacks':
        return IngredientCategory.snacksExtras;
      default:
        return IngredientCategory.produce;
    }
  }

  /// Determine UnitType from string
  UnitType _getUnitTypeFromString(String unit) {
    final lower = unit.toLowerCase();
    if (lower.contains('ml') ||
        lower.contains('liter') ||
        lower.contains('cup') ||
        lower.contains('tbsp')) {
      return UnitType.volume;
    } else if (lower.contains('gram') ||
        lower.contains('kg') ||
        lower.contains('oz')) {
      return UnitType.weight;
    }
    return UnitType.count;
  }

  Map<IngredientCategory, List<Ingredient>> _groupByCategory(
    List<Ingredient> items,
  ) {
    final grouped = <IngredientCategory, List<Ingredient>>{};
    final categoryOrder = [
      IngredientCategory.produce,
      IngredientCategory.proteins,
      IngredientCategory.dairyRefrigerated,
      IngredientCategory.grainsLegumes,
      IngredientCategory.cannedGoods,
      IngredientCategory.frozen,
      IngredientCategory.condimentsSauces,
      IngredientCategory.spicesSeasonings,
      IngredientCategory.baking,
      IngredientCategory.snacksExtras,
    ];

    // Initialize all categories in order
    for (var category in categoryOrder) {
      grouped[category] = [];
    }

    // Sort items into categories
    for (var item in items) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    return grouped;
  }

  void _showQuantityAdjustment(int index) {
    final ingredient = _detectedItems[index];
    // Safely handle amount regardless of actual runtime type
    int currentQuantity;
    if (ingredient.amount is int) {
      currentQuantity = amountAsInt(ingredient.amount);
    } else if (ingredient.amount is double) {
      currentQuantity = (ingredient.amount as double).toInt();
    } else {
      currentQuantity = int.tryParse(ingredient.amount.toString()) ?? 1;
    }
    IngredientCategory selectedCategory = ingredient.category;
    String currentName = ingredient.name;
    String currentUnit = ingredient.baseUnit;
    final nameController = TextEditingController(text: currentName);

    // Simplified unit options (no plurals, smart defaults)
    final unitOptions = [
      'ea',
      'lb',
      'oz',
      'fl oz',
      'pk',
      'can',
      'jar',
      'bag',
      'box',
      'bunch',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Editable Name Field
                TextField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Ingredient Name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: kBoneCreame.withOpacity(0.5),
                  ),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: kDeepForestGreen,
                  ),
                  onChanged: (value) {
                    currentName = value;
                  },
                ),
                const SizedBox(height: 20),
                // Quantity Controls Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Minus Button
                    GestureDetector(
                      onTap: currentQuantity > 0
                          ? () {
                              setModalState(() {
                                currentQuantity--;
                              });
                            }
                          : null,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: currentQuantity > 0
                              ? kSageGreen.withOpacity(0.2)
                              : Colors.grey.shade100,
                        ),
                        child: Center(
                          child: Icon(
                            Icons.remove,
                            color: currentQuantity > 0
                                ? kDeepForestGreen
                                : Colors.grey.shade400,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Quantity Display
                    Column(
                      children: [
                        Text(
                          currentQuantity.toString(),
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: kDeepForestGreen,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 24),
                    // Plus Button
                    GestureDetector(
                      onTap: () {
                        setModalState(() {
                          currentQuantity++;
                        });
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kSageGreen.withOpacity(0.2),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.add,
                            color: kDeepForestGreen,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Unit Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButton<String>(
                    value: unitOptions.contains(currentUnit)
                        ? currentUnit
                        : unitOptions.first,
                    isExpanded: true,
                    underline: const SizedBox(),
                    hint: const Text('Select Unit'),
                    items: unitOptions.map((unit) {
                      return DropdownMenuItem(value: unit, child: Text(unit));
                    }).toList(),
                    onChanged: (newUnit) {
                      if (newUnit != null) {
                        setModalState(() {
                          currentUnit = newUnit;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // Category Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButton<IngredientCategory>(
                    value: selectedCategory,
                    isExpanded: true,
                    underline: const SizedBox(),
                    hint: const Text('Move to Category'),
                    items: IngredientCategory.values.map((category) {
                      return DropdownMenuItem(
                        value: category,
                        child: Text(category.displayName),
                      );
                    }).toList(),
                    onChanged: (newCategory) {
                      if (newCategory != null) {
                        setModalState(() {
                          selectedCategory = newCategory;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(height: 32),
                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: kDeepForestGreen),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: kDeepForestGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _detectedItems[index] = ingredient.copyWith(
                              name: currentName.trim().isNotEmpty
                                  ? currentName.trim()
                                  : ingredient.name,
                              amount: currentQuantity,
                              baseUnit: currentUnit,
                              category: selectedCategory,
                            );
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kSageGreen,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Save',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddManualIngredient() {
    final nameController = TextEditingController();
    IngredientCategory selectedCategory = IngredientCategory.produce;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Manual Ingredient',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: kDeepForestGreen,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Ingredient Name',
                  hintText: 'e.g., Garlic, Milk',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Category pill boxes
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Category',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: IngredientCategory.values.map((category) {
                      final isSelected = selectedCategory == category;
                      return GestureDetector(
                        onTap: () {
                          setModalState(() {
                            selectedCategory = category;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected ? kDeepForestGreen : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? kDeepForestGreen
                                  : Colors.grey.shade300,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Text(
                            category.displayName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: kDeepForestGreen),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: kDeepForestGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (nameController.text.trim().isNotEmpty) {
                          setState(() {
                            _detectedItems.add(
                              Ingredient(
                                id: DateTime.now().millisecondsSinceEpoch
                                    .toString(),
                                name: nameController.text.trim(),
                                category: selectedCategory,
                                unitType: UnitType.count,
                                amount: 1,
                                baseUnit: 'ea',
                              ),
                            );
                          });
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kSageGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Add',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Ingredient>>(
      future: _detectionFuture,
      builder: (context, snapshot) {
        // ===== LOADING STATE =====
        if (_isLoading) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Processing Image'),
              backgroundColor: kBoneCreame,
              foregroundColor: kDeepForestGreen,
            ),
            body: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Detecting ingredients...'),
                ],
              ),
            ),
          );
        }

        // ===== ERROR STATE =====
        if (_errorMessage != null) {
          final isRateLimitError = _errorMessage!.contains('rate limit');

          return Scaffold(
            appBar: AppBar(
              title: Text(
                isRateLimitError ? 'Rate Limit Exceeded' : 'Detection Error',
              ),
              backgroundColor: kBoneCreame,
              foregroundColor: kDeepForestGreen,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isRateLimitError ? Icons.schedule : Icons.error_outline,
                      size: 64,
                      color: isRateLimitError ? kMutedGold : kSoftTerracotta,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      isRateLimitError
                          ? 'Too Many Requests'
                          : 'Detection Error',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(color: kDeepForestGreen),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: kDeepForestGreen),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text(
                              'Go Back',
                              style: TextStyle(
                                color: kDeepForestGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _errorMessage = null;
                                _isLoading = true;
                                _detectionFuture =
                                    _detectAndClassifyWithGemini();
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kDeepForestGreen,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text(
                              'Retry',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isRateLimitError) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: kMutedGold.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '💡 Tip: Wait a few seconds before retrying. API quota resets periodically.',
                          style: TextStyle(
                            fontSize: 12,
                            color: kMutedGold,
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        final grouped = _groupByCategory(_detectedItems);
        final categoryOrder = [
          IngredientCategory.produce,
          IngredientCategory.proteins,
          IngredientCategory.dairyRefrigerated,
          IngredientCategory.grainsLegumes,
          IngredientCategory.cannedGoods,
          IngredientCategory.frozen,
          IngredientCategory.condimentsSauces,
          IngredientCategory.spicesSeasonings,
          IngredientCategory.baking,
          IngredientCategory.snacksExtras,
        ];

        return Scaffold(
          appBar: AppBar(
            title: const Text('Confirm Items'),
            backgroundColor: kBoneCreame,
            foregroundColor: kDeepForestGreen,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.info_outline, size: 20),
                onPressed: () {
                  // Show help dialog instead of snackbar
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('How to Use'),
                      content: const Text(
                        'Tap chips to adjust quantity or category. Use + to add items manually.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Got it'),
                        ),
                      ],
                    ),
                  );
                },
                tooltip: 'Help',
              ),
            ],
          ),
          body: _detectedItems.isEmpty
              // ===== EMPTY STATE =====
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      const Text('No items detected in the image'),
                      const SizedBox(height: 8),
                      Text(
                        'Try a different image or add items manually',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              // ===== FIXED IMAGE + SCROLLABLE INGREDIENTS LAYOUT =====
              : Column(
                  children: [
                    // ========== FIXED IMAGE AT TOP (does not scroll) ==========
                    Stack(
                      children: [
                        Container(
                          height: MediaQuery.of(context).size.height * 0.35,
                          width: double.infinity,
                          color: kBoneCreame,
                          child: InteractiveViewer(
                            minScale: 1.0,
                            maxScale: 4.0,
                            child: Image.file(
                              widget.imageFile,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    color: kBoneCreame,
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.image_not_supported,
                                            size: 48,
                                            color: Colors.grey.shade400,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Image cannot be displayed',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                            ),
                          ),
                        ),
                        // FAB positioned at bottom-right of image
                        Positioned(
                          bottom: 12,
                          right: 16,
                          child: FloatingActionButton(
                            onPressed: _showAddManualIngredient,
                            backgroundColor: kDeepForestGreen,
                            shape: const CircleBorder(),
                            child: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // ========== SCROLLABLE INGREDIENT LIST ==========
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        itemCount: categoryOrder.length,
                        itemBuilder: (context, index) {
                          final category = categoryOrder[index];

                          if (!grouped.containsKey(category) ||
                              grouped[category]!.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          final items = grouped[category]!;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Category Header with count badge
                              Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: kMutedGold,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      category.displayName,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: kDeepForestGreen,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kMutedGold.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      items.length.toString(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: kDeepForestGreen,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              // Ingredient chips
                              ExcludeSemantics(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: items.asMap().entries.map<Widget>((
                                    entry,
                                  ) {
                                    final globalIndex = _detectedItems.indexOf(
                                      entry.value,
                                    );
                                    final ing = entry.value;

                                    return Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        GestureDetector(
                                          onTap: () => _showQuantityAdjustment(
                                            globalIndex,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.only(
                                              left: 12,
                                              right: 8,
                                              top: 8,
                                              bottom: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: Colors.grey.shade300,
                                                width: 1.0,
                                              ),
                                            ),
                                            child: Text(
                                              ing.name,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: kCharcoal,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Floating X delete button
                                        Positioned(
                                          top: -6,
                                          right: -6,
                                          child: GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                _detectedItems.removeAt(
                                                  globalIndex,
                                                );
                                              });
                                            },
                                            child: Container(
                                              width: 20,
                                              height: 20,
                                              decoration: BoxDecoration(
                                                color: Colors.grey,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.close,
                                                size: 12,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
          bottomNavigationBar: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _detectedItems.isNotEmpty
                    ? () {
                        widget.onAddIngredients(_detectedItems);
                        Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kDeepForestGreen,
                  disabledBackgroundColor: Colors.grey.shade300,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: const Text(
                  'Confirm & Save',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
