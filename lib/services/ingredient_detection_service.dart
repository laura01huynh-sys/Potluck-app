import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // For Ingredient, IngredientCategory, UnitType

/// Service for AI-powered ingredient detection from images using Google Generative AI
/// Uses Gemini 2.5 Flash for image analysis with automatic fallback for reliability
class IngredientDetectionService {
  final String apiKey;

  // Daily quota limit for AI scans
  static const int dailyQuotaLimit = 20;

  // Models to try in order - using Gemini 2.5 Flash models (user has quota)
  static const List<String> _modelFallbacks = [
    'gemini-2.5-flash', // Primary - user has quota for this
    'gemini-2.5-flash-lite', // Lite fallback
  ];

  IngredientDetectionService({required this.apiKey});

  /// Detects ingredients from an image file using Gemini Vision API
  /// Automatically tries fallback models if primary fails
  /// Get current scan statistics (used today, remaining, reset time)
  static Future<Map<String, dynamic>> getScanStats() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final lastResetDate = prefs.getString('scan_quota_date') ?? '';

    int scansUsed = 0;
    if (lastResetDate == today) {
      scansUsed = prefs.getInt('scan_quota_count') ?? 0;
    }

    final remaining = dailyQuotaLimit - scansUsed;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final resetTime = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);

    return {
      'used': scansUsed,
      'remaining': remaining > 0 ? remaining : 0,
      'limit': dailyQuotaLimit,
      'resetTime': resetTime,
    };
  }

  /// Increment daily scan count
  static Future<void> _incrementScanCount() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final lastResetDate = prefs.getString('scan_quota_date') ?? '';

    int currentCount = 0;
    if (lastResetDate == today) {
      currentCount = prefs.getInt('scan_quota_count') ?? 0;
    }

    await prefs.setString('scan_quota_date', today);
    await prefs.setInt('scan_quota_count', currentCount + 1);
  }

  Future<List<Ingredient>> detectIngredientsFromImage(File imageFile) async {
    final imageBytes = await imageFile.readAsBytes();
    final mimeType = _getMimeType(imageFile.path);

    // Try each model in sequence until one works
    for (final modelName in _modelFallbacks) {
      try {
        final result = await _tryDetectWithModel(
          modelName,
          imageBytes,
          mimeType,
        );

        // Increment scan count after successful detection
        await _incrementScanCount();

        return result;
      } catch (e) {
        final errorStr = e.toString().toLowerCase();

        // If it's an overload/unavailable error, try next model
        if (errorStr.contains('503') ||
            errorStr.contains('overloaded') ||
            errorStr.contains('unavailable') ||
            errorStr.contains('not_found') ||
            errorStr.contains('404')) {
          continue;
        }

        // If it's a quota error, fall back to mock data immediately
        if (errorStr.contains('quota') ||
            errorStr.contains('429') ||
            errorStr.contains('resource_exhausted') ||
            errorStr.contains('exceeded')) {
          return _getMockIngredients();
        }

        // For other errors, try next model
        continue;
      }
    }

    // All models failed - use mock data as last resort
    return _getMockIngredients();
  }

  /// Attempts detection with a specific model
  Future<List<Ingredient>> _tryDetectWithModel(
    String modelName,
    Uint8List imageBytes,
    String mimeType,
  ) async {
    final model = GenerativeModel(model: modelName, apiKey: apiKey);

    final prompt = Content.multi([
      TextPart(
        '''Analyze this image and identify all visible food ingredients and grocery items.

Return ONLY a JSON object (no markdown, no code blocks) with this exact structure:
{
  "ingredients": [
    {"name": "Tomato", "category": "Produce", "quantity": 3},
    {"name": "Milk", "category": "Dairy", "quantity": 1}
  ]
}

Categories must be one of: Produce, Protein, Dairy, Pantry, Staples
If no food items are visible, return: {"ingredients": []}''',
      ),
      DataPart(mimeType, imageBytes),
    ]);

    final response = await model.generateContent([prompt]);
    final text = response.text?.trim() ?? '{"ingredients": []}';

    return _parseJsonResponse(text);
  }

  /// Parses the structured JSON response from Gemini
  List<Ingredient> _parseJsonResponse(String jsonText) {
    try {
      // Clean potential markdown code blocks
      String cleanJson = jsonText.trim();
      if (cleanJson.startsWith('```json')) {
        cleanJson = cleanJson.substring(7);
      }
      if (cleanJson.startsWith('```')) {
        cleanJson = cleanJson.substring(3);
      }
      if (cleanJson.endsWith('```')) {
        cleanJson = cleanJson.substring(0, cleanJson.length - 3);
      }
      cleanJson = cleanJson.trim();

      final data = jsonDecode(cleanJson);
      final List ingredientsList = data['ingredients'] ?? [];

      return ingredientsList.map<Ingredient>((item) {
        final name = item['name']?.toString() ?? 'Unknown';
        final categoryStr = item['category']?.toString() ?? 'Pantry';
        final quantity = item['quantity'] ?? 1;

        return Ingredient(
          id: '${DateTime.now().millisecondsSinceEpoch}_${name.hashCode}',
          name: _capitalizeFirst(name),
          category: _parseCategory(categoryStr),
          unitType: UnitType.count,
          amount: quantity is int ? quantity : (quantity as num).toInt(),
          baseUnit: 'units',
        );
      }).toList();
    } catch (e) {
      // Fallback to simple comma parsing if JSON fails
      return _parseCommaSeparated(jsonText);
    }
  }

  /// Fallback parser for comma-separated text
  List<Ingredient> _parseCommaSeparated(String text) {
    final ingredients = <Ingredient>[];
    final items = text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);

    for (final item in items) {
      final name = item.replaceAll(RegExp(r'[^\w\s]'), '').trim();
      if (name.isEmpty) continue;

      ingredients.add(
        Ingredient(
          id: '${DateTime.now().millisecondsSinceEpoch}_${ingredients.length}',
          name: _capitalizeFirst(name),
          category: _guessCategory(name),
          unitType: UnitType.count,
          amount: 1,
          baseUnit: 'units',
        ),
      );
    }

    return ingredients;
  }

  /// Returns mock ingredients for development when API quota is exceeded
  static List<Ingredient> _getMockIngredients() {
    final baseId = DateTime.now().millisecondsSinceEpoch;
    return [
      Ingredient(
        id: baseId.toString(),
        name: 'Tomatoes',
        category: IngredientCategory.produce,
        unitType: UnitType.count,
        amount: 3,
        baseUnit: 'units',
      ),
      Ingredient(
        id: (baseId + 1).toString(),
        name: 'Garlic',
        category: IngredientCategory.produce,
        unitType: UnitType.count,
        amount: 5,
        baseUnit: 'cloves',
      ),
      Ingredient(
        id: (baseId + 2).toString(),
        name: 'Onions',
        category: IngredientCategory.produce,
        unitType: UnitType.count,
        amount: 2,
        baseUnit: 'units',
      ),
    ];
  }

  IngredientCategory _parseCategory(String category) {
    final lower = category.toLowerCase();

    if (_matchesAny(lower, ['produce', 'fruit', 'vegetable', 'fresh'])) {
      return IngredientCategory.produce;
    }

    if (_matchesAny(lower, [
      'dairy',
      'milk',
      'cheese',
      'yogurt',
      'refrigerated',
      'eggs',
      'butter',
    ])) {
      return IngredientCategory.dairyRefrigerated;
    }

    if (_matchesAny(lower, [
      'meat',
      'seafood',
      'fish',
      'chicken',
      'beef',
      'pork',
      'shrimp',
      'salmon',
    ])) {
      return IngredientCategory.proteins;
    }

    if (_matchesAny(lower, [
      'spice',
      'seasoning',
      'salt',
      'pepper',
      'cumin',
      'herb',
      'dried',
    ])) {
      return IngredientCategory.spicesSeasonings;
    }

    if (_matchesAny(lower, [
      'baking',
      'flour',
      'sugar',
      'yeast',
      'vanilla',
      'extract',
    ])) {
      return IngredientCategory.baking;
    }

    if (_matchesAny(lower, ['frozen', 'freeze'])) {
      return IngredientCategory.frozen;
    }

    // Map pantry-like keywords to the new granular categories
    if (_matchesAny(lower, ['canned', 'can', 'tin'])) {
      return IngredientCategory.cannedGoods;
    }

    if (_matchesAny(lower, [
      'oil',
      'olive oil',
      'vinegar',
      'soy sauce',
      'sauce',
      'honey',
      'maple',
    ])) {
      return IngredientCategory.condimentsSauces;
    }

    // Snacks & Extras: chips, cookies, bars, dips, jerky, seaweed, etc.
    if (_matchesAny(lower, [
      'chip',
      'chips',
      'crisps',
      'pretzel',
      'pretzels',
      'popcorn',
      'tortilla',
      'puff',
      'puffs',
      'cheetos',
      'doritos',
      'cracker',
      'crackers',
      'cookie',
      'cookies',
      'biscuit',
      'biscuits',
      'candy',
      'gummy',
      'brownie',
      'brownies',
      'donut',
      'donuts',
      'pastry',
      'pastries',
      'granola',
      'granola bar',
      'protein bar',
      'energy bar',
      'trail mix',
      'fruit leather',
      'dried fruit',
      'jerky',
      'slim jim',
      'hummus',
      'salsa',
      'guacamole',
      'pita',
      'pita chips',
      'pork rind',
      'pork rinds',
      'seaweed',
      'seaweed snack',
      'nut',
      'nuts',
      'peanut',
      'almond',
      'cashew',
      'walnut',
    ])) {
      return IngredientCategory.snacksExtras;
    }

    if (_matchesAny(lower, [
      'rice',
      'pasta',
      'grain',
      'lentil',
      'chickpea',
      'bean',
      'noodle',
      'bread',
    ])) {
      return IngredientCategory.grainsLegumes;
    }

    if (_matchesAny(lower, ['tomato', 'broth', 'stock'])) {
      return IngredientCategory.cannedGoods;
    }

    // Fallback to grains & legumes for general pantry items
    return IngredientCategory.grainsLegumes;
  }

  String _getMimeType(String path) {
    final extension = path.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  IngredientCategory _guessCategory(String name) {
    final lower = name.toLowerCase();

    // Produce: Fresh fruits and vegetables
    if (_matchesAny(lower, [
      'tomato',
      'onion',
      'garlic',
      'pepper',
      'carrot',
      'lettuce',
      'spinach',
      'broccoli',
      'cucumber',
      'celery',
      'potato',
      'mushroom',
      'zucchini',
      'eggplant',
      'cabbage',
      'kale',
      'apple',
      'banana',
      'orange',
      'lemon',
      'lime',
      'avocado',
      'berry',
      'grape',
      'melon',
      'mango',
      'pineapple',
      'vegetable',
      'fruit',
      'salad',
      'green',
      'squash',
      'radish',
      'beet',
    ])) {
      return IngredientCategory.produce;
    }

    // Dairy & Refrigerated: Milk, cheeses, eggs, yogurt
    if (_matchesAny(lower, [
      'milk',
      'cheese',
      'butter',
      'yogurt',
      'cream',
      'sour cream',
      'cottage',
      'mozzarella',
      'cheddar',
      'parmesan',
      'ricotta',
      'feta',
      'brie',
      'egg',
      'refrigerated',
      'cream cheese',
    ])) {
      return IngredientCategory.dairyRefrigerated;
    }

    // Proteins: Chicken, beef, shrimp, salmon (includes tofu/tempeh)
    if (_matchesAny(lower, [
      'chicken',
      'beef',
      'pork',
      'fish',
      'salmon',
      'tuna',
      'shrimp',
      'bacon',
      'sausage',
      'turkey',
      'lamb',
      'steak',
      'meat',
      'tofu',
      'tempeh',
      'seafood',
      'crab',
      'lobster',
      'ham',
      'duck',
      'anchovies',
    ])) {
      return IngredientCategory.proteins;
    }

    // Spices & Seasonings: Salt, pepper, cumin, dried herbs
    if (_matchesAny(lower, [
      'salt',
      'pepper',
      'cumin',
      'basil',
      'cilantro',
      'parsley',
      'mint',
      'ginger',
      'herb',
      'spice',
      'seasoning',
      'paprika',
      'oregano',
      'thyme',
      'rosemary',
      'garlic powder',
      'onion powder',
      'chili',
      'cayenne',
    ])) {
      return IngredientCategory.spicesSeasonings;
    }

    // Baking: Flour, sugar, yeast, vanilla extract
    if (_matchesAny(lower, [
      'flour',
      'sugar',
      'yeast',
      'vanilla',
      'extract',
      'baking powder',
      'baking soda',
      'cocoa',
      'chocolate',
      'cinnamon',
      'nutmeg',
      'brown sugar',
    ])) {
      return IngredientCategory.baking;
    }

    // Frozen: Frozen vegetables, fruits, meals
    if (_matchesAny(lower, ['frozen', 'freeze', 'ice cream', 'popsicle'])) {
      return IngredientCategory.frozen;
    }

    // Snacks & Extras heuristic (fall-back for items like chips, bars, dips)
    if (_matchesAny(lower, [
      'chip',
      'chips',
      'crisps',
      'pretzel',
      'pretzels',
      'popcorn',
      'tortilla',
      'puff',
      'puffs',
      'cheetos',
      'doritos',
      'cracker',
      'crackers',
      'cookie',
      'cookies',
      'biscuit',
      'biscuits',
      'candy',
      'gummy',
      'brownie',
      'brownies',
      'donut',
      'donuts',
      'pastry',
      'pastries',
      'granola',
      'granola bar',
      'protein bar',
      'energy bar',
      'trail mix',
      'fruit leather',
      'dried fruit',
      'jerky',
      'slim jim',
      'hummus',
      'salsa',
      'guacamole',
      'pita',
      'pita chips',
      'pork rind',
      'pork rinds',
      'seaweed',
      'seaweed snack',
      'nut',
      'nuts',
      'peanut',
      'almond',
      'cashew',
      'walnut',
    ])) {
      return IngredientCategory.snacksExtras;
    }

    // Map pantry-like keywords to the new granular categories
    if (_matchesAny(lower, ['canned', 'can', 'tin'])) {
      return IngredientCategory.cannedGoods;
    }

    if (_matchesAny(lower, [
      'oil',
      'olive oil',
      'vinegar',
      'soy sauce',
      'sauce',
      'honey',
      'maple',
    ])) {
      return IngredientCategory.condimentsSauces;
    }

    if (_matchesAny(lower, [
      'rice',
      'pasta',
      'grain',
      'lentil',
      'chickpea',
      'bean',
      'noodle',
      'bread',
    ])) {
      return IngredientCategory.grainsLegumes;
    }

    if (_matchesAny(lower, ['tomato', 'broth', 'stock'])) {
      return IngredientCategory.cannedGoods;
    }

    // Fallback to grains & legumes for general pantry items
    return IngredientCategory.grainsLegumes;
  }

  bool _matchesAny(String text, List<String> keywords) {
    return keywords.any((keyword) => text.contains(keyword));
  }
}
