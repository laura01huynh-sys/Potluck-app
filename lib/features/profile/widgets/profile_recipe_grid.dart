import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../../core/format.dart';
import '../../../models/ingredient.dart';
import '../../../models/recipe.dart';
import '../../../models/review.dart';
import '../../../services/ingredient_match_service.dart';
import '../../recipe/widgets/recipe_card.dart';
import '../models/user_profile.dart';

/// Generic recipe grid for profile tabs (Saved, Cooked, My Dishes).
/// Renders MasonryGridView with RecipeCard and pantry match logic.
class ProfileRecipeGrid extends StatelessWidget {
  final List<Recipe> recipes;
  final List<Ingredient> pantryIngredients;
  final void Function(List<Ingredient>) onIngredientsUpdated;
  final UserProfile userProfile;
  final void Function(UserProfile) onProfileUpdated;
  final List<CommunityReview> communityReviews;
  final void Function(CommunityReview)? onAddCommunityReview;
  final void Function(BuildContext context, Recipe recipe) onRecipeTap;
  final bool isCookedTab;
  final void Function(String recipeId)? onDelete;
  final bool isAuthorTab;
  final String? emptyMessage;
  final IconData? emptyIcon;

  const ProfileRecipeGrid({
    super.key,
    required this.recipes,
    required this.pantryIngredients,
    required this.onIngredientsUpdated,
    required this.userProfile,
    required this.onProfileUpdated,
    required this.communityReviews,
    required this.onRecipeTap,
    this.isCookedTab = false,
    this.onDelete,
    this.isAuthorTab = false,
    this.emptyMessage,
    this.emptyIcon,
  });

  @override
  Widget build(BuildContext context) {
    if (recipes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(
                emptyIcon ?? Icons.restaurant_menu,
                size: 48,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              Text(
                emptyMessage ?? 'No recipes yet',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return MasonryGridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: recipes.length,
      itemBuilder: (context, index) {
        final recipe = recipes[index];
        final imageUrlToUse =
            recipe.imageUrl.isNotEmpty ? recipe.imageUrl : '';

        final (matchPercentage, missingCount, missingIngredients) =
            _computePantryMatch(recipe);

        return RecipeCard(
          sharedIngredients: pantryIngredients,
          onIngredientsUpdated: onIngredientsUpdated,
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
          onTap: (ctx) => onRecipeTap(ctx, recipe),
          userProfile: userProfile,
          onProfileUpdated: onProfileUpdated,
          recipeId: recipe.id,
          imageUrl: imageUrlToUse,
          aspectRatio: 0.9,
          nutrition: recipe.nutrition,
          isCookedTab: isCookedTab,
          isAuthor: isAuthorTab,
          titleFontSize: 14,
          onAddCommunityReview: onAddCommunityReview,
          communityReviews: communityReviews,
          sourceUrl: recipe.sourceUrl,
          onDelete: onDelete,
        );
      },
    );
  }

  (double, int, List<String>) _computePantryMatch(Recipe recipe) {
    double matchPercentage = 0.0;
    int missingCount = 0;
    List<String> missingIngredients = const [];

    if (pantryIngredients.isNotEmpty) {
      final pantryNames = pantryIngredients
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
        if (IngredientMatchService.isBasicStaple(recipeIng)) {
          matched++;
          continue;
        }
        final hasIngredient = pantryNames.any(
          (pantryNameLower) =>
              IngredientMatchService.ingredientMatches(
                  recipeIng, pantryNameLower),
        );
        if (hasIngredient) matched++;
      }
      matchPercentage = (matched / recipe.ingredients.length) * 100.0;
      missingIngredients = recipe.ingredients.where((recipeIng) {
        if (IngredientMatchService.isBasicStaple(recipeIng)) return false;
        final hasIngredient = pantryNames.any(
          (pantryNameLower) =>
              IngredientMatchService.ingredientMatches(
                  recipeIng, pantryNameLower),
        );
        return !hasIngredient;
      }).toList();
      missingCount = missingIngredients.length;
    } else {
      missingCount = recipe.ingredients.length;
      missingIngredients = List<String>.from(recipe.ingredients);
    }

    return (matchPercentage, missingCount, missingIngredients);
  }
}
