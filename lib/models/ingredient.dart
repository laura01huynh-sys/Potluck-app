import 'dart:io';
import 'package:image_picker/image_picker.dart';

class FridgeImage {
  final String id;
  final File imageFile;
  final DateTime timestamp;
  final ImageSource source;
  final List<String> ingredients;

  FridgeImage({
    required this.id,
    required this.imageFile,
    required this.timestamp,
    required this.source,
    this.ingredients = const [],
  });

  FridgeImage copyWith({
    String? id,
    File? imageFile,
    DateTime? timestamp,
    ImageSource? source,
    List<String>? ingredients,
  }) => FridgeImage(
    id: id ?? this.id,
    imageFile: imageFile ?? this.imageFile,
    timestamp: timestamp ?? this.timestamp,
    source: source ?? this.source,
    ingredients: ingredients ?? this.ingredients,
  );
}

enum IngredientCategory {
  proteins('Proteins'),
  produce('Produce'),
  dairyRefrigerated('Dairy & Refrigerated'),
  cannedGoods('Canned Goods'),
  snacksExtras('Snacks & Extras'),
  condimentsSauces('Condiments & Sauces'),
  grainsLegumes('Grains & Legumes'),
  spicesSeasonings('Spices & Seasonings'),
  baking('Baking'),
  frozen('Frozen');

  final String displayName;
  const IngredientCategory(this.displayName);

  /// Canonical display order for pantry/category UIs.
  static List<IngredientCategory> get displayOrder => const [
        IngredientCategory.produce,
        IngredientCategory.proteins,
        IngredientCategory.dairyRefrigerated,
        IngredientCategory.grainsLegumes,
        IngredientCategory.cannedGoods,
        IngredientCategory.frozen,
        IngredientCategory.condimentsSauces,
        IngredientCategory.spicesSeasonings,
        IngredientCategory.baking,
        IngredientCategory.snacksExtras,
      ];
}

enum UnitType {
  volume,
  count,
  weight;

  String get label => switch (this) {
        UnitType.volume => 'Volume',
        UnitType.count => 'Count',
        UnitType.weight => 'Weight',
      };
}

class Ingredient {
  final String id;
  final String name;
  final String? imageId;
  final IngredientCategory category;
  final UnitType unitType;
  final dynamic amount;
  final String baseUnit;
  final bool isSelected;
  final bool isPriority;
  final bool isAvoided;
  final bool isAllergy;

  Ingredient({
    required this.id,
    required this.name,
    this.imageId,
    required this.category,
    required this.unitType,
    required this.amount,
    required this.baseUnit,
    this.isSelected = false,
    this.isPriority = false,
    this.isAvoided = false,
    this.isAllergy = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imageId': imageId,
        'category': category.name,
        'unitType': unitType.name,
        'amount': amount,
        'baseUnit': baseUnit,
        'isSelected': isSelected,
        'isPriority': isPriority,
        'isAvoided': isAvoided,
        'isAllergy': isAllergy,
      };

  factory Ingredient.fromJson(Map<String, dynamic> data) {
    final unitType = UnitType.values.firstWhere(
      (u) => u.name == data['unitType'],
      orElse: () => UnitType.count,
    );
    dynamic amount;
    if (unitType == UnitType.volume) {
      amount = double.parse(data['amount'].toString());
    } else {
      final parsed = double.tryParse(data['amount'].toString()) ?? 0.0;
      amount = parsed == parsed.roundToDouble() ? parsed.toInt() : parsed;
    }
    final category = IngredientCategory.values.firstWhere(
      (c) => c.name == data['category'],
      orElse: () => IngredientCategory.produce,
    );
    return Ingredient(
      id: data['id'] as String,
      name: data['name'] as String,
      imageId: data['imageId'] as String?,
      category: category,
      unitType: unitType,
      amount: amount,
      baseUnit: data['baseUnit'] as String,
      isSelected: data['isSelected'] as bool? ?? false,
      isPriority: data['isPriority'] as bool? ?? false,
      isAvoided: data['isAvoided'] as bool? ?? false,
      isAllergy: data['isAllergy'] as bool? ?? false,
    );
  }

  bool get needsPurchase =>
      amount == 0 || (amount is double && (amount as double) < 0.01);

  Ingredient copyWith({
    String? id,
    String? name,
    String? imageId,
    IngredientCategory? category,
    UnitType? unitType,
    dynamic amount,
    String? baseUnit,
    bool? isSelected,
    bool? isPriority,
    bool? isAvoided,
    bool? isAllergy,
  }) =>
      Ingredient(
        id: id ?? this.id,
        name: name ?? this.name,
        imageId: imageId ?? this.imageId,
        category: category ?? this.category,
        unitType: unitType ?? this.unitType,
        amount: amount ?? this.amount,
        baseUnit: baseUnit ?? this.baseUnit,
        isSelected: isSelected ?? this.isSelected,
        isPriority: isPriority ?? this.isPriority,
        isAvoided: isAvoided ?? this.isAvoided,
        isAllergy: isAllergy ?? this.isAllergy,
      );
}