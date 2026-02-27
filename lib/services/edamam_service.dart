import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../main.dart' show Ingredient;
import '../core/constants.dart';
import '../core/format.dart';

class EdamamRecipeService {
  static const _baseUrl = 'https://api.edamam.com/api/recipes/v2';
  static const _fields = 'field=uri&field=label&field=image&field=images&field=yield&field=ingredientLines&field=ingredients&field=calories&field=totalNutrients&field=totalTime&field=url&field=source';
  final _random = Random();

  /// Fetches recipes based on available pantry ingredients
  Future<List<Map<String, dynamic>>> fetchRecipesFromPantry(
    List<Ingredient> pantry, {
    int maxResults = 20,
    List<String>? diet,
    List<String>? health,
  }) async {
    final active = pantry.where((i) => FormatUtils.parseDouble(i.amount) > 0).toList();
    if (active.isEmpty) return [];

    final names = active.map((i) => i.name.toLowerCase().trim()).toList()..shuffle();
    final queries = [
      if (names.isNotEmpty) names.take(3).join(' '),
      if (names.length >= 2) names.skip(1).take(2).join(' '),
      if (names.isNotEmpty) names.first,
      if (names.isNotEmpty) '${names.first} recipes',
    ];

    try {
      final resultsById = <String, Map<String, dynamic>>{};
      final filterParams = [
        if (diet != null) ...diet.map((d) => 'diet=${Uri.encodeComponent(d)}'),
        if (health != null) ...health.map((h) => 'health=${Uri.encodeComponent(h)}'),
      ].join('&');

      for (final q in queries) {
        if (resultsById.length >= maxResults) break;

        final uri = Uri.parse('$_baseUrl?type=public&q=${Uri.encodeComponent(q)}&app_id=${ApiKeys.edamamAppId}&app_key=${ApiKeys.edamamAppKey}&random=true&$_fields${filterParams.isNotEmpty ? '&$filterParams' : ''}');
        final response = await http.get(uri).timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) continue;

        final hits = jsonDecode(response.body)['hits'] as List? ?? [];
        for (var hit in hits) {
          final recipe = _normalizeEdamamRecipe(hit['recipe'] ?? {});
          if (recipe != null) resultsById[recipe['id']] = recipe;
        }
      }

      return resultsById.values.take(maxResults).toList();
    } catch (e) {
      return [];
    }
  }

  /// Maps Edamam JSON to Internal App Format
  Map<String, dynamic>? _normalizeEdamamRecipe(Map<String, dynamic> json) {
    try {
      final id = json['uri']?.split('#recipe_').last ?? DateTime.now().millisecond.toString();
      final servings = FormatUtils.parseDouble(json['yield'] ?? 4);
      final nutrients = json['totalNutrients'] as Map? ?? {};
      
      double perServ(String key) => FormatUtils.parseDouble(nutrients[key]?['quantity']) / servings;

      final measurements = <String, String>{};
      final ingredientNames = <String>[];
      
      for (var ing in (json['ingredients'] as List? ?? [])) {
        final name = ing['food'] ?? '';
        if (name.isNotEmpty) {
          ingredientNames.add(name);
          measurements[name] = FormatUtils.cleanMeasurement(ing['text'] ?? '');
        }
      }

      return {
        'id': id,
        'title': json['label'] ?? 'Untitled',
        'imageUrl': json['images']?['REGULAR']?['url'] ?? json['image'] ?? '',
        'ingredients': ingredientNames,
        'ingredientMeasurements': measurements,
        'cookTime': (json['totalTime'] as num? ?? 0) > 0 ? json['totalTime'] : (15 + _random.nextInt(30)),
        'nutrition': {
          'calories': perServ('ENERC_KCAL').round(),
          'protein': perServ('PROCNT'),
          'fat': perServ('FAT'),
          'carbs': perServ('CHOCDF'),
        },
        'sourceUrl': json['url'] ?? '',
        'authorName': json['source'] ?? 'Edamam',
        'aspectRatio': [0.85, 0.9, 1.0][_random.nextInt(3)],
        'servings': servings.toInt(),
      };
    } catch (_) { return null; }
  }
}