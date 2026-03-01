import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/pantry_encoding.dart';
import '../models/ingredient.dart';

/// Pantry persistence and helpers. Use from anywhere (e.g. Provider) without
/// passing callbacks up to MainNavigation.
class PantryService {
  static const _pantryKey = 'pantry_ingredients';
  static const _dismissedRestockKey = 'dismissed_restock_ids';

  /// Loads pantry ingredients from SharedPreferences using [Ingredient.fromJson].
  static Future<List<Ingredient>> loadPantryIngredients() async {
    final prefs = await SharedPreferences.getInstance();
    final ingredientsJson = prefs.getStringList(_pantryKey) ?? [];
    return ingredientsJson.map((json) {
      try {
        final data = jsonDecode(json) as Map<String, dynamic>;
        return Ingredient.fromJson(data);
      } catch (e) {
        rethrow;
      }
    }).toList();
  }

  /// Saves [ingredients] to SharedPreferences. JSON encoding runs on a
  /// background isolate via [compute].
  static Future<void> savePantryIngredients(List<Ingredient> ingredients) async {
    try {
      final ingredientsData = ingredients.map((ing) => ing.toJson()).toList();
      final ingredientsJson = await compute(
        encodeIngredientsInBackground,
        ingredientsData,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_pantryKey, ingredientsJson);
    } catch (e) {
      debugPrint('PantryService.savePantryIngredients: $e');
    }
  }

  /// Loads the set of dismissed restock item IDs.
  static Future<Set<String>> loadDismissedRestockIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_dismissedRestockKey) ?? [];
    return Set<String>.from(list);
  }

  /// Saves the set of dismissed restock item IDs.
  static Future<void> saveDismissedRestockIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_dismissedRestockKey, ids.toList());
  }

  /// Merges [newIngredients] into [current] by name + baseUnit (adds amounts if
  /// same, otherwise appends). Returns a new list; does not mutate [current].
  static List<Ingredient> mergeConfirmedIngredients(
    List<Ingredient> current,
    List<Ingredient> newIngredients,
  ) {
    final result = List<Ingredient>.from(current);
    for (final newIng in newIngredients) {
      final i = result.indexWhere(
        (ing) => ing.name == newIng.name && ing.baseUnit == newIng.baseUnit,
      );
      if (i != -1) {
        result[i] = result[i].copyWith(
          amount: (result[i].amount as num) + (newIng.amount as num),
        );
      } else {
        result.add(newIng);
      }
    }
    return result;
  }

  /// Returns a new list with the ingredient [ingredientId] restocked to a
  /// default amount by unit type. Does not mutate [current].
  static List<Ingredient> restockIngredient(
    List<Ingredient> current,
    String ingredientId,
  ) {
    final index = current.indexWhere((ing) => ing.id == ingredientId);
    if (index == -1) return current;
    final ing = current[index];
    final newAmount = switch (ing.unitType) {
      UnitType.volume => 1.0,
      UnitType.count => 5,
      UnitType.weight => 500,
    };
    final next = List<Ingredient>.from(current);
    next[index] = ing.copyWith(amount: newAmount);
    return next;
  }
}
