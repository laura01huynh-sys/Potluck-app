# Potluck - AI Coding Agent Instructions

## Project Overview
**Potluck** is a Flutter mobile app that combines pantry management with intelligent recipe recommendations. The core value: help users find recipes they can cook right now using what they already have, respecting dietary restrictions and preferences.

### Key Architecture Components
- **Single-file monolith**: All code in [lib/main.dart](../lib/main.dart) (~7400 lines)
- **Data persistence**: SharedPreferences stores user profile (allergies, avoided ingredients, saved recipes, lifestyle choices, custom restrictions)
- **Central state management**: `MainNavigation` widget maintains shared ingredient list and user profile; child screens update via callbacks
- **Luxury organic design system**: Custom color palette (kBoneCreame, kDeepForestGreen, kMutedGold) with Material3 theming

## Core Data Models

### User Profile
`UserProfile` contains:
- `allergies` / `avoided` / `selectedLifestyles` - Dietary restrictions
- `customLifestyles` - User-created rules with ingredient blocklists
- `savedRecipeIds` - Bookmarked recipes
- Metrics: `recipesCookedCount`, `estimatedMoneySaved`

Persisted as individual SharedPreferences keys with JSON serialization for complex objects.

### Ingredient
Tracks pantry contents with three unit types:
- **Volume** (0.0-1.0): bottles, containers
- **Count** (int): discrete units
- **Weight** (int): grams

Fields: `id`, `name`, `category` (Produce/Protein/Dairy/Pantry/Staples), `unitType`, `amount`, `baseUnit`, plus flags (`isAllergy`, `isAvoided`, `isPriority`).

### Recipe
Contains ingredients list with optional `ingredientTags` Map (e.g., `{'Chicken': ['Meat', 'Protein']}`). Used for dietary filtering. Includes `mealTypes` (breakfast/lunch/dinner/etc), `proteinGrams` for ranking, `rating`, `cookTimeMinutes`.

## Critical Features & Patterns

### 1. **Tiered Recipe Filtering** (FilterService)
Tier 1 (Allergies) → Tier 2 (Lifestyles) → Tier 3 (Avoided + Substitutes)
- **Allergies**: Total exclusion via `hasAllergyConflict()`
- **Lifestyles**: Leverage predefined maps (`lifestyleRules`, `defaultIngredientClassification`)
- **Special cases**: Kosher (dairy+meat combo), custom lifestyles with user-defined blocklists
- **Result**: `filterRecipes()` returns safe subset; `getAvoidedIngredientsWithSubstitutes()` provides warnings with substitution suggestions

### 2. **Pantry-to-Recipe Matching** ("Potluck" feature)
Functions in FilterService calculate readiness:
- `calculatePantryMatchPercentage()` - % of recipe ingredients in pantry (≥0)
- `getMissingIngredients()` / `getMissingIngredientsCount()` - What's needed
- `isReadyToCook()` - True if 100% match (all ingredients in stock)
- `getPantryMatchBadge()` - Visual indicator (✅, +1, +2, +3)

Used by RecipeFeedScreen to prioritize recipes user can immediately cook.

### 3. **Screen Architecture** (6 main screens)
1. **PantryScreen** - Add/edit/delete ingredients, categorized display
2. **RecipeFeedScreen** - Filter & recommend recipes (uses FilterService, shows Potluck badges)
3. **RecipeDetailPage** - Full recipe view, save recipes, warnings for allergies/avoided
4. **ProfileScreen** - Dietary preferences, lifestyle selection, statistics
5. **DietaryHubScreen** - Detailed dietary customization (allergies, avoided, custom lifestyles)
6. **HubScreen / ShoppingListScreen** - Planned features (partially implemented)

Data flows via callbacks: e.g., `onIngredientsUpdated`, `onProfileUpdated` → MainNavigation → `_saveUserProfile()`.

### 4. **Persistence Pattern**
SharedPreferences keys:
- `saved_recipe_ids`, `allergies`, `avoided`, `lifestyles`, `custom_restrictions`
- `custom_lifestyles` - List of JSON strings
- `active_custom_lifestyles` - Set of IDs

Load on app init via `_loadUserProfile()`; save on every profile/ingredient update.

## Development Workflow

### Building & Testing
```bash
flutter pub get              # Install dependencies
flutter run                  # Run on connected device/simulator
flutter test                 # Widget tests (test/widget_test.dart)
```

### Key Dependencies
- `google_fonts` - Typography (Lora for headings, Inter for body)
- `image_picker` - Photo capture for pantry scanning
- `shared_preferences` - Local persistence
- `material.dart` - Material Design components

### Code Style Conventions
- **String extension**: `'hello'.capitalize()` returns `'Hello'`
- **Enums with displayName**: e.g., `IngredientCategory.produce.displayName` → 'Produce'
- **Color constants**: `kBoneCreame`, `kDeepForestGreen` etc. (defined at file top)
- **Monolithic file**: When adding new features, add models after existing models, screens at the end

## Common Tasks

### Add New Dietary Restriction
1. Add entry to `lifestyleRules` Map in FilterService (ingredient exclusions)
2. Update `UserProfile.selectedLifestyles` documentation
3. Add UI toggle in DietaryHubScreen under lifestyle selection

### Add Recipe Feature
1. Define Recipe fields (add to Recipe model)
2. Update FilterService logic if filtering behavior changes
3. Display in RecipeDetailPage and RecipeFeedScreen

### Debug Pantry Matching
- Check `calculatePantryMatchPercentage()` uses lowercase comparison
- Verify `Ingredient.amount` is correct type (double for volume, int for count/weight)
- Use `getPantryMatchBadge()` to inspect missing count logic

## Notes for AI Agents
- **Monolithic structure**: No modular separation; refactoring into multiple files would be major change
- **SharedPreferences sync**: No explicit sync call needed on iOS; understand batch updates best practice
- **Callback hell**: Deep nesting of onChanged callbacks; consider refactoring to Provider/Riverpod if state grows
- **String matching**: Ingredient name comparisons are case-sensitive unless explicitly `.toLowerCase()`
