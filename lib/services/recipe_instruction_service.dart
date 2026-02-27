import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/gemini_config.dart';

/// Fast recipe instruction generator powered by Gemini.
///
/// Strategy (optimized for speed):
/// 1. Check in-memory cache → instant.
/// 2. Check SharedPreferences disk cache → ~5ms.
/// 3. Single Gemini API call with title + ingredients → generates clear
///    cooking steps in ~2-4 seconds (no webpage fetching).
/// 4. Cache permanently so this recipe never costs another API call.
///
/// Why this is fast:
/// - ONE network call (Gemini) instead of two (webpage fetch + Gemini).
/// - No HTML fetching/parsing — eliminates the biggest bottleneck.
/// - Tight 15s timeout instead of 25s.
/// - Compact prompt → fewer tokens → faster response.
/// - Gemini 2.5 Flash is optimized for speed.
class RecipeInstructionService {
  // In-memory cache — repeated opens in the same session are instant
  static final Map<String, List<String>> _memoryCache = {};

  // Global throttle: track last Gemini call time across all services
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

  /// Main entry point. Returns a list of instruction step strings.
  ///
  /// [sourceUrl] is kept in the signature for backward compatibility but is
  /// no longer used for fetching. The source link is still shown in the UI
  /// for users who want to visit the original page.
  static Future<List<String>> getInstructions({
    required String recipeId,
    required String title,
    required List<String> ingredients,
    Map<String, String> measurements = const {},
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

    // 3 ── Single Gemini call — generate steps from title + ingredients
    final instructions = await _generateInstructions(
      title: title,
      ingredients: ingredients,
      measurements: measurements,
    );

    // 4 ── Cache permanently
    if (instructions.isNotEmpty) {
      _memoryCache[recipeId] = instructions;
      await _saveToCache(recipeId, instructions);
    }

    return instructions;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Gemini generation — single fast call
  // ─────────────────────────────────────────────────────────────────────────

  static Future<List<String>> _generateInstructions({
    required String title,
    required List<String> ingredients,
    required Map<String, String> measurements,
  }) async {
    try {
      // Throttle to avoid hitting Gemini rate limits
      await _waitForRateLimit();

      // Build ingredient list with measurements for context
      final ingredientList = ingredients
          .map((ing) {
            final measure = measurements[ing];
            return measure != null && measure.isNotEmpty ? '$measure $ing' : ing;
          })
          .join(', ');

      // Concise prompt for practical instructions without fluff
      final prompt =
          'You are an expert chef. Write concise step-by-step cooking instructions for "$title".\n\n'
          'Ingredients with quantities:\n$ingredientList\n\n'
          'Requirements:\n'
          '1. Be CONCISE - no filler words or unnecessary sentences\n'
          '2. Include cooking temperatures (°F/°C) and times where needed\n'
          '3. Reference the actual ingredients listed\n'
          '4. Do NOT include measurements in steps (shown separately)\n'
          '5. Include visual cues (e.g., "until golden", "until soft")\n'
          '6. Each step should be ONE clear action, max 1-2 sentences\n'
          '7. Skip obvious prep like "gather ingredients" or "read recipe"\n'
          '8. Focus on actual cooking actions only\n\n'
          'Return ONLY a JSON array of 5-8 short, actionable steps. No introductions or conclusions.';

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
                'temperature': 0.3,
                'topP': 0.95,
                'maxOutputTokens': 2048,
                'responseMimeType': 'application/json',
              },
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 429) {
        // Rate limited - return empty list so UI can show source link
        return [];
      }
      if (response.statusCode != 200) {
        // API error - return empty list so UI can show source link
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final text =
          data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ??
          '';

      return _parseJsonSteps(text);
    } catch (e) {
      // Any error (timeout, parsing, etc.) - return empty list
      // UI will show "View original" link instead
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // JSON parser + measurement stripper
  // ─────────────────────────────────────────────────────────────────────────

  static List<String> _parseJsonSteps(String responseText) {
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

    List<String> steps = [];
    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is List) {
        steps = decoded
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (e) {
      // Fallback: split numbered lines ("1. ...", "2. ..." etc.)
      steps = cleaned
          .split(RegExp(r'\n'))
          .map((l) => l.replaceFirst(RegExp(r'^\d+[\.\)]\s*'), '').trim())
          .where((l) => l.isNotEmpty && l.length > 10)
          .toList();
    }

    // Post-process: strip any remaining measurements from steps
    return steps.map(_stripMeasurements).toList();
  }

  /// Remove common measurement patterns from instruction text
  static String _stripMeasurements(String step) {
    // Pattern matches: "2 cups of", "1/2 tablespoon", "500g", "1.5 liters", etc.
    // We keep the ingredient name but remove the quantity
    return step
        // "Add 2 cups of flour" → "Add the flour"
        .replaceAllMapped(
          RegExp(
            r'\b(\d+(?:[./]\d+)?)\s*(cups?|tbsp|tablespoons?|tsp|teaspoons?|oz|ounces?|lbs?|pounds?|grams?|g|kg|ml|liters?|l|pinch(?:es)?|dash(?:es)?|cloves?|heads?|stalks?|bunch(?:es)?|cans?|jars?|bottles?|packages?|pieces?)\s+(?:of\s+)?',
            caseSensitive: false,
          ),
          (m) => 'the ',
        )
        // "500g chicken" → "the chicken"
        .replaceAllMapped(
          RegExp(
            r'\b(\d+(?:\.\d+)?)\s*(g|kg|ml|l|oz|lb)\b',
            caseSensitive: false,
          ),
          (m) => '',
        )
        // "1/2 cup" alone → remove
        .replaceAll(
          RegExp(
            r'\b\d+(?:[./]\d+)?\s*(cups?|tbsp|tablespoons?|tsp|teaspoons?)\b',
            caseSensitive: false,
          ),
          '',
        )
        // Clean up "the the" or extra spaces
        .replaceAll(RegExp(r'\bthe\s+the\b'), 'the')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cache (SharedPreferences — permanent per recipe ID)
  // ─────────────────────────────────────────────────────────────────────────

  static const String _cachePrefix = 'recipe_instructions_';

  static Future<List<String>?> _loadFromCache(String recipeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('$_cachePrefix$recipeId');
      if (json == null) return null;
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.map((e) => e.toString()).toList();
    } catch (e) {
      return null;
    }
  }

  static Future<void> _saveToCache(
    String recipeId,
    List<String> instructions,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_cachePrefix$recipeId', jsonEncode(instructions));
    } catch (e) {
      // ignore: empty catch blocks
    }
  }

  /// Clear the instruction cache for a specific recipe (useful for debugging)
  static Future<void> clearCache(String recipeId) async {
    _memoryCache.remove(recipeId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_cachePrefix$recipeId');
  }

  /// Clear all instruction caches
  static Future<void> clearAllCaches() async {
    _memoryCache.clear();
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_cachePrefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
