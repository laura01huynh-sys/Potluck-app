class RecipeDataConstants {
  /// Maps a lifestyle to a list of keywords that should be BLOCKED.
  static const Map<String, List<String>> lifestyleRules = {
    'vegetarian': [
      'Meat',
      'Poultry',
      'Seafood',
      'Bacon',
      'Steak',
      'Chicken',
      'Beef',
      'Lamb',
    ],
    'vegan': [
      'Meat',
      'Poultry',
      'Seafood',
      'Dairy',
      'Eggs',
      'Honey',
      'Milk',
      'Cheese',
      'Butter',
    ],
    'keto': [
      'Grains',
      'Sugar',
      'Fruit',
      'Rice',
      'Pasta',
      'Potatoes',
      'Bread',
    ],
    'paleo': [
      'Grains',
      'Legumes',
      'Dairy',
      'Processed Sugar',
    ],
    'gluten-free': [
      'Wheat',
      'Barley',
      'Rye',
      'Flour',
      'Bread',
      'Pasta',
    ],
    'dairy-free': [
      'Milk',
      'Cheese',
      'Butter',
      'Cream',
      'Yogurt',
    ],
    'pescatarian': ['Meat', 'Poultry'],
    'kosher': [], // Handled separately (dairy+meat combo, pork, shellfish)
    'high-protein': [], // Ranking only, not exclusion
    'low-sodium': [], // Ranking only, not exclusion
    'halal': [],
  };

  /// Words that, if found near a blocked keyword, make the ingredient safe again.
  static const List<String> safetyNegators = [
    'free',
    'alternative',
    'substitute',
    'non',
    'plant-based',
    'vegan',
    'dairy-free',
  ];

  /// Default ingredient classifications for quick-select (allergies / avoidances).
  static const Map<String, List<String>> defaultIngredientClassification = {
    'allergy_risk': [
      'Peanuts',
      'Tree Nuts',
      'Shellfish',
      'Fish',
      'Soy',
      'Dairy',
      'Eggs',
      'Wheat',
      'Sesame',
    ],
    'common_avoidance': [
      'Cilantro',
      'Mushrooms',
      'Olives',
      'Eggplant',
      'Blue Cheese',
      'Mayonnaise',
      'Onions',
    ],
  };
}

