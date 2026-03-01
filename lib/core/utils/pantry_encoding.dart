import 'dart:convert';

/// Encodes pantry ingredient maps to JSON strings (for background isolate).
/// Used by [MainNavigation] (or a future PantryService) for debounced save.
List<String> encodeIngredientsInBackground(
  List<Map<String, dynamic>> ingredientsData,
) {
  return ingredientsData.map((data) => jsonEncode(data)).toList();
}
