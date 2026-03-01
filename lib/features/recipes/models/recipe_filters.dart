/// Static filter option lists for the Advanced Search UI.
/// Used by [AdvancedSearchScreen] to build diet, allergy, cuisine, and other chips.
class RecipeFilterOptions {
  RecipeFilterOptions._();

  static const List<String> diets = [
    'Vegan',
    'Vegetarian',
    'Ketogenic',
    'Paleo',
    'Pescatarian',
    'Gluten-Free',
    'Whole30',
  ];

  static const List<String> intolerances = [
    'Dairy',
    'Egg',
    'Gluten',
    'Peanut',
    'Seafood',
    'Sesame',
    'Shellfish',
    'Soy',
    'Sulfite',
    'Tree Nut',
    'Wheat',
  ];

  static const List<String> cuisines = [
    'Italian',
    'Mexican',
    'Asian',
    'Indian',
    'Mediterranean',
    'French',
    'Greek',
    'Spanish',
  ];

  static const List<String> mealTypes = [
    'Main Course',
    'Side Dish',
    'Dessert',
    'Appetizer',
    'Salad',
    'Breakfast',
    'Soup',
    'Beverage',
    'Fingerfood',
  ];

  static const List<String> prepTimes = [
    'Under 15 mins',
    'Under 30 mins',
    'Under 45 mins',
    'Slow Cook (1hr+)',
  ];

  static const List<String> cookingMethods = [
    'Air Fryer',
    'Slow Cooker',
    'One-Pot Meals',
    'Oven-Baked',
    'No-Cook',
  ];

  static const List<String> macroGoals = [
    'High Protein (20g+)',
    'Low Carb (20g-)',
    'Low Calorie (400-)',
    'Low Fat',
  ];
}
