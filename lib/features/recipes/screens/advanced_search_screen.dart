import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../profile/models/user_profile.dart';
import '../models/recipe_filters.dart';

/// Advanced search / filter screen: diets, intolerances, cuisines, meal types,
/// prep time, macros, cooking methods. Applies selections via [onApplyFilters].
class AdvancedSearchScreen extends StatefulWidget {
  final UserProfile userProfile;
  final Function(Map<String, dynamic>) onApplyFilters;

  const AdvancedSearchScreen({
    super.key,
    required this.userProfile,
    required this.onApplyFilters,
  });

  @override
  State<AdvancedSearchScreen> createState() => _AdvancedSearchScreenState();
}

class _AdvancedSearchScreenState extends State<AdvancedSearchScreen> {
  late Set<String> _selectedDiets;
  late Set<String> _selectedIntolerances;
  late Set<String> _selectedCuisines;
  late Set<String> _selectedMealTypes;
  late Set<String> _selectedCookingMethods;
  late Set<String> _selectedMacroGoals;
  String _selectedPrepTime = '';
  late TextEditingController _searchController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _selectedDiets = Set<String>.from(
      widget.userProfile.selectedLifestyles.where(
        (l) => RecipeFilterOptions.diets.map((d) => d.toLowerCase()).contains(l),
      ),
    );
    _selectedIntolerances = Set<String>.from(widget.userProfile.allergies);
    _selectedCuisines = {};
    _selectedMealTypes = {};
    _selectedCookingMethods = {};
    _selectedMacroGoals = {};
    _selectedPrepTime = '';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    final filters = {
      'diets': _selectedDiets.toList(),
      'intolerances': _selectedIntolerances.toList(),
      'cuisines': _selectedCuisines.toList(),
      'mealTypes': _selectedMealTypes.toList(),
      'cookingMethods': _selectedCookingMethods.toList(),
      'macroGoals': _selectedMacroGoals.toList(),
      'prepTime': _selectedPrepTime,
      'searchQuery': _searchQuery,
    };
    widget.onApplyFilters(filters);
    Navigator.pop(context);
  }

  Widget _buildFilterSection(
    String title,
    List<String> items,
    Set<String> selected,
    bool isHighContrast,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: kDeepForestGreen,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((item) {
            final isSelected = selected.contains(item);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    selected.remove(item);
                  } else {
                    selected.add(item);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isHighContrast
                            ? Colors.red.shade100
                            : kSageGreen.withOpacity(0.2))
                      : Colors.grey.shade100,
                  border: Border.all(
                    color: isSelected
                        ? (isHighContrast ? Colors.red.shade400 : kSageGreen)
                        : Colors.grey.shade300,
                    width: isHighContrast && isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  item,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? (isHighContrast
                              ? Colors.red.shade700
                              : kDeepForestGreen)
                        : kSoftSlateGray,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced Search'),
        backgroundColor: kBoneCreame,
        foregroundColor: kDeepForestGreen,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search recipes...',
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: kDeepForestGreen, width: 2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: kDeepForestGreen, width: 2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: kDeepForestGreen,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: kBoneCreame.withOpacity(0.5),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: 24),
                _buildFilterSection(
                  'Diet & Lifestyle',
                  RecipeFilterOptions.diets,
                  _selectedDiets,
                  false,
                ),
                const SizedBox(height: 24),
                _buildFilterSection(
                  'Intolerances & Allergies',
                  RecipeFilterOptions.intolerances,
                  _selectedIntolerances,
                  true,
                ),
                const SizedBox(height: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Preparation & Time',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: kDeepForestGreen,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: RecipeFilterOptions.prepTimes.map((time) {
                        final isSelected = _selectedPrepTime == time;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedPrepTime = isSelected ? '' : time;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? kSageGreen.withOpacity(0.2)
                                  : Colors.grey.shade100,
                              border: Border.all(
                                color: isSelected
                                    ? kSageGreen
                                    : Colors.grey.shade300,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              time,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected
                                    ? kDeepForestGreen
                                    : kSoftSlateGray,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildFilterSection(
                  'Meal Type',
                  RecipeFilterOptions.mealTypes,
                  _selectedMealTypes,
                  false,
                ),
                const SizedBox(height: 24),
                _buildFilterSection(
                  'Global Cuisines',
                  RecipeFilterOptions.cuisines,
                  _selectedCuisines,
                  false,
                ),
                const SizedBox(height: 24),
                _buildFilterSection(
                  'Nutritional Goals (Macros)',
                  RecipeFilterOptions.macroGoals,
                  _selectedMacroGoals,
                  false,
                ),
                const SizedBox(height: 24),
                _buildFilterSection(
                  'Cooking Method & Equipment',
                  RecipeFilterOptions.cookingMethods,
                  _selectedCookingMethods,
                  false,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20 + MediaQuery.of(context).padding.bottom,
            child: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _applyFilters,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kDeepForestGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Apply Filters',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
