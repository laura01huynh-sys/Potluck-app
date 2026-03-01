import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/constants.dart';
import '../../../../core/format.dart';
import '../../../../models/ingredient.dart';
import '../../../../models/recipe.dart';
import '../../../../models/review.dart';
import '../../../profile/models/user_profile.dart';

/// Recipe card used in feed, discover, and profile (saved/cooked).
/// Navigation and image caching are provided by the parent via [onTap],
/// [onEditRecipe], and [ensureRecipeImageCached].
class RecipeCard extends StatefulWidget {
  final List<Ingredient> sharedIngredients;
  final Function(List<Ingredient>) onIngredientsUpdated;
  final String recipeTitle;
  final List<String> recipeIngredients;
  final int cookTime;
  final double rating;
  final int reviewCount;
  final double matchPercentage;
  final int missingCount;
  final List<String> missingIngredients;
  final bool isReadyToCook;
  final bool isRecommendation;
  final bool isCookedTab;
  final UserProfile? userProfile;
  final Function(UserProfile)? onProfileUpdated;
  final String? recipeId;
  final String? imageUrl;
  final Function(String)? onDelete;
  final bool isAuthor;
  final double aspectRatio;
  final Nutrition? nutrition;
  final List<String> instructions;
  final Map<String, String> ingredientMeasurements;
  final Function(CommunityReview)? onAddCommunityReview;
  final List<CommunityReview> communityReviews;
  final String? sourceUrl;
  final int defaultServings;
  final Set<String> dismissedRestockIds;
  final String? authorName;
  final String? authorAvatar;
  final String? authorId;
  final bool isDiscoverFeed;
  final void Function(String? authorId)? onFollowAuthor;
  final bool isFollowing;

  /// When null: 18 for For You, 14 for Discover. Pass 14 for Profile saved/cooked.
  final double? titleFontSize;

  /// Called when the card is tapped. Parent should push [RecipeDetailPage].
  final void Function(BuildContext context) onTap;

  /// Optional. When the user taps edit (author card). Parent should push [RecipeEntryScreen].
  final void Function(BuildContext context)? onEditRecipe;

  /// Optional. When saving a recipe, parent can download and cache the image.
  final Future<void> Function(String recipeId, String? imageUrl)?
      ensureRecipeImageCached;

  const RecipeCard({
    super.key,
    required this.sharedIngredients,
    required this.onIngredientsUpdated,
    required this.recipeTitle,
    required this.recipeIngredients,
    required this.cookTime,
    required this.rating,
    required this.reviewCount,
    required this.matchPercentage,
    required this.missingCount,
    required this.missingIngredients,
    required this.isReadyToCook,
    required this.isRecommendation,
    required this.onTap,
    this.userProfile,
    this.onProfileUpdated,
    this.recipeId,
    this.imageUrl,
    this.onDelete,
    this.isAuthor = false,
    this.aspectRatio = 1.0,
    this.nutrition,
    this.instructions = const [],
    this.ingredientMeasurements = const {},
    this.isCookedTab = false,
    this.onAddCommunityReview,
    required this.communityReviews,
    this.sourceUrl,
    this.defaultServings = 4,
    this.dismissedRestockIds = const {},
    this.authorName,
    this.authorAvatar,
    this.authorId,
    this.isDiscoverFeed = false,
    this.onFollowAuthor,
    this.isFollowing = false,
    this.titleFontSize,
    this.onEditRecipe,
    this.ensureRecipeImageCached,
  });

  @override
  State<RecipeCard> createState() => _RecipeCardState();
}

class _RecipeCardState extends State<RecipeCard> {
  void _removeCookedRecipe(BuildContext context) {
    if (widget.userProfile == null || widget.recipeId == null) return;
    final updatedCookedIds = List<String>.from(
      widget.userProfile!.cookedRecipeIds,
    );
    updatedCookedIds.remove(widget.recipeId!);
    final updatedProfile = widget.userProfile!.copyWith(
      cookedRecipeIds: updatedCookedIds,
    );
    widget.onProfileUpdated?.call(updatedProfile);
  }

  late bool _isSaved;
  bool _quickAdded = false;

  @override
  void initState() {
    super.initState();
    _quickAdded = widget.isFollowing;
    _updateSavedState();
  }

  @override
  void didUpdateWidget(RecipeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userProfile != widget.userProfile) {
      _updateSavedState();
    }
    if (oldWidget.isFollowing != widget.isFollowing) {
      _quickAdded = widget.isFollowing;
    }
  }

  void _updateSavedState() {
    _isSaved =
        widget.userProfile != null &&
        widget.recipeId != null &&
        widget.userProfile!.savedRecipeIds.contains(widget.recipeId);
  }

  Future<void> _toggleSave(BuildContext context) async {
    if (widget.userProfile == null || widget.recipeId == null) return;

    setState(() {
      _isSaved = !_isSaved;
    });

    final updatedSavedIds = Set<String>.from(
      widget.userProfile!.savedRecipeIds,
    );

    if (_isSaved) {
      updatedSavedIds.add(widget.recipeId!);
      if (widget.ensureRecipeImageCached != null) {
        await widget.ensureRecipeImageCached!(
          widget.recipeId!,
          widget.imageUrl,
        );
      }
    } else {
      updatedSavedIds.remove(widget.recipeId!);
    }

    final updatedProfile = widget.userProfile!.copyWith(
      savedRecipeIds: updatedSavedIds.toList(),
    );

    widget.onProfileUpdated?.call(updatedProfile);
  }

  void _editRecipe(BuildContext context) {
    if (widget.recipeId == null) return;
    widget.onEditRecipe?.call(context);
  }

  @override
  Widget build(BuildContext context) {
    // Show only top review comment on recipe card preview
    final reviewsForThis = widget.communityReviews
        .where((r) => r.recipeId == widget.recipeId)
        .toList();
    String? topReviewComment;
    if (reviewsForThis.isNotEmpty) {
      reviewsForThis.sort((a, b) => b.likes.compareTo(a.likes));
      topReviewComment = reviewsForThis.first.comment;
    }

    return GestureDetector(
      onTap: () => widget.onTap(context),
      onDoubleTap: () => _toggleSave(context),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: widget.aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
                      (widget.imageUrl!.startsWith('/')
                          ? Image.file(
                              File(widget.imageUrl!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) {
                                return Container(
                                  color: kBoneCreame,
                                  child: Center(
                                    child: Icon(
                                      Icons.restaurant,
                                      size: 60,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                );
                              },
                            )
                          : Image.network(
                              widget.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) {
                                return Container(
                                  color: kBoneCreame,
                                  child: Center(
                                    child: Icon(
                                      Icons.restaurant,
                                      size: 60,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                );
                              },
                            )),
                    if (widget.imageUrl == null || widget.imageUrl!.isEmpty)
                      Container(
                        color: kBoneCreame,
                        child: Center(
                          child: Icon(
                            Icons.restaurant,
                            size: 60,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.75),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.85),
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: Builder(
                                builder: (context) {
                                  final total = widget.recipeIngredients.length;
                                  final have = (total - widget.missingCount)
                                      .clamp(0, total);
                                  final raw = total > 0
                                      ? '$have/$total'
                                      : '0/0';

                                  final boldStyle = TextStyle(
                                    color: kDeepForestGreen,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                  );
                                  final normalStyle = TextStyle(
                                    color: kDeepForestGreen,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.3,
                                  );

                                  final spans = <TextSpan>[];
                                  final reg = RegExp(r'(\d+|/)');
                                  int last = 0;
                                  for (final m in reg.allMatches(raw)) {
                                    if (m.start > last) {
                                      spans.add(
                                        TextSpan(
                                          text: raw.substring(last, m.start),
                                          style: normalStyle,
                                        ),
                                      );
                                    }
                                    spans.add(
                                      TextSpan(
                                        text: m.group(0),
                                        style: boldStyle,
                                      ),
                                    );
                                    last = m.end;
                                  }
                                  if (last < raw.length) {
                                    spans.add(
                                      TextSpan(
                                        text: raw.substring(last),
                                        style: normalStyle,
                                      ),
                                    );
                                  }

                                  return RichText(
                                    textAlign: TextAlign.center,
                                    text: TextSpan(children: spans),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.userProfile != null && widget.recipeId != null)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: widget.isCookedTab
                            ? GestureDetector(
                                onTap: () => _removeCookedRecipe(context),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: BackdropFilter(
                                    filter: ui.ImageFilter.blur(
                                      sigmaX: 20,
                                      sigmaY: 20,
                                    ),
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withOpacity(0.75),
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.close,
                                          size: 20,
                                          color: kDeepForestGreen,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : (widget.isAuthor
                                  ? GestureDetector(
                                      onTap: () {
                                        if (widget.recipeId != null) {
                                          widget.onDelete?.call(
                                            widget.recipeId!,
                                          );
                                        }
                                      },
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(20),
                                        child: BackdropFilter(
                                          filter: ui.ImageFilter.blur(
                                            sigmaX: 20,
                                            sigmaY: 20,
                                          ),
                                          child: Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.white.withOpacity(
                                                0.75,
                                              ),
                                            ),
                                            child: const Center(
                                              child: Icon(
                                                Icons.close,
                                                size: 20,
                                                color: kDeepForestGreen,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                  : GestureDetector(
                                      onTap: () => _toggleSave(context),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(20),
                                        child: BackdropFilter(
                                          filter: ui.ImageFilter.blur(
                                            sigmaX: 20,
                                            sigmaY: 20,
                                          ),
                                          child: Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.white.withOpacity(
                                                0.75,
                                              ),
                                            ),
                                            child: Center(
                                              child: Icon(
                                                _isSaved
                                                    ? Icons.favorite
                                                    : Icons.favorite_outline,
                                                size: 20,
                                                color: kDeepForestGreen,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    )),
                      ),
                    if (widget.isDiscoverFeed && widget.authorName != null)
                      Positioned(
                        bottom: 12,
                        left: 12,
                        right: 12,
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Text(
                            widget.authorName!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Stack(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.isDiscoverFeed && widget.authorName != null)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                widget.recipeTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Playfair Display',
                                  fontSize:
                                      widget.titleFontSize ??
                                      (widget.isDiscoverFeed ? 14 : 18),
                                  fontWeight: FontWeight.bold,
                                  color: kDeepForestGreen,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            SizedBox(
                              width: 44,
                              child: Center(
                                child: GestureDetector(
                                  onTap: () {
                                    if (widget.authorId != null) {
                                      // TODO: Navigate to user profile
                                    }
                                  },
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: kDeepForestGreen,
                                        backgroundImage:
                                            widget.authorAvatar != null
                                            ? NetworkImage(widget.authorAvatar!)
                                            : null,
                                        child: widget.authorAvatar == null
                                            ? Text(
                                                widget.authorName?.isNotEmpty ==
                                                        true
                                                    ? widget.authorName![0]
                                                          .toUpperCase()
                                                    : 'U',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              )
                                            : null,
                                      ),
                                      if (widget.authorName != null)
                                        Positioned(
                                          bottom: -2,
                                          right: -8,
                                          child: GestureDetector(
                                            onTap: () {
                                              if (widget.onFollowAuthor !=
                                                      null &&
                                                  !_quickAdded) {
                                                widget.onFollowAuthor!(
                                                  widget.authorId,
                                                );
                                                setState(() {
                                                  _quickAdded = true;
                                                });
                                              } else if (widget
                                                      .onFollowAuthor ==
                                                  null) {
                                                setState(() {
                                                  _quickAdded = !_quickAdded;
                                                });
                                              }
                                            },
                                            child: Container(
                                              width: 18,
                                              height: 18,
                                              decoration: BoxDecoration(
                                                color: _quickAdded
                                                    ? Colors.black
                                                    : Colors.grey.shade600,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 2,
                                                ),
                                              ),
                                              child: Icon(
                                                _quickAdded
                                                    ? Icons.check
                                                    : Icons.add,
                                                size: 10,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          widget.recipeTitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Playfair Display',
                            fontSize:
                                widget.titleFontSize ??
                                (widget.isDiscoverFeed ? 14 : 18),
                            fontWeight: FontWeight.bold,
                            color: kDeepForestGreen,
                            height: 1.2,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: kSoftSlateGray,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            formatCookTime(widget.cookTime),
                            style: const TextStyle(
                              fontSize: 13,
                              color: kSoftSlateGray,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(Icons.star, size: 14, color: kMutedGold),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${widget.rating.toStringAsFixed(1)} (${widget.reviewCount})',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: kSoftSlateGray,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (topReviewComment != null) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 0),
                          child: Text(
                            topReviewComment,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: kSoftSlateGray,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (widget.isAuthor)
                    Positioned(
                      top: -5,
                      right: -5,
                      child: GestureDetector(
                        onTap: () => _editRecipe(context),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.edit,
                              size: 16,
                              color: Color.fromARGB(255, 87, 91, 94),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
