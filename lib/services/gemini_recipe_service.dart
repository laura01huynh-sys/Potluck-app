import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants.dart';
import '../core/format.dart';

/// Recipe data service powered by Gemini.
/// Combines ingredient measurements AND cooking instructions into a SINGLE API call.
/// Cache priority: memory → Firestore → SharedPreferences → Gemini API.
class RecipeDataService {
  static final Map<String, Map<String, String>> _measurementsCache = {};
  static final Map<String, List<String>> _instructionsCache = {};
  static const String _cloudCollection = 'recipe_data';
  static const String _measurementsPrefix = 'recipe_measurements_v3_';
  static const String _instructionsPrefix = 'recipe_instructions_v3_';
  static DateTime? _lastGeminiCall;
  static const _minCallGapMs = 4000;

  static Future<RecipeData> getRecipeData({
    required String recipeId,
    required String title,
    required List<String> ingredients,
    Map<String, String> existingMeasurements = const {},
    String? sourceUrl,
  }) async {
    // 1. Memory cache
    if (_measurementsCache.containsKey(recipeId) && _instructionsCache.containsKey(recipeId)) {
      return RecipeData(measurements: _measurementsCache[recipeId]!, instructions: _instructionsCache[recipeId]!);
    }

    // 2. Firestore cache
    final cloud = await _loadFromCloud(recipeId);
    if (cloud != null && cloud.measurements.isNotEmpty && cloud.instructions.isNotEmpty) {
      _writeToMemory(recipeId, cloud);
      await _writeToDisk(recipeId, cloud);
      return cloud;
    }

    // 3. Disk cache
    final diskMeasurements = await _diskGet<Map<String, String>>(_measurementsPrefix + recipeId, isMap: true);
    final diskInstructions = await _diskGet<List<String>>(_instructionsPrefix + recipeId, isMap: false);
    if (diskMeasurements != null && diskInstructions != null && diskMeasurements.isNotEmpty && diskInstructions.isNotEmpty) {
      final data = RecipeData(measurements: diskMeasurements, instructions: diskInstructions);
      _writeToMemory(recipeId, data);
      _saveToCloud(recipeId, data); // fire-and-forget
      return data;
    }

    // 4. Gemini API
    final result = await _callGemini(title: title, ingredients: ingredients, existingMeasurements: existingMeasurements, sourceUrl: sourceUrl);
    _writeToMemory(recipeId, result);
    await _writeToDisk(recipeId, result);
    _saveToCloud(recipeId, result); // fire-and-forget
    return result;
  }

  static void _writeToMemory(String recipeId, RecipeData data) {
    if (data.measurements.isNotEmpty) _measurementsCache[recipeId] = data.measurements;
    if (data.instructions.isNotEmpty) _instructionsCache[recipeId] = data.instructions;
  }

  static Future<void> _writeToDisk(String recipeId, RecipeData data) async {
    final prefs = await SharedPreferences.getInstance();
    if (data.measurements.isNotEmpty) await prefs.setString(_measurementsPrefix + recipeId, jsonEncode(data.measurements));
    if (data.instructions.isNotEmpty) await prefs.setString(_instructionsPrefix + recipeId, jsonEncode(data.instructions));
  }

  // Returns Map<String,String> when isMap=true, List<String> otherwise
  static Future<T?> _diskGet<T>(String key, {required bool isMap}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(key);
      if (json == null) return null;
      final decoded = jsonDecode(json);
      if (isMap) {
        return (decoded as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString())) as T;
      } else {
        return (decoded as List).map((e) => e.toString()).toList() as T;
      }
    } catch (_) {
      return null;
    }
  }

  // ── Gemini ──────────────────────────────────────────────────────────────

  static Future<RecipeData> _callGemini({
    required String title,
    required List<String> ingredients,
    required Map<String, String> existingMeasurements,
    String? sourceUrl,
  }) async {
    try {
      // Rate limiting
      if (_lastGeminiCall != null) {
        final elapsed = DateTime.now().difference(_lastGeminiCall!).inMilliseconds;
        if (elapsed < _minCallGapMs) await Future.delayed(Duration(milliseconds: _minCallGapMs - elapsed));
      }
      _lastGeminiCall = DateTime.now();

      final sourceContext = (sourceUrl != null && sourceUrl.isNotEmpty) ? '\nSource: $sourceUrl' : '';
      final prompt = '''You are an expert chef. For "$title", return ONLY this JSON:$sourceContext
Known ingredients: ${ingredients.join(', ')}
{
  "measurements": { "ingredient name": "quantity unit" },
  "instructions": ["Step 1", "Step 2", ...]
}
MEASUREMENTS: whole produce = number only ("2"); garlic = cloves ("3 cloves"); liquids = US cups/tbsp/tsp; dry = cup/tbsp/tsp; spices = tsp/pinch; butter/cheese = tbsp/cup/oz. Use fractions.
INSTRUCTIONS: concise, include temps (°F/°C) and times, no measurements in steps, visual cues ("until golden"), 5–8 steps.''';

      final response = await http.post(
        Uri.parse(GeminiConfig.recipeEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [{'text': prompt}]}],
          'generationConfig': {'temperature': 0.2, 'topP': 0.95, 'maxOutputTokens': 4096, 'responseMimeType': 'application/json'},
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return RecipeData(measurements: existingMeasurements, instructions: []);

      final text = (jsonDecode(response.body) as Map)['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ?? '';
      return _parseResponse(text, existingMeasurements);
    } catch (_) {
      return RecipeData(measurements: existingMeasurements, instructions: []);
    }
  }

  static RecipeData _parseResponse(String raw, Map<String, String> fallback) {
    try {
      var cleaned = raw.trim().replaceAll(RegExp(r'^```json?|```$', multiLine: true), '').trim();
      final decoded = jsonDecode(cleaned) as Map<String, dynamic>;

      final measurements = <String, String>{};
      (decoded['measurements'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
        final key = k.toLowerCase().trim();
        measurements[key] = RecipeUtils.normalizeAndClean(key, v.toString().trim());
      });

      final instructions = (decoded['instructions'] as List? ?? [])
          .map((s) => _stripMeasurements(s.toString().trim()))
          .where((s) => s.isNotEmpty)
          .toList();

      return RecipeData(
        measurements: measurements.isNotEmpty ? measurements : fallback,
        instructions: instructions,
      );
    } catch (_) {
      return RecipeData(measurements: fallback, instructions: []);
    }
  }

  static String _stripMeasurements(String step) => step
      .replaceAllMapped(
        RegExp(r'\b(\d+(?:[./]\d+)?)\s*(cups?|tbsp|tablespoons?|tsp|teaspoons?|oz|ounces?|lbs?|pounds?|grams?|g|kg|ml|liters?|l|pinch(?:es)?|dash(?:es)?|cloves?|heads?|stalks?|bunch(?:es)?|cans?|jars?|bottles?|packages?|pieces?)\s+(?:of\s+)?', caseSensitive: false),
        (_) => 'the ',
      )
      .replaceAllMapped(RegExp(r'\b(\d+(?:\.\d+)?)\s*(g|kg|ml|l|oz|lb)\b', caseSensitive: false), (_) => '')
      .replaceAll(RegExp(r'\bthe\s+the\b'), 'the')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();

  // ── Firestore ────────────────────────────────────────────────────────────

  static Future<RecipeData?> _loadFromCloud(String recipeId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection(_cloudCollection).doc(recipeId).get();
      if (!doc.exists) return null;
      final data = doc.data()!;
      final measurements = (data['measurements'] as Map? ?? {}).map((k, v) => MapEntry(k.toString(), v.toString()));
      final instructions = (data['instructions'] as List? ?? []).map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      if (measurements.isEmpty && instructions.isEmpty) return null;
      return RecipeData(measurements: measurements, instructions: instructions);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveToCloud(String recipeId, RecipeData data) async {
    try {
      await FirebaseFirestore.instance.collection(_cloudCollection).doc(recipeId).set({
        'measurements': data.measurements,
        'instructions': data.instructions,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // ── Cache clearing ───────────────────────────────────────────────────────

  static Future<void> clearCache(String recipeId) async {
    _measurementsCache.remove(recipeId);
    _instructionsCache.remove(recipeId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_measurementsPrefix + recipeId);
    await prefs.remove(_instructionsPrefix + recipeId);
  }

  static Future<void> clearAllCaches() async {
    _measurementsCache.clear();
    _instructionsCache.clear();
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((k) => k.startsWith(_measurementsPrefix) || k.startsWith(_instructionsPrefix))) {
      await prefs.remove(key);
    }
  }
}

class RecipeData {
  final Map<String, String> measurements;
  final List<String> instructions;
  const RecipeData({required this.measurements, required this.instructions});
}