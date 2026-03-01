import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../features/profile/models/user_profile.dart';

/// Result of loading profile from storage. Caller merges [savedRecipeData] and
/// [cookedRecipeData] into recipe caches (e.g. RecipeFeedScreenState).
class ProfileLoadResult {
  final UserProfile profile;
  final Map<String, List<String>> authorFollowers;
  final List<Map<String, dynamic>> savedRecipeData;
  final List<Map<String, dynamic>> cookedRecipeData;

  const ProfileLoadResult({
    required this.profile,
    required this.authorFollowers,
    required this.savedRecipeData,
    required this.cookedRecipeData,
  });
}

/// Profile and recipe-data persistence. Use with [allRecipeMaps] from
/// RecipeFeedScreenState when saving.
class ProfileService {
  /// Loads profile, author followers, and persisted recipe data from prefs.
  /// Merge [savedRecipeData] and [cookedRecipeData] into your recipe caches.
  static Future<ProfileLoadResult> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();

    final savedRecipeIds = prefs.getStringList('saved_recipe_ids') ?? [];
    final cookedRecipeIds = prefs.getStringList('cooked_recipe_ids') ?? [];
    final savedRecipeDataJson = prefs.getStringList('saved_recipe_data') ?? [];
    final cookedRecipeDataJson =
        prefs.getStringList('cooked_recipe_data') ?? [];

    final savedRecipeData = savedRecipeDataJson
        .map((json) => jsonDecode(json) as Map<String, dynamic>)
        .toList();
    final cookedRecipeData = cookedRecipeDataJson
        .map((json) => jsonDecode(json) as Map<String, dynamic>)
        .toList();

    final allergies = prefs.getStringList('allergies') ?? [];
    final avoided = prefs.getStringList('avoided') ?? [];
    final lifestyles = prefs.getStringList('lifestyles') ?? [];
    final customRestrictions = prefs.getStringList('custom_restrictions') ?? [];
    final customLifestylesJson = prefs.getStringList('custom_lifestyles') ?? [];
    final customLifestyles = customLifestylesJson
        .map((json) => CustomLifestyle.fromJson(jsonDecode(json)))
        .toList();
    final activeCustomLifestyles =
        prefs.getStringList('active_custom_lifestyles') ?? [];

    Map<String, List<String>> authorFollowers = {};
    try {
      final followersJson = prefs.getString('author_followers');
      if (followersJson != null) {
        final decoded = jsonDecode(followersJson) as Map<String, dynamic>;
        authorFollowers = decoded.map(
          (k, v) => MapEntry(
            k as String,
            List<String>.from((v as List).map((e) => e.toString())),
          ),
        );
      }
    } catch (_) {}

    const defaultUserId = '1';
    const defaultUserName = 'Laura Huynh';
    final profile = UserProfile(
      userId: defaultUserId,
      userName: defaultUserName,
      savedRecipeIds: savedRecipeIds,
      cookedRecipeIds: cookedRecipeIds,
      allergies: Set<String>.from(allergies),
      avoided: Set<String>.from(avoided),
      selectedLifestyles: Set<String>.from(lifestyles),
      customRestrictions: customRestrictions,
      customLifestyles: customLifestyles,
      activeCustomLifestyles: Set<String>.from(activeCustomLifestyles),
    );

    return ProfileLoadResult(
      profile: profile,
      authorFollowers: authorFollowers,
      savedRecipeData: savedRecipeData,
      cookedRecipeData: cookedRecipeData,
    );
  }

  /// Saves [profile], [authorFollowers], and recipe data. [allRecipeMaps]
  /// should be the combined user + fetched recipe maps from RecipeFeedScreenState.
  static Future<void> saveProfile(
    UserProfile profile,
    Map<String, List<String>> authorFollowers,
    List<Map<String, dynamic>> allRecipeMaps,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('saved_recipe_ids', profile.savedRecipeIds);
    await prefs.setStringList('cooked_recipe_ids', profile.cookedRecipeIds);

    final existingSavedJson = prefs.getStringList('saved_recipe_data') ?? [];
    final existingCookedJson = prefs.getStringList('cooked_recipe_data') ?? [];
    final existingSavedMap = _buildIdToJsonMap(existingSavedJson);
    final existingCookedMap = _buildIdToJsonMap(existingCookedJson);

    final savedRecipeData = <String>[];
    for (final id in profile.savedRecipeIds) {
      final recipe = allRecipeMaps.firstWhere(
        (r) => r['id'] == id,
        orElse: () => <String, dynamic>{},
      );
      if (recipe.isNotEmpty) {
        savedRecipeData.add(jsonEncode(Map<String, dynamic>.from(recipe)));
      } else if (existingSavedMap.containsKey(id)) {
        savedRecipeData.add(existingSavedMap[id]!);
      }
    }

    final cookedRecipeData = <String>[];
    for (final id in profile.cookedRecipeIds) {
      final recipe = allRecipeMaps.firstWhere(
        (r) => r['id'] == id,
        orElse: () => <String, dynamic>{},
      );
      if (recipe.isNotEmpty) {
        cookedRecipeData.add(jsonEncode(Map<String, dynamic>.from(recipe)));
      } else if (existingCookedMap.containsKey(id)) {
        cookedRecipeData.add(existingCookedMap[id]!);
      }
    }

    await prefs.setStringList('saved_recipe_data', savedRecipeData);
    await prefs.setStringList('cooked_recipe_data', cookedRecipeData);
    await prefs.setStringList('allergies', profile.allergies.toList());
    await prefs.setStringList('avoided', profile.avoided.toList());
    await prefs.setStringList(
      'lifestyles',
      profile.selectedLifestyles.toList(),
    );
    await prefs.setStringList(
      'custom_restrictions',
      profile.customRestrictions,
    );
    final customLifestylesJson = profile.customLifestyles
        .map((cl) => jsonEncode(cl.toJson()))
        .toList();
    await prefs.setStringList('custom_lifestyles', customLifestylesJson);
    await prefs.setStringList(
      'active_custom_lifestyles',
      profile.activeCustomLifestyles.toList(),
    );
    await prefs.setString('author_followers', jsonEncode(authorFollowers));
  }

  static Map<String, String> _buildIdToJsonMap(List<String> jsonList) {
    final map = <String, String>{};
    for (final raw in jsonList) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final id = decoded['id']?.toString();
        if (id != null && id.isNotEmpty) map[id] = raw;
      } catch (_) {}
    }
    return map;
  }

  /// Load author followers only.
  static Future<Map<String, List<String>>> loadAuthorFollowers() async {
    final result = await loadProfile();
    return result.authorFollowers;
  }

  /// Save author followers only. Use after updating the map locally.
  static Future<void> saveAuthorFollowers(
    Map<String, List<String>> authorFollowers,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('author_followers', jsonEncode(authorFollowers));
  }
}
