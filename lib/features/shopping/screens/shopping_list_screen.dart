import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants.dart';
import '../../../models/ingredient.dart';
import '../models/shopping_list.dart';

class ShoppingListScreen extends StatefulWidget {
  final List<Ingredient> pantryIngredients;
  final Function(String ingredientId) onRestock;
  final Function(List<Ingredient>) onAddIngredients;
  final Function(String ingredientId)? onDismissRestock;

  const ShoppingListScreen({
    super.key,
    required this.pantryIngredients,
    required this.onRestock,
    required this.onAddIngredients,
    this.onDismissRestock,
  });

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  String _currentPage = 'lists';
  List<ShoppingItem> _restockItems = [];
  List<ShoppingList> _shoppingLists = [];
  String? _selectedListId;
  Set<String> _dismissedRestockIds = {};
  final TextEditingController _manualAddController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController(
    text: '1',
  );

  @override
  void initState() {
    super.initState();
    _loadDismissedRestockIds().then((_) {
      _restockItems = widget.pantryIngredients
          .where(
            (ing) =>
                ing.needsPurchase && !_dismissedRestockIds.contains(ing.id),
          )
          .map(
            (ing) => ShoppingItem(
              id: ing.id,
              name: ing.name,
              unit: ing.baseUnit,
              isFromRestock: true,
            ),
          )
          .toList();
      if (mounted) setState(() {});
    });
    _loadShoppingLists();
  }

  @override
  void didUpdateWidget(ShoppingListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pantryIngredients != widget.pantryIngredients) {
      _buildRestockList();
    }
  }

  @override
  void dispose() {
    _manualAddController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _loadShoppingLists() async {
    final prefs = await SharedPreferences.getInstance();
    final listsJson = prefs.getStringList('shopping_lists') ?? [];

    setState(() {
      _shoppingLists = listsJson
          .map((json) => ShoppingList.fromJson(jsonDecode(json)))
          .toList();

      if (_shoppingLists.isEmpty) {
        _shoppingLists.add(
          ShoppingList(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: 'My Shopping List',
          ),
        );
        _saveShoppingLists();
      }

      _selectedListId = _shoppingLists.first.id;
    });
  }

  Future<void> _saveShoppingLists() async {
    final prefs = await SharedPreferences.getInstance();
    final listsJson = _shoppingLists
        .map((list) => jsonEncode(list.toJson()))
        .toList();
    await prefs.setStringList('shopping_lists', listsJson);
  }

  void _buildRestockList() {
    setState(() {
      _restockItems = widget.pantryIngredients
          .where(
            (ing) =>
                ing.needsPurchase && !_dismissedRestockIds.contains(ing.id),
          )
          .map(
            (ing) => ShoppingItem(
              id: ing.id,
              name: ing.name,
              unit: ing.baseUnit,
              isFromRestock: true,
            ),
          )
          .toList();
    });
  }

  Future<void> _loadDismissedRestockIds() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getStringList('dismissed_restock_ids') ?? [];
    _dismissedRestockIds = Set<String>.from(dismissed);
  }

  Future<void> _saveDismissedRestockIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'dismissed_restock_ids',
      _dismissedRestockIds.toList(),
    );
  }

  ShoppingList? get _selectedList {
    if (_selectedListId == null) return null;
    try {
      return _shoppingLists.firstWhere((l) => l.id == _selectedListId);
    } catch (_) {
      return _shoppingLists.isNotEmpty ? _shoppingLists.first : null;
    }
  }

  void _moveToList(ShoppingItem item) {
    if (_selectedList == null) return;
    setState(() {
      _restockItems.removeWhere((i) => i.id == item.id);
      _selectedList!.items.add(item);
    });
    _saveShoppingLists();
  }

  void _dismissFromRestock(String itemId) {
    setState(() {
      _restockItems.removeWhere((i) => i.id == itemId);
      _dismissedRestockIds.add(itemId);
    });
    _saveDismissedRestockIds();
    widget.onDismissRestock?.call(itemId);
  }

  void _addManualItem() {
    final name = _manualAddController.text.trim();
    final quantity = _quantityController.text.trim();
    if (name.isNotEmpty && _selectedList != null) {
      setState(() {
        _selectedList!.items.add(
          ShoppingItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: name,
            quantity: quantity.isNotEmpty ? quantity : '1',
            unit: 'ea',
            isFromRestock: false,
          ),
        );
      });
      _manualAddController.clear();
      _quantityController.text = '1';
      _saveShoppingLists();
    }
  }

  void _removeFromList(String itemId) {
    if (_selectedList == null) return;
    setState(() {
      _selectedList!.items.removeWhere((i) => i.id == itemId);
    });
    _saveShoppingLists();
  }

  void _checkOffItem(ShoppingItem item) {
    if (item.isFromRestock) {
      widget.onRestock(item.id);
    }

    setState(() {
      item.isChecked = true;
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _removeFromList(item.id);
      }
    });
  }

  void _createNewList() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New List'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'List name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final cleaned = controller.text.trim();
              if (cleaned.isNotEmpty) {
                setState(() {
                  final newList = ShoppingList(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: cleaned,
                  );
                  _shoppingLists.add(newList);
                  _selectedListId = newList.id;
                });
                _saveShoppingLists();
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: kDeepForestGreen),
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showListOptions(ShoppingList list) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              list.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: kDeepForestGreen,
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.edit, color: kDeepForestGreen),
              title: const Text('Rename List'),
              onTap: () {
                Navigator.pop(context);
                _renameList(list);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: kSoftTerracotta),
              title: const Text(
                'Delete List',
                style: TextStyle(color: kSoftTerracotta),
              ),
              onTap: () {
                Navigator.pop(context);
                _deleteList(list);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _renameList(ShoppingList list) {
    final controller = TextEditingController(text: list.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename List'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final cleaned = controller.text.trim();
              if (cleaned.isNotEmpty) {
                setState(() {
                  list.name = cleaned;
                });
                _saveShoppingLists();
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: kDeepForestGreen),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _deleteList(ShoppingList list) {
    if (_shoppingLists.length <= 1) {
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete List?'),
        content: Text('Are you sure you want to delete "${list.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _shoppingLists.removeWhere((l) => l.id == list.id);
                if (_selectedListId == list.id) {
                  _selectedListId = _shoppingLists.first.id;
                }
              });
              _saveShoppingLists();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: kSoftTerracotta),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopping List'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _currentPage = 'lists'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _currentPage == 'lists'
                            ? kDeepForestGreen
                            : Colors.grey.shade100,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          bottomLeft: Radius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Lists (${_selectedList?.items.length ?? 0})',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _currentPage == 'lists'
                              ? Colors.white
                              : kCharcoal,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _currentPage = 'restock'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _currentPage == 'restock'
                            ? kDeepForestGreen
                            : Colors.grey.shade100,
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Restock (${_restockItems.length})',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _currentPage == 'restock'
                              ? Colors.white
                              : kCharcoal,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _currentPage == 'restock'
                ? _buildRestockPage()
                : _buildListsPage(),
          ),
        ],
      ),
    );
  }

  Widget _buildRestockPage() {
    if (_restockItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 60, color: kSageGreen),
            const SizedBox(height: 12),
            Text(
              'All stocked up!',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Text(
              'No ingredients need restocking',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      itemCount: _restockItems.length,
      itemBuilder: (context, index) {
        final item = _restockItems[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Out of stock',
                        style: TextStyle(fontSize: 12, color: kSoftTerracotta),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => _moveToList(item),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kSageGreen,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  child: const Text(
                    'Add to List',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => _dismissFromRestock(item.id),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildListsPage() {
    return Column(
      children: [
        if (_shoppingLists.length > 1)
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _shoppingLists.length + 1,
              itemBuilder: (context, index) {
                if (index == _shoppingLists.length) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: _createNewList,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.grey.shade300,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add, size: 18, color: kDeepForestGreen),
                            const SizedBox(width: 4),
                            Text(
                              'New List',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: kDeepForestGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                final list = _shoppingLists[index];
                final isSelected = list.id == _selectedListId;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedListId = list.id;
                      });
                    },
                    onLongPress: () => _showListOptions(list),
                    child: Container(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 8,
                        top: 8,
                        bottom: 8,
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
                            list.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : kCharcoal,
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
                              list.items.length.toString(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.white
                                    : kDeepForestGreen,
                              ),
                            ),
                          ),
                          if (_shoppingLists.length > 1) ...[
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => _deleteList(list),
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: isSelected
                                    ? Colors.white70
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        if (_shoppingLists.length > 1) const SizedBox(height: 12),
        if (_shoppingLists.length == 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _shoppingLists.first.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: kDeepForestGreen,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.add_circle_outline,
                    color: kDeepForestGreen,
                  ),
                  onPressed: _createNewList,
                  tooltip: 'Create new list',
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: kDeepForestGreen),
                  onSelected: (value) {
                    if (_selectedList == null) return;
                    if (value == 'rename') {
                      _renameList(_selectedList!);
                    } else if (value == 'delete') {
                      _deleteList(_selectedList!);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _manualAddController,
                  decoration: InputDecoration(
                    hintText: 'Add item...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Qty',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addManualItem,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kDeepForestGreen,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _selectedList == null || _selectedList!.items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shopping_cart_outlined,
                        size: 60,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Your list is empty',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add items above or from the Restock tab',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: _selectedList!.items.length,
                  itemBuilder: (context, index) {
                    final item = _selectedList!.items[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: item.isChecked
                            ? Colors.grey.shade100
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: item.isChecked
                              ? Colors.grey.shade300
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: ListTile(
                        leading: GestureDetector(
                          onTap: () => _checkOffItem(item),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: item.isChecked
                                  ? kSageGreen
                                  : Colors.transparent,
                              border: Border.all(
                                color: item.isChecked
                                    ? kSageGreen
                                    : Colors.grey.shade400,
                              ),
                            ),
                            child: item.isChecked
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 20,
                                  )
                                : null,
                          ),
                        ),
                        title: Text(
                          item.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: item.isChecked
                                ? Colors.grey.shade500
                                : kCharcoal,
                            decoration: item.isChecked
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        subtitle: item.quantity != '1'
                            ? Text(
                                'Qty: ${item.quantity}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              )
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => _removeFromList(item.id),
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
