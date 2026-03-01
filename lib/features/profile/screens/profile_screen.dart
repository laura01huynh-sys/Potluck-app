import 'package:flutter/material.dart';

import '../../../models/ingredient.dart';
import '../../../models/recipe.dart';
import '../../../models/review.dart';
import '../../../services/dietary_filter_service.dart';
import '../models/user_profile.dart';
import '../services/profile_recipe_provider.dart';
import '../widgets/dietary_hub_button.dart';
import '../widgets/kitchen_stats_card.dart';
import '../widgets/palate_empty_state.dart';
import '../widgets/profile_header.dart';
import '../widgets/profile_recipe_grid.dart';
import '../widgets/profile_tab_bar.dart';
import '../widgets/profile_avatar_handler.dart';
import '../widgets/restriction_section.dart';

/// Coordinating profile screen: header, stats, tabs, and tab content.
/// Delegates to extracted widgets and services.
class ProfileScreen extends StatefulWidget {
  final List<Ingredient> pantryIngredients;
  final void Function(List<Ingredient>) onIngredientsUpdated;
  final UserProfile userProfile;
  final void Function(UserProfile) onProfileUpdated;
  final void Function(CommunityReview)? onAddCommunityReview;
  final List<CommunityReview> communityReviews;
  final int followerCount;
  final List<Map<String, dynamic>> userRecipes;
  final List<Map<String, dynamic>> fetchedRecipesCache;
  final void Function(BuildContext context, Recipe recipe) onRecipeTap;
  final void Function(String recipeId)? onDeleteRecipe;

  const ProfileScreen({
    super.key,
    this.pantryIngredients = const [],
    required this.onIngredientsUpdated,
    required this.userProfile,
    required this.onProfileUpdated,
    this.onAddCommunityReview,
    required this.communityReviews,
    this.followerCount = 0,
    required this.userRecipes,
    required this.fetchedRecipesCache,
    required this.onRecipeTap,
    this.onDeleteRecipe,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late UserProfile _profile;
  late List<CommunityReview> _communityReviews;
  String _selectedTab = 'Saved';

  @override
  void initState() {
    super.initState();
    _profile = widget.userProfile;
    _communityReviews = widget.communityReviews;
  }

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userProfile != widget.userProfile ||
        oldWidget.communityReviews != widget.communityReviews) {
      setState(() {
        _profile = widget.userProfile;
        _communityReviews = widget.communityReviews;
      });
    }
  }

  void _onProfileUpdated(UserProfile updatedProfile) {
    setState(() => _profile = updatedProfile);
    widget.onProfileUpdated(updatedProfile);
  }

  ProfileRecipeProvider _getProvider() {
    return ProfileRecipeProvider(
      userProfile: _profile,
      communityReviews: _communityReviews,
      userRecipes: widget.userRecipes,
      fetchedRecipesCache: widget.fetchedRecipesCache,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          PotluckProfileHeader(
            userName: _profile.userName,
            avatarUrl: _profile.avatarUrl,
            onAvatarTap: () => ProfileAvatarHandler.changeProfilePicture(
              context,
              profile: _profile,
              onProfileUpdated: _onProfileUpdated,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: KitchenStatsCard(
              madeCount: _getProvider().getCookedRecipesCount().toString(),
              sharedCount: _getProvider().getSharedRecipesCount().toString(),
              followerCount: widget.followerCount.toString(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: ProfileTabBar(
              tabNames: const ['Saved', 'Cooked', 'My Dishes', 'Dietary'],
              selectedTab: _selectedTab,
              onTabSelected: (tab) => setState(() => _selectedTab = tab),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
            child: _buildTabContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 'Saved':
        return _buildSavedContent();
      case 'Cooked':
        return _buildCookedContent();
      case 'My Dishes':
        return _buildMyDishesContent();
      case 'Dietary':
        return _buildDietaryContent();
      default:
        return _buildSavedContent();
    }
  }

  Widget _buildSavedContent() {
    final provider = _getProvider();
    var savedRecipes = provider.getSavedRecipes();
    savedRecipes = RecipeFilterService.filterRecipes(savedRecipes, _profile);
    if (_profile.selectedLifestyles.contains('high-protein')) {
      savedRecipes = RecipeFilterService.sortByProtein(savedRecipes, true);
    }

    return ProfileRecipeGrid(
      recipes: savedRecipes,
      pantryIngredients: widget.pantryIngredients,
      onIngredientsUpdated: widget.onIngredientsUpdated,
      userProfile: _profile,
      onProfileUpdated: _onProfileUpdated,
      communityReviews: widget.communityReviews,
      onAddCommunityReview: widget.onAddCommunityReview,
      onRecipeTap: widget.onRecipeTap,
      emptyMessage: 'No saved recipes yet',
      emptyIcon: Icons.favorite_outline,
    );
  }

  Widget _buildCookedContent() {
    final cookedRecipes = _getProvider().getCookedRecipes();

    return ProfileRecipeGrid(
      recipes: cookedRecipes,
      pantryIngredients: widget.pantryIngredients,
      onIngredientsUpdated: widget.onIngredientsUpdated,
      userProfile: _profile,
      onProfileUpdated: _onProfileUpdated,
      communityReviews: widget.communityReviews,
      onAddCommunityReview: widget.onAddCommunityReview,
      onRecipeTap: widget.onRecipeTap,
      isCookedTab: true,
      emptyMessage: 'No cooked recipes yet',
      emptyIcon: Icons.restaurant,
    );
  }

  Widget _buildMyDishesContent() {
    final myRecipes = _getProvider().getMyDishesRecipes();

    return ProfileRecipeGrid(
      recipes: myRecipes,
      pantryIngredients: widget.pantryIngredients,
      onIngredientsUpdated: widget.onIngredientsUpdated,
      userProfile: _profile,
      onProfileUpdated: _onProfileUpdated,
      communityReviews: widget.communityReviews,
      onAddCommunityReview: widget.onAddCommunityReview,
      onRecipeTap: widget.onRecipeTap,
      onDelete: widget.onDeleteRecipe,
      isAuthorTab: true,
      emptyMessage: 'No shared recipes yet',
      emptyIcon: Icons.share,
    );
  }

  Widget _buildDietaryContent() {
    final lifestyleLabels = [
      ..._profile.selectedLifestyles,
      ..._profile.customLifestyles
          .where((c) => _profile.activeCustomLifestyles.contains(c.id))
          .map((c) => c.name),
    ];
    final hasRestrictions = _profile.allergies.isNotEmpty ||
        _profile.avoided.isNotEmpty ||
        lifestyleLabels.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DietaryHubButton(
          userProfile: _profile,
          onProfileUpdated: widget.onProfileUpdated,
        ),
        const SizedBox(height: 24),
        RestrictionSection(
          title: 'Allergies',
          items: _profile.allergies.toList(),
          variant: 'allergy',
        ),
        RestrictionSection(
          title: 'Avoided Ingredients',
          items: _profile.avoided.toList(),
          variant: 'avoided',
        ),
        RestrictionSection(
          title: 'Lifestyles',
          items: lifestyleLabels,
          variant: 'lifestyle',
        ),
        if (!hasRestrictions) const PalateEmptyState(),
      ],
    );
  }
}
