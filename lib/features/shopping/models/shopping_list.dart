/// Models for shopping lists and items (persisted via SharedPreferences).

class ShoppingList {
  final String id;
  String name;
  List<ShoppingItem> items;

  ShoppingList({
    required this.id,
    required this.name,
    List<ShoppingItem>? items,
  }) : items = items ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory ShoppingList.fromJson(Map<String, dynamic> json) {
    return ShoppingList(
      id: json['id'],
      name: json['name'],
      items:
          (json['items'] as List<dynamic>?)
              ?.map((i) => ShoppingItem.fromJson(i))
              .toList() ??
          [],
    );
  }
}

class ShoppingItem {
  final String id;
  final String name;
  String quantity;
  final String unit;
  final bool isFromRestock;
  bool isChecked;

  ShoppingItem({
    required this.id,
    required this.name,
    this.quantity = '1',
    required this.unit,
    required this.isFromRestock,
    this.isChecked = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantity': quantity,
        'unit': unit,
        'isFromRestock': isFromRestock,
        'isChecked': isChecked,
      };

  factory ShoppingItem.fromJson(Map<String, dynamic> json) {
    return ShoppingItem(
      id: json['id'],
      name: json['name'],
      quantity: json['quantity'] ?? '1',
      unit: json['unit'] ?? 'ea',
      isFromRestock: json['isFromRestock'] ?? false,
      isChecked: json['isChecked'] ?? false,
    );
  }
}
