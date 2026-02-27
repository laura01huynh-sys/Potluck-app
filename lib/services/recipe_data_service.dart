import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/gemini_config.dart';

/// Consolidated recipe data service powered by Gemini.
///
/// Combines ingredient measurements AND cooking instructions into a SINGLE
/// API call to minimize daily quota usage (100 RPD limit).
///
/// Strategy:
/// 1. Check in-memory cache → instant.
/// 2. Check SharedPreferences disk cache → ~5ms.
/// 3. ONE Gemini API call → returns both measurements and instructions.
/// 4. Cache permanently so this recipe never costs another API call.
class RecipeDataService {
  // In-memory caches
  static final Map<String, Map<String, String>> _measurementsCache = {};
  static final Map<String, List<String>> _instructionsCache = {};

  // Rate limiting
  static DateTime? _lastGeminiCallTime;
  static const _minCallGapMs = 4000; // 4 seconds between calls (15 RPM limit)

  static Future<void> _waitForRateLimit() async {
    if (_lastGeminiCallTime != null) {
      final elapsed =
          DateTime.now().difference(_lastGeminiCallTime!).inMilliseconds;
      if (elapsed < _minCallGapMs) {
        await Future.delayed(Duration(milliseconds: _minCallGapMs - elapsed));
      }
    }
    _lastGeminiCallTime = DateTime.now();
  }

  /// Main entry point. Returns both measurements and instructions in one call.
  ///
  /// [ingredients] - List of ingredient names from Edamam (used for context)
  /// [existingMeasurements] - Any measurements already provided by Edamam
  static Future<RecipeData> getRecipeData({
    required String recipeId,
    required String title,
    required List<String> ingredients,
    Map<String, String> existingMeasurements = const {},
    String? sourceUrl,
  }) async {
    // 1 ── Memory cache (instant)
    if (_measurementsCache.containsKey(recipeId) &&
        _instructionsCache.containsKey(recipeId)) {
      return RecipeData(
        measurements: _measurementsCache[recipeId]!,
        instructions: _instructionsCache[recipeId]!,
      );
    }

    // 2 ── Disk cache (very fast)
    final cachedMeasurements = await _loadMeasurementsFromCache(recipeId);
    final cachedInstructions = await _loadInstructionsFromCache(recipeId);

    if (cachedMeasurements != null &&
        cachedMeasurements.isNotEmpty &&
        cachedInstructions != null &&
        cachedInstructions.isNotEmpty) {
      _measurementsCache[recipeId] = cachedMeasurements;
      _instructionsCache[recipeId] = cachedInstructions;
      return RecipeData(
        measurements: cachedMeasurements,
        instructions: cachedInstructions,
      );
    }

    // 3 ── Single Gemini call for BOTH measurements and instructions
    final result = await _generateRecipeData(
      title: title,
      ingredients: ingredients,
      existingMeasurements: existingMeasurements,
      sourceUrl: sourceUrl,
    );

    // 4 ── Cache permanently
    if (result.measurements.isNotEmpty) {
      _measurementsCache[recipeId] = result.measurements;
      await _saveMeasurementsToCache(recipeId, result.measurements);
    }
    if (result.instructions.isNotEmpty) {
      _instructionsCache[recipeId] = result.instructions;
      await _saveInstructionsToCache(recipeId, result.instructions);
    }

    return result;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Consolidated Gemini generation — ONE call for both
  // ─────────────────────────────────────────────────────────────────────────

  static Future<RecipeData> _generateRecipeData({
    required String title,
    required List<String> ingredients,
    required Map<String, String> existingMeasurements,
    String? sourceUrl,
  }) async {
    try {
      await _waitForRateLimit();

      // Build ingredient context
      final ingredientList = ingredients.join(', ');
      final sourceContext =
          sourceUrl != null && sourceUrl.isNotEmpty ? '\nSource: $sourceUrl' : '';

      // Consolidated prompt for BOTH measurements and instructions
      final prompt = '''You are an expert chef. For the recipe "$title", provide BOTH ingredient measurements AND cooking instructions.$sourceContext

Known ingredients: $ingredientList

Return a JSON object with exactly this structure:
{
  "measurements": {
    "ingredient name": "quantity unit",
    ...
  },
  "instructions": [
    "Step 1 text",
    "Step 2 text",
    ...
  ]
}

MEASUREMENT RULES:
1. For whole produce (lemons, onions, eggs, apples, bananas, tomatoes, potatoes, carrots, etc.): use just the number, NO unit. Example: "2" not "2 each"
2. For garlic: always use "clove" or "cloves". Example: "3 cloves"
3. For liquids (water, milk, oil, broth, juice, wine, etc.): use standard US measurements like "cup", "cups", "tbsp", "tsp". Example: "1 cup" or "2 tbsp". Do NOT use mL or L.
4. For dry ingredients (flour, sugar, rice, etc.): use "cup", "tbsp", "tsp". Example: "2 cups" or "1 tbsp"
5. For herbs: use "tbsp" for chopped, "sprig" for whole. Example: "2 tbsp" or "3 sprigs"
6. For spices: use "tsp" or "pinch". Example: "1 tsp" or "1 pinch"
7. For butter/cheese: use "tbsp", "cup", or "oz". Example: "2 tbsp" or "4 oz"
8. Use fractions where appropriate: 1/2, 1/4, 3/4, etc.

INSTRUCTION RULES:
1. Be CONCISE - no filler words
2. Include temperatures (°F/°C) and times where needed
3. Do NOT include measurements in steps (they're shown separately)
4. Each step should be ONE clear action, max 1-2 sentences
5. Include visual cues ("until golden", "until soft")
6. 5-8 steps total
7. Skip obvious prep like "gather ingredients"

Return ONLY the JSON object. No explanations.''';

      final response = await http
          .post(
            Uri.parse(GeminiConfig.recipeEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
              'generationConfig': {
                'temperature': 0.2,
                'topP': 0.95,
                'maxOutputTokens': 4096,
                'responseMimeType': 'application/json',
              },
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 429) {
        // Rate limited - return existing measurements with empty instructions
        return RecipeData(
          measurements: existingMeasurements,
          instructions: [],
        );
      }
      if (response.statusCode != 200) {
        return RecipeData(
          measurements: existingMeasurements,
          instructions: [],
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final text =
          data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ??
              '';

      return _parseResponse(text, existingMeasurements);
    } catch (e) {
      // On any error, return existing measurements with empty instructions
      return RecipeData(
        measurements: existingMeasurements,
        instructions: [],
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Response parser with unit normalization
  // ─────────────────────────────────────────────────────────────────────────

  static RecipeData _parseResponse(
    String responseText,
    Map<String, String> fallbackMeasurements,
  ) {
    var cleaned = responseText.trim();

    // Strip markdown code fences if present
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    cleaned = cleaned.trim();

    try {
      final decoded = jsonDecode(cleaned) as Map<String, dynamic>;

      // Parse measurements
      final rawMeasurements = decoded['measurements'] as Map<String, dynamic>?;
      final measurements = <String, String>{};
      if (rawMeasurements != null) {
        for (final entry in rawMeasurements.entries) {
          final ingredient = entry.key.toString().toLowerCase().trim();
          final measurement = _normalizeMeasurement(
            ingredient,
            entry.value.toString().trim(),
          );
          measurements[ingredient] = measurement;
        }
      }

      // Parse instructions
      final rawInstructions = decoded['instructions'] as List<dynamic>?;
      final instructions = <String>[];
      if (rawInstructions != null) {
        for (final step in rawInstructions) {
          final stepText = _stripMeasurementsFromStep(step.toString().trim());
          if (stepText.isNotEmpty) {
            instructions.add(stepText);
          }
        }
      }

      return RecipeData(
        measurements: measurements.isNotEmpty ? measurements : fallbackMeasurements,
        instructions: instructions,
      );
    } catch (e) {
      return RecipeData(
        measurements: fallbackMeasurements,
        instructions: [],
      );
    }
  }

  /// Normalize measurement based on ingredient type
  static String _normalizeMeasurement(String ingredient, String measurement) {
    final lower = ingredient.toLowerCase();
    final measureLower = measurement.toLowerCase();

    // Whole produce - strip units like "each", "ea", "whole", "piece"
    const wholeProduce = {
      'lemon', 'lemons', 'lime', 'limes', 'orange', 'oranges',
      'apple', 'apples', 'banana', 'bananas', 'avocado', 'avocados',
      'tomato', 'tomatoes', 'potato', 'potatoes', 'onion', 'onions',
      'carrot', 'carrots', 'cucumber', 'cucumbers', 'pepper', 'peppers',
      'egg', 'eggs', 'zucchini', 'eggplant', 'squash',
      'mango', 'mangoes', 'peach', 'peaches', 'pear', 'pears',
      'plum', 'plums', 'kiwi', 'kiwis', 'grapefruit', 'grapefruits',
    };

    for (final produce in wholeProduce) {
      if (lower.contains(produce)) {
        // Extract just the number
        final numMatch = RegExp(r'^([\d./]+(?:\s+[\d./]+)?)').firstMatch(measurement);
        if (numMatch != null) {
          return numMatch.group(1)!.trim();
        }
        return measurement.replaceAll(RegExp(r'\s*(each|ea|whole|piece|pieces|pc|pcs)\s*', caseSensitive: false), '').trim();
      }
    }

    // Garlic - ensure "clove" unit
    if (lower.contains('garlic')) {
      final numMatch = RegExp(r'^([\d./]+(?:\s+[\d./]+)?)').firstMatch(measurement);
      if (numMatch != null) {
        final num = numMatch.group(1)!.trim();
        // Check if already has clove
        if (measureLower.contains('clove')) {
          return measurement;
        }
        // Check if it's a head
        if (measureLower.contains('head')) {
          return measurement;
        }
        // Default to cloves
        final numVal = double.tryParse(num.replaceAll('/', '.')) ?? 1;
        return numVal == 1 ? '1 clove' : '$num cloves';
      }
      return measurement;
    }

    // Default: return as-is (keep original US measurements)
    return measurement;
  }

  /// Remove measurement patterns from instruction steps
  static String _stripMeasurementsFromStep(String step) {
    return step
        .replaceAllMapped(
          RegExp(
            r'\b(\d+(?:[./]\d+)?)\s*(cups?|tbsp|tablespoons?|tsp|teaspoons?|oz|ounces?|lbs?|pounds?|grams?|g|kg|ml|liters?|l|pinch(?:es)?|dash(?:es)?|cloves?|heads?|stalks?|bunch(?:es)?|cans?|jars?|bottles?|packages?|pieces?)\s+(?:of\s+)?',
            caseSensitive: false,
          ),
          (m) => 'the ',
        )
        .replaceAllMapped(
          RegExp(
            r'\b(\d+(?:\.\d+)?)\s*(g|kg|ml|l|oz|lb)\b',
            caseSensitive: false,
          ),
          (m) => '',
        )
        .replaceAll(RegExp(r'\bthe\s+the\b'), 'the')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cache management
  // ─────────────────────────────────────────────────────────────────────────

  static const String _measurementsCachePrefix = 'recipe_measurements_v3_';
  static const String _instructionsCachePrefix = 'recipe_instructions_v3_';

  static Future<Map<String, String>?> _loadMeasurementsFromCache(
    String recipeId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('$_measurementsCachePrefix$recipeId');
      if (json == null) return null;
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (e) {
      return null;
    }
  }

  static Future<List<String>?> _loadInstructionsFromCache(
    String recipeId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('$_instructionsCachePrefix$recipeId');
      if (json == null) return null;
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.map((e) => e.toString()).toList();
    } catch (e) {
      return null;
    }
  }

  static Future<void> _saveMeasurementsToCache(
    String recipeId,
    Map<String, String> measurements,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_measurementsCachePrefix$recipeId',
        jsonEncode(measurements),
      );
    } catch (e) {
      // Ignore cache errors
    }
  }

  static Future<void> _saveInstructionsToCache(
    String recipeId,
    List<String> instructions,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_instructionsCachePrefix$recipeId',
        jsonEncode(instructions),
      );
    } catch (e) {
      // Ignore cache errors
    }
  }

  /// Clear all caches for a specific recipe
  static Future<void> clearCache(String recipeId) async {
    _measurementsCache.remove(recipeId);
    _instructionsCache.remove(recipeId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_measurementsCachePrefix$recipeId');
    await prefs.remove('$_instructionsCachePrefix$recipeId');
  }

  /// Clear all recipe data caches
  static Future<void> clearAllCaches() async {
    _measurementsCache.clear();
    _instructionsCache.clear();
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where(
      (k) =>
          k.startsWith(_measurementsCachePrefix) ||
          k.startsWith(_instructionsCachePrefix),
    );
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}

/// Data class for recipe measurements and instructions
class RecipeData {
  final Map<String, String> measurements;
  final List<String> instructions;

  const RecipeData({
    required this.measurements,
    required this.instructions,
  });
}

/// Helper to deduplicate ingredients by name (case-insensitive)
List<String> deduplicateIngredients(List<String> ingredients) {
  final seen = <String>{};
  final result = <String>[];
  for (final ingredient in ingredients) {
    final normalized = ingredient.toLowerCase().trim();
    if (!seen.contains(normalized)) {
      seen.add(normalized);
      result.add(ingredient);
    }
  }
  return result;
}
