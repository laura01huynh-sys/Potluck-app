import 'package:shared_preferences/shared_preferences.dart';

import 'gemini_recipe_service.dart';

/// One-off housekeeping tasks (cache clears, version migrations). Run at app
/// startup so navigation/widgets don't own this logic.
class MaintenanceService {
  static const String _versionKey = 'recipe_data_cache_version';
  static const int _currentVersion = 4; // bump to force a re-clear when needed

  /// Runs startup maintenance (e.g. one-time recipe cache clear by version).
  /// Call once after app init (e.g. from MainNavigation.initState).
  static Future<void> runStartupTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedVersion = prefs.getInt(_versionKey) ?? 0;
      if (storedVersion < _currentVersion) {
        await RecipeDataService.clearAllCaches();
        await prefs.setInt(_versionKey, _currentVersion);
      }
    } catch (_) {}
  }
}
