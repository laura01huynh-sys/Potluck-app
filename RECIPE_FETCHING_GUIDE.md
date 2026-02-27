# Recipe Fetching System - Complete Integration Guide

## Overview
The Potluck app now has a **dual-layer caching system** for recipe fetching that prevents API limit exhaustion during development while still supporting manual refreshes.

---

## Architecture

### Layer 1: RecipeFeedScreen Cache (`lib/main.dart`)
**Purpose:** High-level app state caching with significant change detection

**Key Methods:**
- `_getPantryList()` - Returns sorted list of active ingredient names (amount > 0)
- `_hasSignificantChange()` - Detects added/removed items (ignores quantity tweaks)
- `_getCacheKey()` - Creates stable cache key from ingredient names
- `_isCacheValid()` - Checks if cached data is < 30 minutes old
- `_loadFromCache()` - Retrieves cached recipes from SharedPreferences
- `_saveToCache()` - Stores recipes with timestamp
- `_fetchRemoteRecipes({bool forceRefresh = false})` - Main orchestrator

**Cache Strategy:**
1. **User opens app** → Check cache
2. **Cache exists & fresh** → Use it (no API call)
3. **Cache stale/missing** → Fetch from network
4. **User adds/removes ingredient** → Detect significant change, refetch
5. **User taps refresh button** → Force fresh API call (bypass cache)
6. **Network error** → Fall back to stale cache if available

**Debug Logs:** Look for `DEBUG CACHE:` prefix in console

---

### Layer 2: PotluckRecipeService (`lib/services/potluck_recipe_service.dart`)
**Purpose:** Recipe service layer with ingredient-based caching

**Key Methods:**
- `_pantryIngredientsToString(List<Ingredient>)` - Converts active ingredients to `"flour,butter,eggs"`
- `_getCacheKey(String ingredientString)` - Creates ingredient-based cache key
- `_isCacheValid(String cacheKey)` - Checks service-level cache validity
- `_loadFromCache()` / `_saveToCache()` - Service-level persistence
- `getPotluckRecipes(List<String> ingredients, {forceRefresh = false})` - Fetches recipes with caching
- `fetchRecipesFromPantry(List<Ingredient>, forceRefresh)` - Wrapper accepting Ingredient objects

**Cache Strategy:**
- Cache key format: `spoonacular_recipes_flour_butter_eggs`
- TTL: 30 minutes (matched with RecipeFeedScreen)
- On network error: Returns stale cache if available
- On success: Enriches recipes with full information and caches result

**Debug Logs:** Look for `DEBUG SERVICE:` prefix in console

---

### Layer 3: ApiService (`lib/services/api_service.dart`)
**Purpose:** Low-level Spoonacular API client (no caching)

**Key Details:**
- ✅ Already includes `ranking=1` parameter in findRecipesByIngredients URL
- ✅ Already logs full URL: `DEBUG API: Full URL: $uri`
- Uses two-step fetch:
  1. `findRecipesByIngredients` - Quick search by available ingredients
  2. `fetchRecipeInformationBulk` - Enriches with nutrition, ratings, etc.

---

## Data Flow with Example

### Scenario: User has pantry items [Flour, Butter, Eggs]

```
┌─────────────────────────────────────────────────────────────┐
│                    RecipeFeedScreen                         │
│  1. _fetchRemoteRecipes(forceRefresh: false)               │
│  2. _getPantryList() → ["Butter", "Eggs", "Flour"]         │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
        ┌──────────────────────────────────┐
        │   Check Local Cache (Tier 1)     │
        │   Key: spoonacular_cache_<hash>  │
        │   Age: 5 minutes ✅ VALID        │
        └──────────────────┬───────────────┘
                           │
                           ▼ (Cache hit - use it)
                    ┌──────────────┐
                    │ Return cached│
                    │ recipes list │
                    └──────────────┘
```

### Scenario: User manually taps refresh button

```
┌─────────────────────────────────────────────────────────────┐
│                    RecipeFeedScreen                         │
│  1. User taps 🔄 refresh button                            │
│  2. _fetchRemoteRecipes(forceRefresh: true)                │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
        ┌──────────────────────────────────┐
        │   Skip Local Cache (forced)      │
        │   Go straight to network         │
        └──────────────────┬───────────────┘
                           │
                           ▼
        ┌──────────────────────────────────┐
        │   PotluckRecipeService Layer     │
        │   Check Service Cache            │
        │   forceRefresh: true             │
        │   Skip cache, fetch network      │
        └──────────────────┬───────────────┘
                           │
                           ▼
        ┌──────────────────────────────────┐
        │   ApiService Layer               │
        │   Call Spoonacular API           │
        │   DEBUG API: Full URL: ... ◀─────┼─ COPY THIS FOR TESTING
        │   GET /recipes/findByIngredients │
        │   ?apiKey=XXX                    │
        │   &ingredients=butter,eggs,flour│
        │   &number=10                     │
        │   &ranking=1 ◀──────────────────┼─ PANTRY PRIORITIZATION
        └──────────────────┬───────────────┘
                           │
                           ▼
        ┌──────────────────────────────────┐
        │   ApiService enriches with full  │
        │   recipe information (nutrition, │
        │   ratings, cook times, etc.)     │
        │   Caches result at service level │
        │   Returns to RecipeFeedScreen    │
        └──────────────────┬───────────────┘
                           │
                           ▼
        ┌──────────────────────────────────┐
        │   RecipeFeedScreen caches at app │
        │   level for next session         │
        │   Returns recipes to build()     │
        │   Displays in MasonryGridView    │
        └──────────────────────────────────┘
```

---

## Debug Console Output Reference

### When cache is used:
```
DEBUG CACHE: Cache age: 5 minutes, Valid: true
DEBUG CACHE: Loaded 12 recipes from cache
```

### When network fetch happens:
```
DEBUG: Pantry ingredients for Spoonacular: [Butter, Eggs, Flour]
DEBUG: Fetching recipes from network...
DEBUG API: Full URL: https://api.spoonacular.com/recipes/findByIngredients?apiKey=XXX&ingredients=butter,eggs,flour&number=10&ranking=1
DEBUG: Received 10 recipes from Spoonacular
DEBUG: First recipe: Omelette with Herbs
DEBUG CACHE: Cached 10 recipes
```

### When pantry changes significantly:
```
DEBUG: Significant pantry change detected! Refetching recipes...
```

---

## Testing the URL in Browser

To verify Spoonacular is returning data:

1. **Run the app:**
   ```bash
   flutter run
   ```

2. **Add ingredients to pantry** (e.g., flour, butter, eggs)

3. **Navigate to Potluck tab** (recipe feed)

4. **Watch console for:**
   ```
   DEBUG API: Full URL: https://api.spoonacular.com/recipes/findByIngredients?apiKey=...&ingredients=...
   ```

5. **Copy the URL** and test in browser
   - Should return JSON array of recipes
   - Each recipe has: `id`, `title`, `image`, `usedIngredients`, `missedIngredients`

6. **Example response format:**
   ```json
   [
     {
       "id": 1234,
       "title": "Omelette with Herbs",
       "image": "https://...",
       "usedIngredients": [
         { "name": "eggs", "amount": 3, "unit": "whole" },
         { "name": "butter", "amount": 2, "unit": "tablespoons" }
       ],
       "missedIngredients": [
         { "name": "salt", "amount": 1, "unit": "teaspoon" }
       ]
     }
   ]
   ```

---

## Cache File Locations in SharedPreferences

### RecipeFeedScreen cache:
- **Key format:** `spoonacular_cache_<ingredient_hash>`
- **Value:** JSON-serialized list of recipe maps
- **Timestamp key:** `spoonacular_cache_<ingredient_hash>_timestamp`

### PotluckRecipeService cache:
- **Key format:** `spoonacular_recipes_<ingredient_hash>`
- **Value:** JSON-serialized recipes from API
- **Timestamp key:** `spoonacular_recipes_<ingredient_hash>_timestamp`

---

## Common Issues & Solutions

### Issue 1: Recipes not showing up
**Diagnosis:**
- Run app and check console for `DEBUG API: Full URL:` log
- Copy URL and test in browser
- If no URL appears in logs, cache might be returning empty data

**Solution:**
- Check if pantry has active ingredients (amount > 0)
- Try tapping refresh button to force API call
- Clear app cache: Settings > Apps > Potluck > Clear Cache

### Issue 2: API limit hit (too many requests)
**This is why we have dual-layer caching!**
- First restart after hot save: Uses cache (no API call)
- After 30 minutes: Cache expires, fresh API call made
- Manual refresh: Always makes fresh API call (by design)

**Solution:**
- Don't repeatedly tap refresh button during testing
- Use cache: Restart app multiple times without adding ingredients
- Or: Wait 30 minutes between fresh API calls

### Issue 3: Seeing old recipes after adding new ingredients
**Cause:** Quantity changes don't trigger refetch (by design)

**Solution:**
- Tap refresh button manually, OR
- Add/remove an ingredient (not just quantity change)

---

## Code Structure Summary

```
lib/main.dart
├── _RecipeFeedScreenState
│   ├── _getPantryList() - Get active ingredients
│   ├── _hasSignificantChange() - Detect add/remove
│   ├── _getCacheKey() - Generate cache key
│   ├── _isCacheValid() - Check TTL
│   ├── _loadFromCache() - Retrieve cached recipes
│   ├── _saveToCache() - Store with timestamp
│   └── _fetchRemoteRecipes() - Main orchestrator ◀─ ENTRY POINT
│       └── Pass forceRefresh to service
│
lib/services/potluck_recipe_service.dart
├── _pantryIngredientsToString() - Convert List<Ingredient> → string
├── _getCacheKey() - Service-level cache key
├── _isCacheValid() - Service-level TTL check
├── _loadFromCache() - Service-level retrieval
├── _saveToCache() - Service-level storage
├── getPotluckRecipes() - Main fetch with caching ◀─ CALLED BY lib/main.dart
└── fetchRecipesFromPantry() - Convenience wrapper for Ingredient lists
    └── Call getPotluckRecipes()
        └── Call ApiService.findRecipesByIngredients()
            └── Call ApiService.fetchRecipeInformationBulk()
                └── Return enriched recipes

lib/services/api_service.dart
├── findRecipesByIngredients() - Spoonacular search (has ranking=1) ✅
└── fetchRecipeInformationBulk() - Spoonacular enrichment
```

---

## Performance Expectations

| Scenario | Network Call | Time to Display |
|----------|---|---|
| App launch (cache valid) | ❌ No | ~100ms (from cache) |
| Add ingredient (significant change) | ✅ Yes | ~1-2s (API + enrichment) |
| Hot restart (same pantry) | ❌ No | ~100ms (from cache) |
| Tap refresh button | ✅ Yes | ~1-2s (forced API call) |
| After 30 min, same pantry | ✅ Yes | ~1-2s (cache expired) |

---

## Final Verification Checklist

- [ ] App compiles without errors: `flutter analyze` shows no errors
- [ ] Added ingredients appear in pantry
- [ ] Potluck tab shows recipes
- [ ] Console shows `DEBUG API:` and `DEBUG CACHE:` logs
- [ ] Refresh button works (manual API call)
- [ ] Hot restart uses cache (no new API call)
- [ ] URL in browser returns valid JSON
- [ ] Recipes have complete information (images, times, ratings)

---

## Next Steps if Still Seeing Issues

1. **Check that getPotluckRecipes is being called:**
   - Add breakpoint in `potluck_recipe_service.dart` in `getPotluckRecipes()`
   - Should be hit when you navigate to Potluck tab

2. **Verify ingredient string is correct:**
   - Look for `DEBUG SERVICE:` log showing ingredient list
   - Should match pantry items

3. **Test API URL directly:**
   - Copy URL from `DEBUG API: Full URL:` log
   - Paste in browser
   - Should see JSON array of recipes

4. **Check SharedPreferences:**
   - Use flutter DevTools to inspect SharedPreferences
   - Verify cache keys and values are being stored

---

**Last Updated:** After implementing dual-layer caching system
**Status:** ✅ Ready for testing
