/// Nutrition facts for a recipe (calories, macros). Used only as a field on [Recipe].
class Nutrition {
  final int calories;
  final double protein;
  final double fat;
  final double carbs;
  final double? fiber;
  final double? sugar;
  final double? sodium;

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