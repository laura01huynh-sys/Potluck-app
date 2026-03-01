import 'package:flutter/material.dart';

import '../../../core/config/dietary_data.dart';
import '../../../core/constants.dart';
import '../../../services/dietary_filter_service.dart';
import '../models/user_profile.dart';
import '../utils/dialog_utils.dart';
import '../widgets/lifestyle_card.dart';
import '../widgets/restriction_chip.dart';
import '../../user/modals/create_lifestyle_modal.dart';
import '../../user/widgets/lifestyle_chip.dart';

/// Dietary Hub: manage allergies, avoided ingredients, lifestyles, and custom restrictions.
/// Uses copyWith pattern for immutable profile updates.
class DietaryHubScreen extends StatefulWidget {
  final UserProfile userProfile;
  final Function(UserProfile) onProfileUpdated;

  const DietaryHubScreen({
    super.key,
    required this.userProfile,
    required this.onProfileUpdated,
  });

  @override
  State<DietaryHubScreen> createState() => _DietaryHubScreenState();
}

class _DietaryHubScreenState extends State<DietaryHubScreen> {
  late UserProfile _profile;
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _profile = widget.userProfile;
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleAllergy(String ingredient) {
    final capitalizedIngredient = ingredient.isNotEmpty
        ? ingredient[0].toUpperCase() + ingredient.substring(1)
        : ingredient;

    setState(() {
      if (_profile.allergies.contains(capitalizedIngredient)) {
        _profile.allergies.remove(capitalizedIngredient);
      } else {
        _profile.allergies.add(capitalizedIngredient);
      }
    });
    _updateProfile();
  }

  void _toggleAvoidance(String ingredient) {
    final capitalizedIngredient = ingredient.isNotEmpty
        ? ingredient[0].toUpperCase() + ingredient.substring(1)
        : ingredient;

    setState(() {
      if (_profile.avoided.contains(capitalizedIngredient)) {
        _profile.avoided.remove(capitalizedIngredient);
      } else {
        _profile.avoided.add(capitalizedIngredient);
      }
    });
    _updateProfile();
  }

  void _toggleLifestyle(String lifestyle) {
    setState(() {
      if (_profile.selectedLifestyles.contains(lifestyle)) {
        _profile.selectedLifestyles.remove(lifestyle);
      } else {
        _profile.selectedLifestyles.add(lifestyle);
      }
    });
    _updateProfile();
  }

  void _toggleCustomLifestyle(String customId) {
    setState(() {
      if (_profile.activeCustomLifestyles.contains(customId)) {
        _profile.activeCustomLifestyles.remove(customId);
      } else {
        _profile.activeCustomLifestyles.add(customId);
      }
    });
    _updateProfile();
  }

  void _deleteCustomLifestyle(String id) {
    setState(() {
      _profile.customLifestyles.removeWhere((cl) => cl.id == id);
      _profile.activeCustomLifestyles.remove(id);
    });
    _updateProfile();
  }

  void _updateProfile() {
    final updated = _profile.copyWith(
      allergies: _profile.allergies,
      avoided: _profile.avoided,
      selectedLifestyles: _profile.selectedLifestyles,
      customLifestyles: _profile.customLifestyles,
      activeCustomLifestyles: _profile.activeCustomLifestyles,
    );
    widget.onProfileUpdated(updated);
  }

  List<String> _getSearchResults() {
    if (_searchController.text.isEmpty) return [];
    final allIngredients = [
      ...RecipeFilterService.getAllergyRiskIngredients(),
      ...RecipeFilterService.getCommonAvoidanceIngredients(),
    ];
    return allIngredients
        .where(
          (ing) =>
              ing.toLowerCase().contains(_searchController.text.toLowerCase()),
        )
        .toSet()
        .toList();
  }

  bool _hasSearchResults() => _getSearchResults().isNotEmpty;

  String _getSearchQuery() => _searchController.text.trim();

  void _showClassificationDialog(String ingredient) {
    final capitalizedIngredient = ingredient.isNotEmpty
        ? ingredient[0].toUpperCase() + ingredient.substring(1)
        : ingredient;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Classify: $capitalizedIngredient',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'How should we handle this?',
              style: TextStyle(fontSize: 16, color: Colors.black),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _toggleAllergy(ingredient);
                      _clearSearchAfterAdd();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 169, 72, 72),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text(
                            'Allergy',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Will hide recipes entirely',
                            style: TextStyle(color: Colors.black, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _toggleAvoidance(ingredient);
                      _clearSearchAfterAdd();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 232, 207, 137),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text(
                            'Avoid',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Will show an avoid label',
                            style: TextStyle(color: Colors.black, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  void _clearSearchAfterAdd() {
    setState(() => _searchController.clear());
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dietary Hub'),
        backgroundColor: kBoneCreame,
        foregroundColor: kDeepForestGreen,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          children: [
            _buildSearchSection(),
            const SizedBox(height: 20),
            _buildActiveRestrictionsSection(),
            const SizedBox(height: 20),
            _buildLifestyleGridSection(),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchSection() {
    final results = _getSearchResults();
    final hasResults = _hasSearchResults();
    final searchQuery = _getSearchQuery();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search for restrictions...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ),
        if (searchQuery.isNotEmpty && !hasResults) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showClassificationDialog(searchQuery),
              icon: const Icon(Icons.add),
              label: Text('Add "$searchQuery" as custom'),
            ),
          ),
        ] else if (hasResults) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) {
                final ingredient = results[index];
                final isAdded =
                    _profile.allergies.contains(ingredient) ||
                    _profile.avoided.contains(ingredient);

                return ListTile(
                  title: Text(ingredient),
                  onTap: isAdded
                      ? null
                      : () => _showClassificationDialog(ingredient),
                  trailing: isAdded
                      ? Icon(
                          Icons.check_circle,
                          color: _profile.allergies.contains(ingredient)
                              ? Colors.red
                              : Colors.grey,
                        )
                      : const Icon(
                          Icons.add_circle_outline,
                          color: Colors.grey,
                        ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActiveRestrictionsSection() {
    final allergies = _profile.allergies.toList();
    final avoided = _profile.avoided.toList();
    final lifestyles = _profile.selectedLifestyles.toList();
    final activeCustomLifestyles = _profile.customLifestyles
        .where((cl) => _profile.activeCustomLifestyles.contains(cl.id))
        .toList();

    if (allergies.isEmpty &&
        avoided.isEmpty &&
        lifestyles.isEmpty &&
        activeCustomLifestyles.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'My Restrictions',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: [
            ...lifestyles.map(
              (lifestyle) => RestrictionChip(
                label: lifestyle,
                type: 'lifestyle',
                onDeleted: () {
                  setState(() => _profile.selectedLifestyles.remove(lifestyle));
                  _updateProfile();
                },
              ),
            ),
            ...activeCustomLifestyles.map(
              (custom) => _buildCustomRestrictionChip(custom),
            ),
            ...allergies.map(
              (allergy) => RestrictionChip(
                label: allergy,
                type: 'allergy',
                onDeleted: () {
                  setState(() => _profile.allergies.remove(allergy));
                  _updateProfile();
                },
              ),
            ),
            ...avoided.map(
              (avoid) => RestrictionChip(
                label: avoid,
                type: 'avoid',
                onDeleted: () {
                  setState(() => _profile.avoided.remove(avoid));
                  _updateProfile();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCustomRestrictionChip(CustomLifestyle custom) {
    return Chip(
      label: Text(
        custom.name.isNotEmpty
            ? custom.name[0].toUpperCase() + custom.name.substring(1)
            : custom.name,
        style: TextStyle(
          color: Colors.blue.shade700,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: Colors.blue.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onDeleted: () {
        setState(() => _profile.activeCustomLifestyles.remove(custom.id));
        _updateProfile();
      },
    );
  }

  Widget _buildLifestyleGridSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lifestyles',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.0,
          children: [
            ...lifestyleDescriptions.entries.map((entry) {
              final lifestyle = entry.key;
              final isSelected = _profile.selectedLifestyles.contains(lifestyle);

              return LifestyleCard(
                lifestyle: lifestyle,
                isSelected: isSelected,
                onTap: () => _toggleLifestyle(lifestyle),
                onInfoTap: () => showLifestyleDefinition(context, lifestyle),
              );
            }),
            ..._profile.customLifestyles.map((custom) {
              final isSelected = _profile.activeCustomLifestyles.contains(custom.id);
              return LifestyleChip(
                custom: custom,
                isSelected: isSelected,
                onDismiss: () => _deleteCustomLifestyle(custom.id),
                onTap: () => _toggleCustomLifestyle(custom.id),
                onInfoTap: () => _showCustomLifestyleDefinition(custom),
              );
            }),
            _buildAddCustomChip(),
          ],
        ),
      ],
    );
  }

  void _showCustomLifestyleDefinition(CustomLifestyle custom) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(custom.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Excludes:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: custom.blockList.map((ingredient) {
                return Chip(
                  label: Text(ingredient),
                  backgroundColor: const Color(0xFFECFDF5),
                  side: const BorderSide(color: Color(0xFF10B981)),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildAddCustomChip() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showCreateCustomLifestyleModal,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300, width: 1.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                'Custom',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateCustomLifestyleModal() {
    CreateLifestyleModal.show(context, onSave: _saveCustomLifestyle);
  }

  void _saveCustomLifestyle(String name, List<String> blockList) {
    final capitalizedBlockList = blockList
        .map(
          (ingredient) => ingredient.isNotEmpty
              ? ingredient[0].toUpperCase() + ingredient.substring(1)
              : ingredient,
        )
        .toList();

    final newCustom = CustomLifestyle(
      id: DateTime.now().toString(),
      name: name,
      blockList: capitalizedBlockList,
    );

    setState(() {
      _profile.customLifestyles.add(newCustom);
      _profile.activeCustomLifestyles.add(newCustom.id);
    });
    _updateProfile();
  }
}
