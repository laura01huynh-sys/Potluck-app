# Navigation

**Intended:** `MainNavigation` (the hub with bottom nav and tab state) should live here as `main_navigation.dart`.

**Current:** `MainNavigation` and `_MainNavigationState` remain in `lib/main.dart` because:

- They depend on **private** state: `_RecipeFeedScreenState._fetchedRecipesCache` and `_RecipeFeedScreenState._userRecipes`, which are used in `_loadUserProfile` / `_saveUserProfile` and elsewhere in main.
- Moving the widget here would require either:
  1. Making that state public and importing `main.dart` from this file (circular import), or  
  2. Extracting recipe (and optionally pantry) state into a **service or provider** (e.g. `RecipeDataCache`, `PantryService` / `IngredientProvider`) that both main and this navigation file use.

**Recommendation:** Introduce a shared cache/service for recipe data and pantry ingredients, then move `MainNavigation` to `lib/navigation/main_navigation.dart` and keep the screen file focused on app bootstrap and routing.
