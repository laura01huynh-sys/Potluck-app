import 'dart:math';

import '../../../models/recipe.dart';
import '../../../models/review.dart';
import '../models/user_profile.dart';

/// Provides recipe data for the profile screen (saved, cooked, my dishes).
/// Accepts recipe caches from [RecipeFeedScreenState] to avoid circular imports.
class ProfileRecipeProvider {
  final UserProfile userProfile;
  final List<CommunityReview> communityReviews;
  final List<Map<String, dynamic>> userRecipes;
  final List<Map<String, dynamic>> fetchedRecipesCache;

  ProfileRecipeProvider({
    required this.userProfile,
    required this.communityReviews,
    required this.userRecipes,
    required this.fetchedRecipesCache,
  });

  static const List<double> _aspectChoices = [0.85, 0.88, 0.9, 0.92, 0.95];
  static final Random _random = Random();

  /// Count cooked recipes that actually exist in the recipe caches.
  int getCookedRecipesCount() {
    final allRecipeIds = <dynamic>{
      ...userRecipes.map((map) => map['id'] as String),
      ...fetchedRecipesCache.map((map) => map['id'] as String),
    };
    return userProfile.cookedRecipeIds
        .where((id) => allRecipeIds.contains(id))
        .length;
  }

  /// Count shared recipes (recipes posted by the user).
  int getSharedRecipesCount() {
    return userRecipes
        .where((recipe) => recipe['authorName'] == 'You')
        .length;
  }

  /// Returns saved recipes as [Recipe] objects, filtered by saved IDs.
  List<Recipe> getSavedRecipes() {
    final allRecipeMaps = [...userRecipes, ...fetchedRecipesCache];

    final savedRecipes = <Recipe>[];
    for (var map in allRecipeMaps) {
      final id = map['id'] as String;
      if (!userProfile.savedRecipeIds.contains(id)) continue;

      final recipeReviews =
          communityReviews.where((r) => r.recipeId == id).toList();
      final realReviewCount = recipeReviews.length;
      final realRating = realReviewCount > 0
          ? recipeReviews.map((r) => r.rating).reduce((a, b) => a + b) /
                realReviewCount
          : 0.0;

      savedRecipes.add(_mapToRecipe(map, realRating, realReviewCount, true));
    }
    return savedRecipes;
  }

  /// Returns cooked recipes as [Recipe] objects.
  List<Recipe> getCookedRecipes() {
    final allRecipeMaps = [...userRecipes, ...fetchedRecipesCache];

    final cookedRecipes = <Recipe>[];
    for (var map in allRecipeMaps) {
      final id = map['id'] as String;
      if (!userProfile.cookedRecipeIds.contains(id)) continue;

      final recipeReviews =
          communityReviews.where((r) => r.recipeId == id).toList();
      final realReviewCount = recipeReviews.length;
      final realRating = realReviewCount > 0
          ? recipeReviews.map((r) => r.rating).reduce((a, b) => a + b) /
                realReviewCount
          : 0.0;

      cookedRecipes.add(_mapToRecipe(map, realRating, realReviewCount, false));
    }
    return cookedRecipes;
  }

  /// Returns user's own recipes (authorName == 'You') as [Recipe] objects.
  List<Recipe> getMyDishesRecipes() {
    return userRecipes
        .where((map) => map['authorName'] == 'You')
        .map((map) {
          final id = map['id'] as String;
          final recipeReviews =
              communityReviews.where((r) => r.recipeId == id).toList();
          final realReviewCount = recipeReviews.length;
          final realRating = realReviewCount > 0
              ? recipeReviews.map((r) => r.rating).reduce((a, b) => a + b) /
                    realReviewCount
              : 0.0;
          return _mapToRecipe(map, realRating, realReviewCount, false);
        })
        .toList();
  }

  Recipe _mapToRecipe(
    Map<String, dynamic> map,
    double realRating,
    int realReviewCount,
    bool isSaved,
  ) {
    final imageUrl = map['imageUrl'] as String?;
    final image = map['image'] as String?;
    final images = map['images'];
    final fallbackImage = images is List && images.isNotEmpty
        ? (images.first as Map?)?['url'] as String?
        : null;

    return Recipe(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'Untitled',
      imageUrl: imageUrl ?? image ?? fallbackImage ?? '',
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
      isSaved: isSaved,
      mealTypes: ['lunch'],
      proteinGrams: 0,
      authorName: map['authorName'] as String? ?? 'Gemini',
      aspectRatio: _aspectChoices[_random.nextInt(_aspectChoices.length)],
      nutrition: map['nutrition'] != null
          ? Nutrition.fromMap(map['nutrition'] as Map<String, dynamic>)
          : null,
      sourceUrl: map['sourceUrl'] as String?,
    );
  }
}
