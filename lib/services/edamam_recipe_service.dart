import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show Ingredient, UnitType;

/// Edamam Recipe API Service
/// Fetches recipes based on pantry ingredients from Edamam's recipe database
///
/// API Documentation: https://developer.edamam.com/edamam-docs-recipe-api
class EdamamRecipeService {
  // Edamam API credentials
  static const String _appId = '46079ec0';
  static const String _appKey = '375c5f612c07d29724251b57ea39d101';

  // API endpoint
  static const String _baseUrl = 'https://api.edamam.com/api/recipes/v2';

  // Cache settings
  static const int _cacheMaxAgeMins = 60; // Cache for 1 hour

  /// Main method: Fetch recipes based on pantry ingredients
  Future<List<Map<String, dynamic>>> fetchRecipesFromPantry(
    List<Ingredient> pantryIngredients, {
    bool forceRefresh = false,
    int maxResults = 20,
    List<String>? dietLabels,
    List<String>? healthLabels,
  }) async {
    // Get active ingredients (amount > 0)
    final activeIngredients = pantryIngredients.where((ing) {
      if (ing.unitType == UnitType.volume) {
        return (ing.amount as double) > 0;
      }
      // Handle both int and double amounts safely
      if (ing.amount is int) {
        return (ing.amount as int) > 0;
      }
      return (ing.amount as num).toDouble() > 0;
    }).toList();

    if (activeIngredients.isEmpty) {
      return [];
    }

    // Build cache key from sorted ingredient names
    final cacheKey = _buildCacheKey(activeIngredients);

    // Try cache first (unless force refresh)
    if (!forceRefresh) {
      final cached = await _loadFromCache(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
    }

    // Build search query candidates from ingredients
    // Edamam works best with simple ingredient searches (1-3 ingredients)
    var ingredientNames = activeIngredients
        .map((ing) => ing.name.toLowerCase().trim())
        .where((name) => name.isNotEmpty)
        .toList();

    // Shuffle ingredients to get variety instead of always using the same ones
    ingredientNames.shuffle();

    final queryCandidates = <String>[];
    if (ingredientNames.isNotEmpty) {
      // Use different combinations for variety
      queryCandidates.add(ingredientNames.take(3).join(' '));
      if (ingredientNames.length >= 2) {
        queryCandidates.add(ingredientNames.skip(1).take(2).join(' '));
      }
      if (ingredientNames.length >= 3) {
        queryCandidates.add(ingredientNames.skip(2).take(2).join(' '));
      }
      queryCandidates.add(ingredientNames.first);
      if (ingredientNames.length > 1) {
        queryCandidates.add(ingredientNames[1]);
      }
    }
    queryCandidates.add('healthy recipes');

    // De-duplicate while preserving order
    final seenQueries = <String>{};
    final queries = queryCandidates.where((q) => seenQueries.add(q)).toList();

    try {
      // Build URL manually since Edamam expects multiple 'field' params
      final fields = [
        'uri',
        'label',
        'image',
        'images',
        'source',
        'url',
        'yield',
        'dietLabels',
        'healthLabels',
        'ingredientLines',
        'ingredients',
        'calories',
        'totalNutrients',
        'totalTime',
        'cuisineType',
        'mealType',
        'dishType',
      ];

      final fieldParams = fields.map((f) => 'field=$f').join('&');

      // Build diet and health label params
      String dietParams = '';
      if (dietLabels != null && dietLabels.isNotEmpty) {
        dietParams = dietLabels
            .map((d) => 'diet=${Uri.encodeComponent(d)}')
            .join('&');
      }
      String healthParams = '';
      if (healthLabels != null && healthLabels.isNotEmpty) {
        healthParams = healthLabels
            .map((h) => 'health=${Uri.encodeComponent(h)}')
            .join('&');
      }
      final filterParams = [
        dietParams,
        healthParams,
      ].where((p) => p.isNotEmpty).join('&');
      final filterSuffix = filterParams.isNotEmpty ? '&$filterParams' : '';

      final recipesById = <String, Map<String, dynamic>>{};

      for (final query in queries) {
        final encodedQuery = Uri.encodeComponent(query);
        final uri = Uri.parse(
          '$_baseUrl?type=public&q=$encodedQuery&app_id=$_appId&app_key=$_appKey&random=true&$fieldParams$filterSuffix',
        );

        final response = await http
            .get(
              uri,
              headers: {
                'Accept': 'application/json',
                'Edamam-Account-User': _appId,
              },
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode != 200) {
          // Try to return stale cache on error
          final staleCache = await _loadFromCache(cacheKey, ignoreExpiry: true);
          if (staleCache != null && staleCache.isNotEmpty) {
            return staleCache;
          }

          throw Exception('Edamam API error: ${response.statusCode}');
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final hits = data['hits'] as List<dynamic>? ?? [];

        if (hits.isEmpty) {
          continue;
        }

        // Convert Edamam response to our recipe format
        final random = Random();

        for (
          int i = 0;
          i < hits.length && recipesById.length < maxResults;
          i++
        ) {
          final hit = hits[i] as Map<String, dynamic>;
          final recipe = hit['recipe'] as Map<String, dynamic>? ?? {};

          final converted = convertEdamamRecipe(recipe, random);
          if (converted != null) {
            final id = converted['id']?.toString();
            final key = (id != null && id.isNotEmpty)
                ? id
                : (converted['title']?.toString() ?? '').toLowerCase();
            if (key.isNotEmpty) {
              recipesById[key] = converted;
            }
          }
        }

        if (recipesById.length >= maxResults) {
          break;
        }
      }

      final recipes = recipesById.values.take(maxResults).toList();
      if (recipes.isNotEmpty) {
        await _saveToCache(cacheKey, recipes);
      }
      return recipes;
    } catch (e) {
      // Try to return stale cache on any error
      final staleCache = await _loadFromCache(cacheKey, ignoreExpiry: true);
      if (staleCache != null && staleCache.isNotEmpty) {
        return staleCache;
      }

      rethrow;
    }
  }

  /// Validate and clean up measurement strings
  String _validateAndCleanMeasurement(String measurement) {
    if (measurement.isEmpty) return measurement;

    // Split into quantity and unit parts
    final parts = measurement.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return measurement;

    // Extract quantity (first part)
    final quantity = parts[0];
    final unit = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    // Validate quantity - must be a valid number
    if (!RegExp(r'^[\d./]+$').hasMatch(quantity)) {
      return '';
    }

    // Descriptor words that appear after a count but are NOT real units
    // e.g. "2 large eggs" → Edamam gives quantity=2, measure="large" → store "2"
    const descriptorWords = {
      'large', 'medium', 'small', 'extra-large', 'xl', 'whole', 'each', 'ea',
      'fresh', 'ripe', 'raw', 'cooked', 'dried', 'frozen', 'chopped', 'diced',
      'sliced', 'minced', 'grated', 'shredded', 'peeled', 'pitted', 'halved',
      'quartered', 'crushed', 'ground', 'packed', 'heaping', 'level',
    };

    // Real cooking units that should be kept
    const validUnits = {
      'cup', 'cups', 'tbsp', 'tablespoon', 'tablespoons',
      'tsp', 'teaspoon', 'teaspoons',
      'oz', 'ounce', 'ounces', 'fl oz',
      'lb', 'lbs', 'pound', 'pounds',
      'g', 'gram', 'grams', 'kg', 'kilogram', 'kilograms',
      'ml', 'milliliter', 'milliliters', 'l', 'liter', 'liters',
      'qt', 'quart', 'quarts', 'pt', 'pint', 'pints', 'gal', 'gallon', 'gallons',
      'pinch', 'dash', 'drop',
      'clove', 'cloves', 'head', 'heads', 'stalk', 'stalks',
      'bunch', 'bunches', 'can', 'cans', 'jar', 'jars',
      'box', 'boxes', 'bag', 'bags', 'package', 'packages', 'pkg',
      'piece', 'pieces', 'slice', 'slices',
      'stick', 'sticks', 'sprig', 'sprigs', 'leaf', 'leaves',
      'serving', 'servings',
    };

    if (unit.isEmpty) return quantity;

    final unitLower = unit.toLowerCase();

    // If it's a real unit, keep it
    if (validUnits.contains(unitLower)) {
      return '$quantity $unit';
    }

    // If it's a descriptor word (large, whole, etc.), drop it — just show count
    if (descriptorWords.contains(unitLower)) {
      return quantity;
    }

    // Unknown unit — drop it to avoid showing garbage like "2 <unit>"
    if (unit == '<unit>' || unit.startsWith('<')) {
      return quantity;
    }

    // Multi-word unit check (e.g. "fl oz")
    if (validUnits.contains(unitLower)) {
      return '$quantity $unit';
    }

    // Default: drop unknown unit, show count only
    return quantity;
  }

  /// Convert Edamam recipe format to our app's format
  Map<String, dynamic>? convertEdamamRecipe(
    Map<String, dynamic> edamamRecipe,
    Random random,
  ) {
    try {
      // Extract basic info
      final uri = edamamRecipe['uri'] as String? ?? '';
      final recipeId = uri.split('#recipe_').last; // Extract ID from URI
      final title = edamamRecipe['label'] as String? ?? 'Untitled Recipe';

      // Get best quality image
      String imageUrl = '';
      final images = edamamRecipe['images'] as Map<String, dynamic>?;
      if (images != null) {
        // Prefer LARGE, then REGULAR, then SMALL, then THUMBNAIL
        if (images['LARGE'] != null) {
          imageUrl =
              (images['LARGE'] as Map<String, dynamic>)['url'] as String? ?? '';
        } else if (images['REGULAR'] != null) {
          imageUrl =
              (images['REGULAR'] as Map<String, dynamic>)['url'] as String? ??
              '';
        } else if (images['SMALL'] != null) {
          imageUrl =
              (images['SMALL'] as Map<String, dynamic>)['url'] as String? ?? '';
        } else if (images['THUMBNAIL'] != null) {
          imageUrl =
              (images['THUMBNAIL'] as Map<String, dynamic>)['url'] as String? ??
              '';
        }
      }
      // Fallback to simple image field
      if (imageUrl.isEmpty) {
        imageUrl = edamamRecipe['image'] as String? ?? '';
      }

      // NOTE: Edamam S3 signed URLs require the signature to load (403 without it).
      // Keep the full signed URL for live display. For persistence, we store a
      // curated fallback URL separately (handled in main.dart _saveUserProfile).

      // Extract ingredients with measurements
      final ingredientLines =
          (edamamRecipe['ingredientLines'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      final ingredientsData =
          edamamRecipe['ingredients'] as List<dynamic>? ?? [];

      // Build ingredient names and measurements from structured data
      final ingredientNames = <String>[];
      final ingredientMeasurements = <String, String>{};

      // First, use the structured ingredients data for accurate measurements
      for (final ing in ingredientsData) {
        if (ing is Map<String, dynamic>) {
          final food = ing['food'] as String? ?? '';
          final quantity = ing['quantity'] as num? ?? 0;
          final measure = ing['measure'] as String? ?? '';
          final text = ing['text'] as String? ?? '';

          if (food.isNotEmpty) {
            ingredientNames.add(food);

            // Build measurement string - prefer the full text for accuracy
            String measureStr = '';
            if (text.isNotEmpty) {
              // Extract just the quantity and unit from text (e.g., "2 cups all-purpose flour" → "2 cups")
              // Pattern matches: "2", "1.5", "1/2", "2 1/2" followed by optional unit
              final match = RegExp(
                r'^([\d./]+(?:\s+[\d./]+)?)\s+(cup|cups|tbsp|tablespoon|tablespoons|tsp|teaspoon|teaspoons|oz|ounce|ounces|lb|lbs|pound|pounds|g|gram|grams|kg|ml|liter|liters|l|pinch|dash|clove|cloves|head|heads|stalk|stalks|bunch|bunches|can|cans|jar|jars|box|boxes|bag|bags|package|packages|piece|pieces|slice|slices|whole|each|serving|servings)',
                caseSensitive: false,
              ).firstMatch(text);
              if (match != null) {
                final quantity = match.group(1)?.trim() ?? '';
                final unit = match.group(2)?.trim() ?? '';
                measureStr = '$quantity $unit';
              }
            }
            // Fallback to structured data if text parsing didn't work
            if (measureStr.isEmpty && quantity > 0) {
              if (quantity == quantity.roundToDouble()) {
                measureStr = quantity.toInt().toString();
              } else {
                measureStr = quantity.toStringAsFixed(1);
              }
              if (measure.isNotEmpty && measure != '<unit>') {
                measureStr += ' $measure';
              }
            }
            // Validate and clean up the measurement
            measureStr = _validateAndCleanMeasurement(measureStr);
            // Store the measurement (even if empty - let the UI handle display)
            ingredientMeasurements[food] = measureStr;
          }
        }
      }

      // IMPORTANT: Do NOT fall back to ingredientLines - it causes duplicates
      // If structured data gave us nothing, leave ingredients empty rather than duplicating
      // The UI will handle empty measurements gracefully

      // Extract nutrition info
      final totalNutrients =
          edamamRecipe['totalNutrients'] as Map<String, dynamic>? ?? {};
      final servings = (edamamRecipe['yield'] as num?)?.toDouble() ?? 4.0;

      // Get per-serving nutrition
      double getPerServing(String key) {
        final nutrient = totalNutrients[key] as Map<String, dynamic>?;
        if (nutrient == null) return 0.0;
        final quantity = (nutrient['quantity'] as num?)?.toDouble() ?? 0.0;
        return quantity / servings;
      }

      final nutrition = {
        'calories': getPerServing('ENERC_KCAL').round(),
        'protein': getPerServing('PROCNT'),
        'fat': getPerServing('FAT'),
        'carbs': getPerServing('CHOCDF'),
        'fiber': getPerServing('FIBTG'),
        'sugar': getPerServing('SUGAR'),
        'sodium': getPerServing('NA'),
      };

      // Cook time
      final totalTime = (edamamRecipe['totalTime'] as num?)?.toInt() ?? 0;
      final cookTime = totalTime > 0
          ? totalTime
          : (15 + random.nextInt(30)); // Random 15-45 min if not specified

      // Edamam doesn't provide instructions in API response
      // Instructions will be fetched from source URL via RecipeInstructionService
      // For now, return empty list - UI will fetch real instructions
      final instructions = <String>[];

      // Source info - ensure we have valid URL
      final source = edamamRecipe['source'] as String? ?? 'Edamam';
      String sourceUrl = edamamRecipe['url'] as String? ?? '';
      // Validate and clean the source URL
      if (sourceUrl.isNotEmpty && !sourceUrl.startsWith('http')) {
        sourceUrl = 'https://$sourceUrl';
      }

      // Diet and health labels for filtering
      final dietLabels =
          (edamamRecipe['dietLabels'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      final healthLabels =
          (edamamRecipe['healthLabels'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      // Meal type
      final mealTypes =
          (edamamRecipe['mealType'] as List<dynamic>?)
              ?.map((e) => e.toString().toLowerCase())
              .toList() ??
          ['lunch'];

      // Generate aspect ratio for visual variety
      final aspectChoices = [0.85, 0.88, 0.9, 0.92, 0.95];
      final aspectRatio = aspectChoices[random.nextInt(aspectChoices.length)];

      // No fake ratings - these will be calculated from actual in-app community reviews
      final rating = 0.0;
      final reviewCount = 0;

      return {
        'id': recipeId.isNotEmpty
            ? recipeId
            : DateTime.now().millisecondsSinceEpoch.toString(),
        'title': title,
        'imageUrl': imageUrl,
        'ingredients':
            ingredientNames, // Only use structured data, never raw lines
        'ingredientLines':
            ingredientLines, // Keep for reference but don't use in UI
        'ingredientMeasurements': ingredientMeasurements,
        'instructions': instructions,
        'cookTime': cookTime,
        'rating': double.parse(rating.toStringAsFixed(1)),
        'reviewCount': reviewCount,
        'nutrition': nutrition,
        'authorName': source,
        'sourceUrl': sourceUrl,
        'dietLabels': dietLabels,
        'healthLabels': healthLabels,
        'mealTypes': mealTypes,
        'aspectRatio': aspectRatio,
        'servings': servings > 0 ? servings.toInt() : 4,
      };
    } catch (e) {
      return null;
    }
  }

  
  /// Build cache key from ingredients
  String _buildCacheKey(List<Ingredient> ingredients) {
    final names =
        ingredients.map((ing) => ing.name.toLowerCase().trim()).toList()
          ..sort();
    return 'edamam_cache_v1_${names.take(5).join('_')}';
  }

  /// Load recipes from cache
  Future<List<Map<String, dynamic>>?> _loadFromCache(
    String cacheKey, {
    bool ignoreExpiry = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(cacheKey);
      final timestampKey = '${cacheKey}_timestamp';
      final timestamp = prefs.getInt(timestampKey);

      if (cachedJson == null) return null;

      // Check cache expiry
      if (!ignoreExpiry && timestamp != null) {
        final cacheAge = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(timestamp),
        );
        if (cacheAge.inMinutes >= _cacheMaxAgeMins) {
          return null;
        }
      }

      final decoded = jsonDecode(cachedJson) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      return null;
    }
  }

  /// Save recipes to cache (Edamam cache has 1hr TTL matching signed URL lifetime)
  Future<void> _saveToCache(
    String cacheKey,
    List<Map<String, dynamic>> recipes,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestampKey = '${cacheKey}_timestamp';

      await prefs.setString(cacheKey, jsonEncode(recipes));
      await prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      // ignore: empty catch blocks
    }
  }

  /// Clear all Edamam caches
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('edamam_cache_'));
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      // ignore: empty catch blocks
    }
  }
}
