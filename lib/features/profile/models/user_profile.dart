class CustomLifestyle {
  final String id;
  final String name;
  final List<String> blockList; // Ingredients to exclude

  CustomLifestyle({
    required this.id,
    required this.name,
    required this.blockList,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'blockList': blockList,
      };

  factory CustomLifestyle.fromJson(Map<String, dynamic> json) {
    return CustomLifestyle(
      id: json['id'],
      name: json['name'],
      blockList: List<String>.from(json['blockList'] ?? []),
    );
  }
}

class UserProfile {
  final String userId;
  final String userName;
  final String? avatarUrl;
  final Set<String> allergies; // Ingredient names with allergy flag
  final Set<String> avoided; // Ingredient names with avoid flag
  final List<String> savedRecipeIds; // IDs of saved recipes
  final List<String> cookedRecipeIds; // IDs of cooked recipes
  final int recipesCookedCount;
  final double estimatedMoneySaved;
  final Set<String>
      selectedLifestyles; // vegan, vegetarian, keto, paleo, gluten-free, pescatarian, kosher, high-protein
  final List<String> customRestrictions; // User-defined custom restrictions
  final List<CustomLifestyle> customLifestyles; // User-created lifestyle rules
  final Set<String> activeCustomLifestyles; // IDs of active custom lifestyles

  UserProfile({
    required this.userId,
    required this.userName,
    this.avatarUrl,
    Set<String>? allergies,
    Set<String>? avoided,
    List<String>? savedRecipeIds,
    List<String>? cookedRecipeIds,
    this.recipesCookedCount = 0,
    this.estimatedMoneySaved = 0.0,
    Set<String>? selectedLifestyles,
    List<String>? customRestrictions,
    List<CustomLifestyle>? customLifestyles,
    Set<String>? activeCustomLifestyles,
  })  : allergies = allergies ?? {},
        avoided = avoided ?? {},
        savedRecipeIds = savedRecipeIds ?? [],
        cookedRecipeIds = cookedRecipeIds ?? [],
        selectedLifestyles = selectedLifestyles ?? {},
        customRestrictions = customRestrictions ?? [],
        customLifestyles = customLifestyles ?? [],
        activeCustomLifestyles = activeCustomLifestyles ?? {};

  UserProfile copyWith({
    String? userId,
    String? userName,
    String? avatarUrl,
    Set<String>? allergies,
    Set<String>? avoided,
    List<String>? savedRecipeIds,
    List<String>? cookedRecipeIds,
    int? recipesCookedCount,
    double? estimatedMoneySaved,
    Set<String>? selectedLifestyles,
    List<String>? customRestrictions,
    List<CustomLifestyle>? customLifestyles,
    Set<String>? activeCustomLifestyles,
  }) {
    return UserProfile(
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      allergies: allergies ?? this.allergies,
      avoided: avoided ?? this.avoided,
      savedRecipeIds: savedRecipeIds ?? this.savedRecipeIds,
      cookedRecipeIds: cookedRecipeIds ?? this.cookedRecipeIds,
      recipesCookedCount: recipesCookedCount ?? this.recipesCookedCount,
      estimatedMoneySaved: estimatedMoneySaved ?? this.estimatedMoneySaved,
      selectedLifestyles: selectedLifestyles ?? this.selectedLifestyles,
      customRestrictions: customRestrictions ?? this.customRestrictions,
      customLifestyles: customLifestyles ?? this.customLifestyles,
      activeCustomLifestyles:
          activeCustomLifestyles ?? this.activeCustomLifestyles,
    );
  }
}
