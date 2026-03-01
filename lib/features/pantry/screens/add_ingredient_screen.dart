import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants.dart';
import '../../../models/ingredient.dart';
import 'confirm_scan_screen.dart';

class AddIngredientScreen extends StatefulWidget {
  final Function(int) onSwitchTab;
  final Function(List<Ingredient>) onAddIngredients;

  const AddIngredientScreen({
    super.key,
    required this.onSwitchTab,
    required this.onAddIngredients,
  });

  @override
  State<AddIngredientScreen> createState() => _AddIngredientScreenState();
}

class _AddIngredientScreenState extends State<AddIngredientScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _ingredientController = TextEditingController();
  final List<Ingredient> _quickAddedIngredients = [];
  IngredientCategory _selectedCategory = IngredientCategory.produce;

  @override
  void dispose() {
    _ingredientController.dispose();
    super.dispose();
  }

  void _addQuickIngredient() {
    final name = _ingredientController.text.trim();

    if (name.isEmpty) {
      return;
    }

    // Use default values - count type with amount 1
    final ingredient = Ingredient(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      category: _selectedCategory,
      unitType: UnitType.count,
      amount: 1,
      baseUnit: 'ea',
    );

    setState(() {
      _quickAddedIngredients.add(ingredient);
      _ingredientController.clear();
      _selectedCategory = IngredientCategory.produce;
    });
  }

  void _removeQuickIngredient(int index) {
    setState(() {
      _quickAddedIngredients.removeAt(index);
    });
  }

  Future<void> _processImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null && mounted) {
        // Navigate to confirmation screen with the image
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ConfirmDetectedItemsScreen(
              imageFile: File(image.path),
              onAddIngredients: widget.onAddIngredients,
            ),
          ),
        );
      }
    } catch (e) {
      // Image selection error - silently handle
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Add Ingredients'),
        backgroundColor: kBoneCreame,
        foregroundColor: kDeepForestGreen,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24.0,
              40.0,
              24.0,
              80.0 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // Camera and Gallery Buttons (Side by Side)
                Row(
                  children: [
                    Expanded(
                      child: _buildOptionButton(
                        icon: Icons.camera_alt,
                        label: 'Scan Fridge',
                        subtitle: 'Take a Photo',
                        onTap: () => _processImage(ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildOptionButton(
                        icon: Icons.image,
                        label: 'Upload Image',
                        subtitle: 'From Gallery',
                        onTap: () => _processImage(ImageSource.gallery),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                // Quick Add Section
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick Add',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: kDeepForestGreen,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Name field
                    TextField(
                      controller: _ingredientController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Ingredient Name',
                        hintText: 'e.g., Tomatoes, Milk',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Category pill boxes
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Category',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: IngredientCategory.values.map((category) {
                            final isSelected = _selectedCategory == category;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedCategory = category;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? kDeepForestGreen
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? kDeepForestGreen
                                        : Colors.grey.shade300,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Text(
                                  category.displayName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Add button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _addQuickIngredient,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kDeepForestGreen,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Add Ingredient',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Display added ingredients
                    if (_quickAddedIngredients.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _quickAddedIngredients.asMap().entries.map((
                          entry,
                        ) {
                          final index = entry.key;
                          final ing = entry.value;
                          // Format quantity based on unit type
                          final quantityStr = ing.unitType == UnitType.volume
                              ? (() {
                                  final amount = ing.amount as double;
                                  // Remove .0 from whole numbers
                                  if (amount == amount.round()) {
                                    return amount.round().toString();
                                  }
                                  return amount.toStringAsFixed(1);
                                })()
                              : ing.amount.toString();
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: kSageGreen.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: kSageGreen),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      ing.name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: kDeepForestGreen,
                                      ),
                                    ),
                                    Text(
                                      '$quantityStr ${ing.baseUnit}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: kSoftSlateGray,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => _removeQuickIngredient(index),
                                  child: Icon(
                                    Icons.close,
                                    size: 16,
                                    color: kDeepForestGreen,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    if (_quickAddedIngredients.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            if (_quickAddedIngredients.isEmpty) return;
                            // Copy the list before clearing
                            final ingredientsToAdd = List<Ingredient>.from(
                              _quickAddedIngredients,
                            );
                            // Clear local state first
                            setState(() {
                              _quickAddedIngredients.clear();
                            });
                            // Add ingredients to pantry
                            widget.onAddIngredients(ingredientsToAdd);
                            // Switch tab after a frame to avoid rebuild issues
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                widget.onSwitchTab(0);
                              }
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kSageGreen,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Save Ingredients',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    bool isFullWidth = false,
  }) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: isFullWidth ? 20 : 28,
          horizontal: 24,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kDeepForestGreen, width: 2),
          boxShadow: [
            BoxShadow(
              color: kDeepForestGreen.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: isFullWidth
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 36, color: kDeepForestGreen),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: kDeepForestGreen,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: kSoftSlateGray),
                      ),
                    ],
                  ),
                ],
              )
            : Column(
                children: [
                  Icon(icon, size: 48, color: kDeepForestGreen),
                  const SizedBox(height: 16),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: kDeepForestGreen,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: kSoftSlateGray),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
      ),
    );

    return isFullWidth
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}
