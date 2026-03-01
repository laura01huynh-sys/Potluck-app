import 'package:flutter/material.dart';

/// Modal for creating a custom lifestyle (name + block list of ingredients).
/// Call [CreateLifestyleModal.show] to present it.
class CreateLifestyleModal extends StatefulWidget {
  final void Function(String name, List<String> blockList) onSave;

  const CreateLifestyleModal({
    super.key,
    required this.onSave,
  });

  /// Shows the create lifestyle modal. [onSave] is called with the name and
  /// block list when the user taps Save.
  static void show(
    BuildContext context, {
    required void Function(String name, List<String> blockList) onSave,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => CreateLifestyleModal(onSave: onSave),
    );
  }

  @override
  State<CreateLifestyleModal> createState() => _CreateLifestyleModalState();
}

class _CreateLifestyleModalState extends State<CreateLifestyleModal> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ingredientController = TextEditingController();
  final Set<String> _selectedIngredients = {};

  @override
  void dispose() {
    _nameController.dispose();
    _ingredientController.dispose();
    super.dispose();
  }

  void _tryAddIngredient() {
    final ingredient = _ingredientController.text.trim();
    if (ingredient.isNotEmpty) {
      setState(() {
        _selectedIngredients.add(ingredient);
        _ingredientController.clear();
      });
    }
  }

  void _onSave() {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selectedIngredients.isEmpty) return;
    widget.onSave(name, _selectedIngredients.toList());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final canSave =
        _selectedIngredients.isNotEmpty && _nameController.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey, width: 0.5),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Create Custom Lifestyle',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Name your lifestyle',
                      hintText: 'e.g., No Nightshades',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_selectedIngredients.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Selected Ingredients',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _selectedIngredients.map((ing) {
                            return Chip(
                              label: Text(ing),
                              onDeleted: () {
                                setState(() {
                                  _selectedIngredients.remove(ing);
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  TextField(
                    controller: _ingredientController,
                    decoration: InputDecoration(
                      labelText: 'Add ingredient',
                      hintText: 'Type any ingredient and press Add',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: _tryAddIngredient,
                      ),
                    ),
                    onSubmitted: (_) => _tryAddIngredient(),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: canSave ? _onSave : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canSave
                            ? const Color(0xFF10B981)
                            : Colors.grey,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Save Lifestyle'),
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
