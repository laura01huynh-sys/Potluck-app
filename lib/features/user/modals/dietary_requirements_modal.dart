import 'package:flutter/material.dart';

import '../../../features/profile/models/user_profile.dart';
import '../../../features/profile/widgets/dietary_restriction_pills.dart';
import '../../../models/ingredient.dart';
import '../../../services/dietary_filter_service.dart';

/// Modal for managing dietary requirements: allergies, avoided ingredients,
/// lifestyles, and custom restrictions. Uses [RecipeFilterService] for
/// getAllergyRiskIngredients and getCommonAvoidanceIngredients.
class DietaryRestrictionsModal extends StatefulWidget {
  final UserProfile profile;
  final Function(String) onAllergyToggle;
  final Function(String) onAvoidedToggle;
  final Function(String) onLifestyleToggle;
  final Function(String) onAddCustomRestriction;
  final Function(String) onRemoveCustomRestriction;
  final VoidCallback onClearAllFilters;
  final List<Ingredient> pantryIngredients;

  const DietaryRestrictionsModal({
    super.key,
    required this.profile,
    required this.onAllergyToggle,
    required this.onAvoidedToggle,
    required this.onLifestyleToggle,
    required this.onAddCustomRestriction,
    required this.onRemoveCustomRestriction,
    required this.onClearAllFilters,
    required this.pantryIngredients,
  });

  @override
  State<DietaryRestrictionsModal> createState() =>
      _DietaryRestrictionsModalState();
}

class _DietaryRestrictionsModalState extends State<DietaryRestrictionsModal>
    with SingleTickerProviderStateMixin {
  late TextEditingController _searchController;
  late TextEditingController _customRestrictionController;
  String _searchQuery = '';
  late Set<String> _localAllergies;
  late Set<String> _localAvoided;
  late Set<String> _localLifestyles;
  late List<String> _localCustomRestrictions;
  late TabController _tabController;

  static const Map<String, String> _lifestyles = {
    'vegan': 'No animal products',
    'vegetarian': 'No meat or fish',
    'keto': 'Low carb, high fat',
    'paleo': 'No grains or processed foods',
    'gluten-free': 'No gluten',
    'pescatarian': 'Fish ok, no land meat',
    'kosher': 'Kosher dietary laws',
    'high-protein': 'Prioritize high protein',
  };

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _customRestrictionController = TextEditingController();
    _tabController = TabController(length: 3, vsync: this);

    _localAllergies = Set.from(widget.profile.allergies);
    _localAvoided = Set.from(widget.profile.avoided);
    _localLifestyles = Set.from(widget.profile.selectedLifestyles);
    _localCustomRestrictions = List.from(widget.profile.customRestrictions);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customRestrictionController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _toggleIngredient(String ingredient, bool isAllergy) {
    setState(() {
      if (isAllergy) {
        if (_localAllergies.contains(ingredient)) {
          _localAllergies.remove(ingredient);
        } else {
          _localAllergies.add(ingredient);
        }
      } else {
        if (_localAvoided.contains(ingredient)) {
          _localAvoided.remove(ingredient);
        } else {
          _localAvoided.add(ingredient);
        }
      }
    });

    Future.microtask(() {
      if (isAllergy) {
        widget.onAllergyToggle(ingredient);
      } else {
        widget.onAvoidedToggle(ingredient);
      }
    });
  }

  void _toggleLifestyle(String lifestyle) {
    setState(() {
      if (_localLifestyles.contains(lifestyle)) {
        _localLifestyles.remove(lifestyle);
      } else {
        _localLifestyles.add(lifestyle);
      }
    });

    Future.microtask(() => widget.onLifestyleToggle(lifestyle));
  }

  void _addCustomRestriction() {
    final restriction = _customRestrictionController.text.trim();
    if (restriction.isNotEmpty &&
        !_localCustomRestrictions.contains(restriction)) {
      setState(() {
        _localCustomRestrictions.add(restriction);
      });
      widget.onAddCustomRestriction(restriction);
      _customRestrictionController.clear();
    }
  }

  void _removeCustomRestriction(String restriction) {
    setState(() {
      _localCustomRestrictions.remove(restriction);
    });
    widget.onRemoveCustomRestriction(restriction);
  }

  Color _getLifestyleColor(String lifestyle) {
    switch (lifestyle) {
      case 'vegan':
        return Colors.green;
      case 'vegetarian':
        return Colors.lime;
      case 'keto':
        return Colors.purple;
      case 'paleo':
        return Colors.brown;
      case 'gluten-free':
        return Colors.amber;
      case 'pescatarian':
        return Colors.blue;
      case 'kosher':
        return Colors.deepOrange;
      case 'high-protein':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Dietary Requirements',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.grey,
                        ),
                        onPressed: widget.onClearAllFilters,
                        tooltip: 'Clear all filters',
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Ingredients'),
                Tab(text: 'Lifestyles'),
                Tab(text: 'Custom'),
              ],
            ),
            Divider(color: Colors.grey.shade200),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          setState(() => _searchQuery = value);
                        },
                        decoration: InputDecoration(
                          hintText: 'Search ingredients...',
                          prefixIcon: const Icon(Icons.search),
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
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      buildRestrictionSection(
                        'Allergies',
                        '⚠️',
                        Colors.red.shade200,
                        _localAllergies,
                        (ingredient) => _toggleIngredient(ingredient, true),
                        RecipeFilterService.getAllergyRiskIngredients(),
                        _searchQuery,
                      ),
                      const SizedBox(height: 24),

                      buildRestrictionSection(
                        'Avoid',
                        '👎',
                        Colors.orange.shade200,
                        _localAvoided,
                        (ingredient) => _toggleIngredient(ingredient, false),
                        RecipeFilterService.getCommonAvoidanceIngredients(),
                        _searchQuery,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),

                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Select your dietary lifestyle(s)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: _lifestyles.entries.map((entry) {
                          final lifestyle = entry.key;
                          final description = entry.value;
                          final isSelected =
                              _localLifestyles.contains(lifestyle);
                          final color = _getLifestyleColor(lifestyle);

                          return GestureDetector(
                            onTap: () => _toggleLifestyle(lifestyle),
                            child: Container(
                              width:
                                  (MediaQuery.of(context).size.width - 48) / 2,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? color.withOpacity(0.15)
                                    : Colors.grey.shade50,
                                border: Border.all(
                                  color: isSelected
                                      ? color
                                      : Colors.grey.shade300,
                                  width: isSelected ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          lifestyle
                                              .replaceAll('-', ' ')
                                              .split(' ')
                                              .map(
                                                (w) =>
                                                    w[0].toUpperCase() +
                                                    w.substring(1),
                                              )
                                              .join(' '),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected
                                                ? Colors.black87
                                                : Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        Icon(
                                          Icons.check_circle,
                                          color: color,
                                          size: 20,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    description,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),

                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Add custom restrictions',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _customRestrictionController,
                              onSubmitted: (_) => _addCustomRestriction(),
                              decoration: InputDecoration(
                                hintText: 'Enter restriction...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _addCustomRestriction,
                            icon: const Icon(Icons.add),
                            label: const Text('Add'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (_localCustomRestrictions.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Your Custom Restrictions (${_localCustomRestrictions.length})',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _localCustomRestrictions.map((restriction) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                border: Border.all(color: Colors.blue.shade200),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    restriction,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () =>
                                        _removeCustomRestriction(restriction),
                                    child: Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.blue.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
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
