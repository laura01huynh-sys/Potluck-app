import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants.dart';
import '../../../core/format.dart';
import '../../../core/widgets/blur_button.dart';
import '../../../features/pantry/models/pantry_view_state.dart';
import '../../../features/pantry/widgets/ingredient_chip.dart';
import '../../../models/ingredient.dart';
import '../../../services/gemini_detect_service.dart';

// Main Pantry screen: layout, search, categories, and AI-powered scan entrypoints.
class PantryScreen extends StatefulWidget {
  final Function(List<Ingredient>)? onIngredientsUpdated;
  final List<Ingredient> sharedIngredients;
  final Set<String> selectedIngredientIds;
  final Function(Set<String>) onSelectionChanged;
  final VoidCallback onFindRecipes;

  const PantryScreen({
    super.key,
    this.onIngredientsUpdated,
    required this.sharedIngredients,
    required this.selectedIngredientIds,
    required this.onSelectionChanged,
    required this.onFindRecipes,
  });

  @override
  State<PantryScreen> createState() => _PantryScreenState();
}

class _PantryScreenState extends State<PantryScreen> {
  final List<FridgeImage> _fridgeImages = [];
  // State for search and category filter
  String _searchQuery = '';
  IngredientCategory? _selectedCategory;
  final TextEditingController _searchController = TextEditingController();
  bool _isSelectionMode = false;
  Timer? _saveTimer;

  @override
  void dispose() {
    _searchController.dispose();
    _saveTimer?.cancel();
    super.dispose();
  }

  // AI-powered ingredient detection - uses Google Generative AI
  Future<void> _extractIngredientsAutomatically(FridgeImage fridgeImage) async {
    // Create a loading dialog overlay with CircularProgressIndicator
    final loadingDialogContext = context;
    showDialog(
      context: loadingDialogContext,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Analyzing image with AI...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // Use centralized API key from GeminiConfig (supports environment variables)
      const String apiKey = GeminiConfig.apiKey;

      // Check if API key is configured
      if (apiKey.isEmpty || apiKey == 'YOUR_GOOGLE_GENERATIVE_AI_API_KEY') {
        if (!mounted) return;
        Navigator.pop(context); // Close loading dialog
        return;
      }

      final detectionService = IngredientDetectionService(apiKey: apiKey);

      // Detect ingredients from image using AI
      final detectedIngredients =
          await detectionService.detectIngredientsFromImage(
        fridgeImage.imageFile,
      );

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      // If no ingredients detected, show message
      if (detectedIngredients.isEmpty) {
        return;
      }

      // Associate detected ingredients with the image
      final ingredientsWithImageId = detectedIngredients
          .map((ing) => ing.copyWith(imageId: fridgeImage.id))
          .toList();

      // Show Review Scan modal to let user confirm/edit detected ingredients
      if (mounted) {
        _showReviewScanModal(fridgeImage, ingredientsWithImageId);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
    }
  }

  void _showReviewScanModal(
    FridgeImage fridgeImage,
    List<Ingredient> detectedIngredients,
  ) {
    final reviewIngredients = List<Ingredient>.from(detectedIngredients);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            // HEADER: Grabber bar + Title
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(70),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    // Grabber bar
                    Padding(
                      padding: const EdgeInsets.only(top: 10.0, bottom: 8.0),
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2.5),
                          ),
                        ),
                      ),
                    ),
                    // Header title + close button
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Review Detected Items',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: kCharcoal,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                            color: kCharcoal,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // BODY: Scrollable ingredient list (center, like Instagram Comments)
            body: Container(
              color: Colors.white,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                itemCount: reviewIngredients.length,
                itemBuilder: (context, index) {
                  return _buildReviewIngredientTile(
                    reviewIngredients[index],
                    index,
                    reviewIngredients,
                    setModalState,
                  );
                },
              ),
            ),
            // BOTTOM BAR: Fixed Cancel and Confirm buttons (NEVER SCROLLS)
            bottomNavigationBar: Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                border: const Border(
                  top: BorderSide(color: Colors.grey, width: 0.5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: kDeepForestGreen),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: kDeepForestGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _confirmAndAddIngredients(
                          fridgeImage,
                          reviewIngredients,
                        );
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kSageGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Confirm',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReviewIngredientTile(
    Ingredient ingredient,
    int index,
    List<Ingredient> reviewIngredients,
    StateSetter setModalState,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ingredient name and remove button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  ingredient.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: kCharcoal,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: kSoftTerracotta),
                onPressed: () {
                  setModalState(() {
                    reviewIngredients.removeAt(index);
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Unit selector row
          Row(
            children: [
              const Expanded(
                child: SizedBox.shrink(), // units removed for pantry
              ),
              const SizedBox(width: 12),
              // Quantity adjuster
              _buildQuantityAdjuster(
                ingredient,
                index,
                reviewIngredients,
                setModalState,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityAdjuster(
    Ingredient ingredient,
    int index,
    List<Ingredient> reviewIngredients,
    StateSetter setModalState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Qty',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            GestureDetector(
              onTap: () {
                setModalState(() {
                  dynamic newAmount;
                  if (ingredient.unitType == UnitType.volume) {
                    newAmount = ((ingredient.amount as double) - 0.1).clamp(
                      0.0,
                      1.0,
                    );
                  } else {
                    newAmount = (amountAsInt(ingredient.amount) - 1).clamp(
                      0,
                      999,
                    );
                  }
                  reviewIngredients[index] = ingredient.copyWith(
                    amount: newAmount,
                  );
                });
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  border: Border.all(color: kSageGreen),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.remove, size: 16, color: kSageGreen),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 40,
              child: Text(
                ingredient.unitType == UnitType.volume
                    ? (() {
                        final amount = ingredient.amount as double;
                        // Remove .0 from whole numbers
                        if (amount == amount.round()) {
                          return amount.round().toString();
                        }
                        return amount.toStringAsFixed(1);
                      })()
                    : ingredient.amount.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                setModalState(() {
                  dynamic newAmount;
                  if (ingredient.unitType == UnitType.volume) {
                    newAmount = ((ingredient.amount as double) + 0.1).clamp(
                      0.0,
                      1.0,
                    );
                  } else {
                    newAmount = (amountAsInt(ingredient.amount) + 1).clamp(
                      0,
                      999,
                    );
                  }
                  reviewIngredients[index] = ingredient.copyWith(
                    amount: newAmount,
                  );
                });
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  border: Border.all(color: kSageGreen),
                  borderRadius: BorderRadius.circular(6),
                  color: kSageGreen.withOpacity(0.1),
                ),
                child: const Icon(Icons.add, size: 16, color: kSageGreen),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _confirmAndAddIngredients(
    FridgeImage fridgeImage,
    List<Ingredient> reviewIngredients,
  ) {
    if (reviewIngredients.isEmpty) {
      return;
    }

    setState(() {
      // Update fridge image with extracted ingredients
      final imageIndex = _fridgeImages.indexWhere(
        (img) => img.id == fridgeImage.id,
      );
      if (imageIndex != -1) {
        _fridgeImages[imageIndex] = _fridgeImages[imageIndex].copyWith(
          ingredients: reviewIngredients.map((ing) => ing.name).toList(),
        );
      }

      // Add to pantry - merge by ingredient name to avoid duplicates
      for (var ingredient in reviewIngredients) {
        final existingIndex = widget.sharedIngredients.indexWhere(
          (ing) => ing.name == ingredient.name,
        );

        if (existingIndex != -1) {
          // Ingredient already exists - merge the amounts
          final existing = widget.sharedIngredients[existingIndex];
          if (ingredient.unitType == existing.unitType &&
              ingredient.baseUnit == existing.baseUnit) {
            // Same unit type and base unit - combine amounts
            dynamic newAmount;
            if (ingredient.unitType == UnitType.volume) {
              newAmount =
                  ((existing.amount as double) + (ingredient.amount as double))
                      .clamp(0.0, 1.0);
            } else {
              final existingAmount = amountAsDouble(existing.amount);
              final addedAmount = amountAsDouble(ingredient.amount);
              final summed = existingAmount + addedAmount;
              newAmount =
                  ingredient.unitType == UnitType.count &&
                          summed == summed.roundToDouble()
                      ? summed.toInt()
                      : summed;
            }
            widget.sharedIngredients[existingIndex] = existing.copyWith(
              amount: newAmount,
            );
          } else {
            // Different units - don't merge, just add as is
            widget.sharedIngredients.add(ingredient);
          }
        } else {
          // New ingredient - add it
          widget.sharedIngredients.add(ingredient);
        }
      }

      // Clear the scanned image after confirming (UI cleanup)
      _fridgeImages.removeWhere((img) => img.id == fridgeImage.id);
    });

    _notifyIngredientsUpdated();
  }

  void _deleteImage(String imageId) {
    setState(() {
      _fridgeImages.removeWhere((img) => img.id == imageId);
      // Keep ingredients even after deleting the image
      // Just clear the imageId reference so they're no longer tied to this scan
      for (int i = 0; i < widget.sharedIngredients.length; i++) {
        if (widget.sharedIngredients[i].imageId == imageId) {
          widget.sharedIngredients[i] = widget.sharedIngredients[i].copyWith(
            imageId: null,
          );
        }
      }
    });
  }

  void _deleteIngredient(String ingredientId) {
    setState(() {
      widget.sharedIngredients.removeWhere((ing) => ing.id == ingredientId);
    });
    _notifyIngredientsUpdated();
  }

  void _notifyIngredientsUpdated() {
    // Cancel previous timer
    _saveTimer?.cancel();

    // Set a new timer to save after 1 second of inactivity
    _saveTimer = Timer(const Duration(seconds: 1), () {
      widget.onIngredientsUpdated?.call(
        List<Ingredient>.from(widget.sharedIngredients),
      );
    });
  }

  void _showAddIngredientDialog(FridgeImage fridgeImage) {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Ingredient'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter ingredient name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              _addIngredientManually(fridgeImage, value.trim());
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final ingredient = controller.text.trim();
              if (ingredient.isNotEmpty) {
                _addIngredientManually(fridgeImage, ingredient);
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: kSageGreen),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _addIngredientManually(FridgeImage fridgeImage, String ingredientName) {
    setState(() {
      // Check if ingredient already exists in this image
      final existingIngredients = _fridgeImages
          .firstWhere((img) => img.id == fridgeImage.id)
          .ingredients;

      if (!existingIngredients.contains(ingredientName)) {
        // Update the fridge image with the new ingredient
        final index = _fridgeImages.indexWhere(
          (img) => img.id == fridgeImage.id,
        );
        if (index != -1) {
          _fridgeImages[index] = _fridgeImages[index].copyWith(
            ingredients: [...existingIngredients, ingredientName],
          );
        }
      }

      // Add to main ingredients list if it doesn't exist
      if (!widget.sharedIngredients.any((ing) => ing.name == ingredientName)) {
        widget.sharedIngredients.add(
          Ingredient(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: ingredientName,
            imageId: fridgeImage.id,
            category: IngredientCategory.produce,
            unitType: UnitType.count,
            amount: 1,
            baseUnit: 'ea',
          ),
        );
      }
    });

    _notifyIngredientsUpdated();
  }

  @override
  Widget build(BuildContext context) {
    final viewState = PantryViewState.from(
      sharedIngredients: widget.sharedIngredients,
      searchQuery: _searchQuery,
      selectedCategory: _selectedCategory,
    );

    final activeIngredients = viewState.activeIngredients;
    final groupedByCategory = viewState.groupedByCategory;
    final allActiveIngredients = viewState.allActiveIngredients;
    final categoryCounts = viewState.categoryCounts;
    final categoriesWithItems = viewState.categoriesWithItems;
    final categoryOrder = IngredientCategory.displayOrder;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSelectionMode
              ? '${widget.selectedIngredientIds.length} Selected'
              : 'My Pantry',
        ),
        actions: [
          if (!_isSelectionMode)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: PotluckBlurButton(
                label: 'Select',
                onPressed: () {
                  setState(() {
                    _isSelectionMode = true;
                  });
                },
              ),
            ),
          if (_isSelectionMode)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: PotluckBlurButton(
                label: 'Cancel',
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
                    widget.onSelectionChanged({});
                  });
                },
              ),
            ),
        ],
      ),
      floatingActionButton: widget.selectedIngredientIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: widget.onFindRecipes,
              backgroundColor: kDeepForestGreen,
              icon: const Icon(Icons.restaurant_menu, color: Colors.white),
              label: Text(
                'Find Recipes (${widget.selectedIngredientIds.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: widget.sharedIngredients.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.kitchen, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(
                      'No ingredients yet',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                // Search Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search ingredients...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: kDeepForestGreen,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                // Category Filter Row
                if (categoriesWithItems.isNotEmpty)
                  SizedBox(
                    height: 36,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(left: 20, right: 16),
                      itemCount:
                          categoriesWithItems.length + 1, // +1 for "All" chip
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          // "All" chip
                          final isSelected = _selectedCategory == null;
                          final totalCount = allActiveIngredients.length;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedCategory = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? kDeepForestGreen
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected
                                        ? kDeepForestGreen
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'All',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected
                                            ? Colors.white
                                            : kCharcoal,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.white.withOpacity(0.2)
                                            : kDeepForestGreen.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        totalCount.toString(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected
                                              ? Colors.white
                                              : kDeepForestGreen,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        final category = categoriesWithItems[index - 1];
                        final isSelected = _selectedCategory == category;
                        final count = categoryCounts[category] ?? 0;

                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedCategory = isSelected
                                    ? null
                                    : category;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? kDeepForestGreen
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? kDeepForestGreen
                                      : Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    category.displayName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? Colors.white
                                          : kCharcoal,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.white.withOpacity(0.2)
                                          : kDeepForestGreen.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      count.toString(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected
                                            ? Colors.white
                                            : kDeepForestGreen,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                // Ingredient List
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 140),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Active Ingredients with Categorized Chips
                          if (activeIngredients.isNotEmpty) ...[
                            // Display categories in order
                            ...categoryOrder
                                .where(
                                  (cat) => groupedByCategory.containsKey(cat),
                                )
                                .map((category) {
                                  final ingredients =
                                      groupedByCategory[category]!;

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        category.displayName,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: kDeepForestGreen,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          alignment: WrapAlignment.start,
                                          children: ingredients.map((
                                            ingredient,
                                          ) {
                                            final isSelected = widget
                                                .selectedIngredientIds
                                                .contains(ingredient.id);
                                            return IngredientChip(
                                              ingredient: ingredient,
                                              isSelected: isSelected,
                                              selectionEnabled: _isSelectionMode,
                                              onToggleSelected: () {
                                                if (!_isSelectionMode) return;
                                                final newSelection =
                                                    Set<String>.from(
                                                  widget.selectedIngredientIds,
                                                );
                                                if (isSelected) {
                                                  newSelection.remove(
                                                    ingredient.id,
                                                  );
                                                } else {
                                                  newSelection
                                                      .add(ingredient.id);
                                                }
                                                widget.onSelectionChanged(
                                                  newSelection,
                                                );
                                              },
                                              onDelete: () =>
                                                  _deleteIngredient(
                                                ingredient.id,
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                    ],
                                  );
                                }),
                          ] else if (_searchQuery.isNotEmpty ||
                              _selectedCategory != null) ...[
                            // Empty state when filters active but no results
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 40,
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.search_off,
                                      size: 48,
                                      color: Colors.grey.shade300,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No ingredients found',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _searchQuery = '';
                                          _searchController.clear();
                                          _selectedCategory = null;
                                        });
                                      },
                                      child: const Text('Clear filters'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          // Scanned Images Horizontal Reel
                          if (_fridgeImages.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Scanned Images',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: kCharcoal,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 120,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _fridgeImages.length,
                                itemBuilder: (context, index) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: _buildImageThumbnail(
                                      _fridgeImages[index],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildImageThumbnail(FridgeImage fridgeImage) {
    final ingredientsFromImage = widget.sharedIngredients
        .where((ing) => ing.imageId == fridgeImage.id)
        .length;

    return GestureDetector(
      onTap: () => _showScanReviewModal(fridgeImage),
      child: Column(
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  fridgeImage.imageFile,
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => _deleteImage(fridgeImage.id),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ingredientsFromImage > 0
                ? '$ingredientsFromImage item${ingredientsFromImage > 1 ? 's' : ''}'
                : 'Review',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: kCharcoal,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showScanReviewModal(FridgeImage fridgeImage) {
    final ingredientsFromImage = widget.sharedIngredients
        .where((ing) => ing.imageId == fridgeImage.id)
        .map((ing) => ing.name)
        .toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with close button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Scan Details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: kCharcoal,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Full-size image
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    fridgeImage.imageFile,
                    width: double.infinity,
                    height: 250,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 16),
                // Timestamp info
                Row(
                  children: [
                    Icon(
                      fridgeImage.source == ImageSource.camera
                          ? Icons.camera_alt
                          : Icons.photo_library,
                      size: 14,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      fridgeImage.timestamp.toString().split('.')[0],
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Ingredients section
                if (ingredientsFromImage.isNotEmpty) ...[
                  const Text(
                    'Ingredients from this scan:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: kCharcoal,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ingredientsFromImage
                        .map(
                          (ingredient) => Chip(
                            label: Text(ingredient),
                            backgroundColor: kSageGreen.withOpacity(0.2),
                            labelStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showAddIngredientDialog(fridgeImage);
                      },
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Add More Ingredients'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kSageGreen,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ] else ...[
                  const Text(
                    'No ingredients extracted yet',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: kCharcoal,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _extractIngredientsAutomatically(fridgeImage);
                      },
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Auto Extract Ingredients'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kSageGreen,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

