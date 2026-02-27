import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/gemini_config.dart';

/// Recipe ingredient fetcher powered by Gemini.
///
/// Strategy:
/// 1. Check in-memory cache → instant.
/// 2. Check SharedPreferences disk cache → ~5ms.
/// 3. Single Gemini API call with recipe title → fetches ingredients with proper measurements.
/// 4. Cache permanently so this recipe never costs another API call.
class RecipeIngredientService {
  // In-memory cache
  static final Map<String, Map<String, String>> _memoryCache = {};

  // Shared throttle: reuse the same last-call tracker as RecipeInstructionService
  // to prevent both services from firing simultaneously
  static DateTime? _lastGeminiCallTime;
  static const _minCallGapMs = 4000; // 4 seconds between calls (15 RPM limit)

  static Future<void> _waitForRateLimit() async {
    if (_lastGeminiCallTime != null) {
      final elapsed = DateTime.now().difference(_lastGeminiCallTime!).inMilliseconds;
      if (elapsed < _minCallGapMs) {
        await Future.delayed(Duration(milliseconds: _minCallGapMs - elapsed));
      }
    }
    _lastGeminiCallTime = DateTime.now();
  }

  /// Main entry point. Returns a map of ingredient name -> measurement.
  static Future<Map<String, String>> getIngredients({
    required String recipeId,
    required String title,
    String? sourceUrl,
  }) async {
    // 1 ── Memory cache (instant)
    if (_memoryCache.containsKey(recipeId)) {
      return _memoryCache[recipeId]!;
    }

    // 2 ── Disk cache (very fast)
    final cached = await _loadFromCache(recipeId);
    if (cached != null && cached.isNotEmpty) {
      _memoryCache[recipeId] = cached;
      return cached;
    }

    // 3 ── Single Gemini call — generate ingredients with measurements
    final ingredients = await _generateIngredients(
      title: title,
      sourceUrl: sourceUrl,
    );

    // 4 ── Cache permanently
    if (ingredients.isNotEmpty) {
      _memoryCache[recipeId] = ingredients;
      await _saveToCache(recipeId, ingredients);
    }

    return ingredients;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Gemini generation
  // ─────────────────────────────────────────────────────────────────────────

  static Future<Map<String, String>> _generateIngredients({
    required String title,
    String? sourceUrl,
  }) async {
    try {
      // Throttle to avoid hitting Gemini rate limits
      await _waitForRateLimit();
    } catch (_) {}

    // Build prompt with source URL context if available
    final sourceContext = sourceUrl != null && sourceUrl.isNotEmpty
        ? '\nSource URL: $sourceUrl\n'
        : '';

    final prompt =
        'You are a recipe ingredient expert. Provide the complete ingredient list with accurate measurements for "$title".$sourceContext\n\n'
        'Requirements:\n'
        '1. Return ONLY a JSON object mapping ingredient names to measurements\n'
        '2. Use standard cooking measurements (cups, tbsp, tsp, oz, lb, g, kg, ml, L, etc.)\n'
        '3. Include fractions where appropriate (1/2, 1/4, 2 1/2, etc.)\n'
        '4. Use "each" or "ea" for countable items without specific measurements\n'
        '5. Be precise with quantities - do not guess or approximate\n'
        '6. Include all ingredients needed for the recipe\n'
        '7. Format: {"ingredient name": "measurement", ...}\n\n'
        'Example format:\n'
        '{\n'
        '  "all-purpose flour": "2 cups",\n'
        '  "butter": "1/2 cup",\n'
        '  "eggs": "2 ea",\n'
        '  "vanilla extract": "1 tsp",\n'
        '  "salt": "1/4 tsp"\n'
        '}\n\n'
        'Return ONLY the JSON object. No explanations or additional text.';

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
              'maxOutputTokens': 2048,
              'responseMimeType': 'application/json',
            },
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 429) {
      throw Exception('Rate limited — please try again in a moment.');
    }
    if (response.statusCode != 200) {
      throw Exception('Gemini API error ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final text =
        data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ??
        '';

    return _parseJsonIngredients(text);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // JSON parser
  // ─────────────────────────────────────────────────────────────────────────

  static Map<String, String> _parseJsonIngredients(String responseText) {
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
      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) {
        return decoded.map((key, value) => MapEntry(
              key.toString().toLowerCase().trim(),
              value.toString().trim(),
            ));
      }
    } catch (e) {
      // Return empty map on parse error
      return {};
    }

    return {};
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cache (SharedPreferences)
  // ─────────────────────────────────────────────────────────────────────────

  static const String _cachePrefix = 'recipe_ingredients_';

  static Future<Map<String, String>?> _loadFromCache(String recipeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('$_cachePrefix$recipeId');
      if (json == null) return null;
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(
            key.toString(),
            value.toString(),
          ));
    } catch (e) {
      return null;
    }
  }

  static Future<void> _saveToCache(
    String recipeId,
    Map<String, String> ingredients,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_cachePrefix$recipeId', jsonEncode(ingredients));
    } catch (e) {
      // Ignore cache errors
    }
  }

  /// Clear the ingredient cache for a specific recipe
  static Future<void> clearCache(String recipeId) async {
    _memoryCache.remove(recipeId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_cachePrefix$recipeId');
  }

  /// Clear all ingredient caches
  static Future<void> clearAllCaches() async {
    _memoryCache.clear();
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_cachePrefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
