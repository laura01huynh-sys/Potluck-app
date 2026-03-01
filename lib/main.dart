// ignore_for_file: deprecated_member_use, library_private_types_in_public_api

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
// Your internal routing/initialization
import 'services/firebase_service.dart';
import 'models/recipe.dart';
import 'models/ingredient.dart';
import 'features/profile/models/user_profile.dart';
import 'models/review.dart';
import 'models/recipe_filter.dart';
import 'widgets/nutrition_summary_bar.dart';
import 'core/dietary.dart';
import 'services/dietary_filter_service.dart';
import 'services/ingredient_match_service.dart';
import 'core/theme.dart';
import 'core/constants.dart';
import 'features/auth/screens/welcome_screen.dart';
import 'features/auth/screens/chef_identity_screen.dart';
import 'services/pantry_service.dart';
import 'services/profile_service.dart';
import 'services/maintenance_service.dart';
import 'features/pantry/screens/add_ingredient_screen.dart';
import 'features/pantry/screens/confirm_scan_screen.dart';
import 'features/pantry/screens/pantry_screen.dart';
import 'features/recipes/screens/advanced_search_screen.dart';
import 'features/profile/screens/hub_screen.dart';
import 'features/profile/screens/profile_screen.dart';
import 'features/profile/screens/dietary_hub_screen.dart';
import 'core/constants/diet_definitions.dart';
import 'features/profile/utils/dialog_utils.dart';
import 'features/profile/widgets/dietary_hub_button.dart';
import 'features/profile/widgets/dietary_restriction_pills.dart';
import 'features/profile/widgets/lifestyle_card.dart';
import 'features/profile/widgets/palate_empty_state.dart';
import 'features/profile/widgets/restriction_chip.dart';
import 'features/profile/widgets/restriction_section.dart';
import 'features/shopping/screens/shopping_list_screen.dart';
import 'features/user/modals/create_lifestyle_modal.dart';
import 'features/user/widgets/lifestyle_chip.dart';

import 'navigation/main_navigation.dart';
import 'navigation/widgets/potluck_nav_bar.dart';
import 'features/recipe/widgets/recipe_card.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(PotluckApp(mainHomeBuilder: () => const MainNavigationHost()));
}

// ================= ROOT APP (entry + auth routing) =================
/// Root widget: MaterialApp and auth-state-based routing (splash, chef identity,
/// welcome, or main app). [mainHomeBuilder] provides the main tab shell.
class PotluckApp extends StatefulWidget {
  const PotluckApp({
    super.key,
    required this.mainHomeBuilder,
  });

  final Widget Function() mainHomeBuilder;

  @override
  State<PotluckApp> createState() => _PotluckAppState();
}

class _PotluckAppState extends State<PotluckApp> {
  bool _isAuthenticated = false;
  bool _needsChefIdentity = false;
  bool _checkingSession = true;
  late final StreamSubscription<User?> _authSub;

  @override
  void initState() {
    super.initState();
    _isAuthenticated = FirebaseService.isSignedIn;
    _checkingSession = false;
    _authSub = FirebaseService.authStateChanges.listen((user) {
      setState(() {
        _isAuthenticated = user != null;
      });
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Potluck',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kBoneCreame,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: ZeroTransitionsBuilder(),
            TargetPlatform.iOS: ZeroTransitionsBuilder(),
          },
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 90, 131, 120),
        ),
        textTheme: AppTextTheme.theme,
        appBarTheme: const AppBarTheme(
          backgroundColor: kBoneCreame,
          foregroundColor: kDeepForestGreen,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: _checkingSession
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _isAuthenticated && _needsChefIdentity
              ? ChefIdentityScreen(
                  onComplete: () {
                    setState(() => _needsChefIdentity = false);
                  },
                )
              : _isAuthenticated
                  ? widget.mainHomeBuilder()
                  : WelcomeScreen(
                      onSignUpSuccess: () {
                        setState(() {
                          _isAuthenticated = true;
                          _needsChefIdentity = true;
                        });
                      },
                      onSignInSuccess: () {
                        setState(() => _isAuthenticated = true);
                      },
                    ),
    );
  }
}

// ================= MAIN NAVIGATION (HUB) =================
/// Stateful host: owns shared state and builds tab content; delegates
/// visual shell to [MainNavigation] in navigation/main_navigation.dart.
class MainNavigationHost extends StatefulWidget {
  const MainNavigationHost({super.key});

  @override
  State<MainNavigationHost> createState() => _MainNavigationHostState();
}

class _MainNavigationHostState extends State<MainNavigationHost> {
  int _currentIndex = 0;
  late List<Ingredient> _sharedIngredients;
  late UserProfile _userProfile;
  late List<CommunityReview> _communityReviews;
  Set<String> _dismissedRestockIds = {};
  Set<String> _selectedIngredientIds = {};
  Timer? _pantrySaveTimer;

  Map<String, List<String>> _authorFollowers = {};
  int? _firebaseFollowerCount;
  Set<String> _firebaseFollowingIds = {};

  @override
  void initState() {
    super.initState();
    _sharedIngredients = [];
    _userProfile = UserProfile(
      userId: '1',
      userName: 'Laura Huynh',
      recipesCookedCount: 12,
      estimatedMoneySaved: 87.50,
    );
    _communityReviews = [];
    _loadPantryIngredients();
    _loadUserProfile();
    _loadDismissedRestockIds();
    MaintenanceService.runStartupTasks();
    _syncFirebaseAuth();
    FirebaseService.authStateChanges.listen((_) => _syncFirebaseAuth());
  }

  Future<void> _syncFirebaseAuth() async {
    final result = await FirebaseService.syncProfileWithAuth();
    if (result == null) {
      setState(() {
        _firebaseFollowerCount = null;
        _firebaseFollowingIds = {};
      });
      return;
    }
    setState(() {
      _userProfile = _userProfile.copyWith(
        userId: result.userId,
        userName: result.userName,
        avatarUrl: result.avatarUrl,
      );
      _firebaseFollowerCount = result.followerCount;
      _firebaseFollowingIds = result.followingIds;
    });
  }

  @override
  void dispose() {
    _pantrySaveTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDismissedRestockIds() async {
    final dismissed = await PantryService.loadDismissedRestockIds();
    setState(() => _dismissedRestockIds = dismissed);
  }

  Future<void> _loadPantryIngredients() async {
    final ingredients = await PantryService.loadPantryIngredients();
    setState(() => _sharedIngredients = ingredients);
  }

  Future<void> _savePantryIngredients() async {
    await PantryService.savePantryIngredients(_sharedIngredients);
  }

  Future<void> _loadUserProfile() async {
    final result = await ProfileService.loadProfile();
    for (final data in result.savedRecipeData) {
      final id = data['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final cache = RecipeFeedScreenState.fetchedRecipesCache;
      final idx = cache.indexWhere((r) => r['id']?.toString() == id);
      if (idx >= 0) {
        cache[idx] = data;
      } else {
        cache.add(data);
      }
    }
    for (final data in result.cookedRecipeData) {
      final id = data['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final cache = RecipeFeedScreenState.fetchedRecipesCache;
      final idx = cache.indexWhere((r) => r['id']?.toString() == id);
      if (idx >= 0) {
        cache[idx] = data;
      } else {
        cache.add(data);
      }
    }
    setState(() {
      _authorFollowers = result.authorFollowers;
      _userProfile = result.profile;
    });
  }

  Future<void> _saveAuthorFollowers() async {
    await ProfileService.saveAuthorFollowers(_authorFollowers);
  }

  Future<void> _saveUserProfile() async {
    final allRecipeMaps = [
      ...RecipeFeedScreenState.userRecipes,
      ...RecipeFeedScreenState.fetchedRecipesCache,
    ];
    await ProfileService.saveProfile(
      _userProfile,
      _authorFollowers,
      allRecipeMaps,
    );
  }

  void _onProfileUpdated(UserProfile updatedProfile) {
    setState(() {
      _userProfile = updatedProfile;
    });
    _saveUserProfile();
    _updateIngredientsFlags();
  }

  void _updateIngredientsFlags() {
    final updatedIngredients = _sharedIngredients.map((ing) {
      return ing.copyWith(
        isAllergy: _userProfile.allergies.contains(ing.name),
        isAvoided: _userProfile.avoided.contains(ing.name),
      );
    }).toList();
    setState(() {
      _sharedIngredients = updatedIngredients;
    });
  }

  void _onTabTapped(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
  }

  void _updateSharedIngredients(List<Ingredient> ingredients) {
    setState(() => _sharedIngredients = ingredients);
    _pantrySaveTimer?.cancel();
    _pantrySaveTimer = Timer(const Duration(seconds: 1), _savePantryIngredients);
  }

  void _addCommunityReview(CommunityReview review) {
    setState(() => _communityReviews.add(review));
  }

  void _addConfirmedIngredients(List<Ingredient> newIngredients) {
    setState(() {
      _sharedIngredients = PantryService.mergeConfirmedIngredients(
        _sharedIngredients,
        newIngredients,
      );
    });
    _pantrySaveTimer?.cancel();
    _pantrySaveTimer = Timer(const Duration(seconds: 1), _savePantryIngredients);
  }

  void _restockIngredient(String ingredientId) {
    setState(() {
      _sharedIngredients = PantryService.restockIngredient(
        _sharedIngredients,
        ingredientId,
      );
    });
    _pantrySaveTimer?.cancel();
    _pantrySaveTimer = Timer(const Duration(seconds: 1), _savePantryIngredients);
  }

  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return PantryScreen(
          key: const PageStorageKey('PantryScreen'),
          onIngredientsUpdated: _updateSharedIngredients,
          sharedIngredients: _sharedIngredients,
          selectedIngredientIds: _selectedIngredientIds,
          onSelectionChanged: (ids) {
            setState(() => _selectedIngredientIds = ids);
          },
          onFindRecipes: () {
            setState(() => _currentIndex = 1);
          },
        );
      case 1:
        return RecipeFeedScreen(
          key: const PageStorageKey('RecipeFeedScreen'),
          sharedIngredients: _sharedIngredients,
          onIngredientsUpdated: _updateSharedIngredients,
          userProfile: _userProfile,
          onProfileUpdated: _onProfileUpdated,
          onAddCommunityReview: _addCommunityReview,
          communityReviews: _communityReviews,
          dismissedRestockIds: _dismissedRestockIds,
          selectedIngredientIds: _selectedIngredientIds,
          onClearSelection: () {
            setState(() => _selectedIngredientIds = {});
          },
          onFollowAuthor: (authorId) async {
            if (authorId == null ||
                authorId.isEmpty ||
                authorId == _userProfile.userId) {
              return;
            }
            if (FirebaseService.isSignedIn &&
                FirebaseService.isFirebaseUserId(authorId)) {
              await FirebaseService.follow(authorId);
              setState(() => _firebaseFollowingIds.add(authorId));
              return;
            }
            setState(() {
              _authorFollowers.putIfAbsent(authorId, () => []);
              if (!_authorFollowers[authorId]!.contains(_userProfile.userId)) {
                _authorFollowers[authorId]!.add(_userProfile.userId);
              }
              _saveAuthorFollowers();
            });
          },
          isFollowingAuthor: (id) {
            if (id == null) return false;
            if (_authorFollowers[id]?.contains(_userProfile.userId) ?? false) {
              return true;
            }
            if (FirebaseService.isFirebaseUserId(id) &&
                _firebaseFollowingIds.contains(id)) {
              return true;
            }
            return false;
          },
        );
      case 2:
        return AddIngredientScreen(
          key: const PageStorageKey('AddIngredientScreen'),
          onSwitchTab: _onTabTapped,
          onAddIngredients: _addConfirmedIngredients,
        );
      case 3:
        return ShoppingListScreen(
          key: const PageStorageKey('ShoppingListScreen'),
          pantryIngredients: _sharedIngredients,
          onRestock: _restockIngredient,
          onAddIngredients: _addConfirmedIngredients,
          onDismissRestock: (itemId) {
            setState(() => _dismissedRestockIds.add(itemId));
            PantryService.saveDismissedRestockIds(_dismissedRestockIds);
          },
        );
      case 4:
        return HubScreen(
          key: const PageStorageKey('HubScreen'),
          body: ProfileScreen(
            pantryIngredients: _sharedIngredients,
            onIngredientsUpdated: _updateSharedIngredients,
            userProfile: _userProfile,
            onProfileUpdated: _onProfileUpdated,
            onAddCommunityReview: _addCommunityReview,
            communityReviews: _communityReviews,
            followerCount:
                _firebaseFollowerCount ??
                _authorFollowers[_userProfile.userId]?.length ??
                0,
            userRecipes: RecipeFeedScreenState.userRecipes,
            fetchedRecipesCache: RecipeFeedScreenState.fetchedRecipesCache,
            onRecipeTap: (context, recipe) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RecipeDetailPage(
                    sharedIngredients: _sharedIngredients,
                    onIngredientsUpdated: _updateSharedIngredients,
                    recipeTitle: recipe.title,
                    recipeIngredients: recipe.ingredients,
                    ingredientMeasurements: recipe.ingredientMeasurements,
                    userProfile: _userProfile,
                    onProfileUpdated: _onProfileUpdated,
                    recipeId: recipe.id,
                    onAddCommunityReview: _addCommunityReview,
                    reviews: _communityReviews
                        .where((r) => r.recipeId == recipe.id)
                        .toList(),
                    imageUrl: recipe.imageUrl.isNotEmpty
                        ? recipe.imageUrl
                        : '',
                    cookTime: recipe.cookTimeMinutes,
                    rating: recipe.rating,
                    nutrition: recipe.nutrition,
                    instructions: const [],
                    sourceUrl: recipe.sourceUrl,
                    defaultServings: 4,
                    dismissedRestockIds: const {},
                  ),
                ),
              );
            },
            onDeleteRecipe: (id) {
              setState(() {
                RecipeFeedScreenState.userRecipes
                    .removeWhere((r) => r['id'] == id);
              });
            },
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    // TODO: eventually move to PantryService.getShoppingCount() for cleaner separation
    final shoppingListCount = _sharedIngredients
        .where((ing) =>
            ing.needsPurchase && !_dismissedRestockIds.contains(ing.id))
        .length;
    return MainNavigation(
      currentIndex: _currentIndex,
      onTabTapped: _onTabTapped,
      shoppingListCount: shoppingListCount,
      tabBuilder: _buildScreen,
    );
  }
}

// ================= 2. DISCOVERY FEED =================
class RecipeFeedScreen extends StatefulWidget {
  final List<Ingredient> sharedIngredients;
  final Function(List<Ingredient>) onIngredientsUpdated;
  final UserProfile userProfile;
  final Function(UserProfile)? onProfileUpdated;
  final Function(CommunityReview)? onAddCommunityReview;
  final List<CommunityReview> communityReviews;
  final Set<String> dismissedRestockIds;
  final Set<String> selectedIngredientIds;
  final VoidCallback? onClearSelection;
  final void Function(String? authorId)? onFollowAuthor;
  final bool Function(String? authorId) isFollowingAuthor;

  const RecipeFeedScreen({
    super.key,
    required this.sharedIngredients,
    required this.onIngredientsUpdated,
    required this.userProfile,
    this.onProfileUpdated,
    this.onAddCommunityReview,
    required this.communityReviews,
    this.dismissedRestockIds = const {},
    this.selectedIngredientIds = const {},
    this.onClearSelection,
    this.onFollowAuthor,
    this.isFollowingAuthor = _defaultIsFollowingAuthor,
  });

  @override
  State<RecipeFeedScreen> createState() => RecipeFeedScreenState();
}

bool _defaultIsFollowingAuthor(String? authorId) => false;

// ================= RECIPE ENTRY SCREEN =================
class RecipeEntryScreen extends StatefulWidget {
  final List<Ingredient> pantryIngredients;
  final Recipe? existingRecipe;
  const RecipeEntryScreen({
    super.key,
    required this.pantryIngredients,
    this.existingRecipe,
  });

  @override
  State<RecipeEntryScreen> createState() => _RecipeEntryScreenState();
}

class _RecipeEntryScreenState extends State<RecipeEntryScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _recipeImage;
  String recipeTitle = '';
  final TextEditingController _titleController = TextEditingController();
  List<Map<String, String>> ingredients = [
    {'name': '', 'amount': ''},
  ];
  List<String> instructions = [''];

  final _ingredientNameControllers = <TextEditingController>[];
  final _ingredientAmountControllers = <TextEditingController>[];
  final _instructionControllers = <TextEditingController>[];

  @override
  void initState() {
    super.initState();
    if (widget.existingRecipe != null) {
      _titleController.text = widget.existingRecipe!.title;
      ingredients = widget.existingRecipe!.ingredients
          .map((ing) => {'name': ing, 'amount': ''})
          .toList();
      instructions = ['']; // Keep simple for now
    }
    _syncControllers();
  }

  void _syncControllers() {
    // Ingredients
    while (_ingredientNameControllers.length < ingredients.length) {
      _ingredientNameControllers.add(
        TextEditingController(
          text: ingredients[_ingredientNameControllers.length]['name'],
        ),
      );
      _ingredientAmountControllers.add(
        TextEditingController(
          text: ingredients[_ingredientAmountControllers.length]['amount'],
        ),
      );
    }
    while (_ingredientNameControllers.length > ingredients.length) {
      _ingredientNameControllers.removeLast().dispose();
      _ingredientAmountControllers.removeLast().dispose();
    }
    // Instructions
    while (_instructionControllers.length < instructions.length) {
      _instructionControllers.add(
        TextEditingController(
          text: instructions[_instructionControllers.length],
        ),
      );
    }
    while (_instructionControllers.length > instructions.length) {
      _instructionControllers.removeLast().dispose();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (var c in _ingredientNameControllers) {
      c.dispose();
    }
    for (var c in _ingredientAmountControllers) {
      c.dispose();
    }
    for (var c in _instructionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Set<String> get pantryNames => widget.pantryIngredients
      .where(
        (ing) => (ing.unitType == UnitType.volume
            ? (ing.amount as double) > 0
            : amountAsDouble(ing.amount) > 0),
      )
      .map((ing) => ing.name.toLowerCase())
      .toSet();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _recipeImage = File(image.path);
        });
      }
    } catch (e) {
      // Image picking error - silently handle
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncControllers();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingRecipe != null ? 'Edit Recipe' : 'Create Recipe',
        ),
        backgroundColor: kBoneCreame,
        foregroundColor: kDeepForestGreen,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Recipe Title Field
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Recipe Title',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: kDeepForestGreen,
              ),
              onChanged: (val) {
                setState(() {
                  recipeTitle = val;
                });
              },
            ),
            const SizedBox(height: 24),
            // Recipe Image Section
            GestureDetector(
              onTap: () => _showImagePickerModal(),
              child: Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: kBoneCreame,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kMutedGold, width: 2),
                ),
                child: _recipeImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(_recipeImage!, fit: BoxFit.cover),
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt, size: 48, color: kMutedGold),
                            const SizedBox(height: 12),
                            const Text(
                              'Tap to add recipe photo',
                              style: TextStyle(
                                color: kMutedGold,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 32),
            // Ingredients Section
            const Text(
              'INGREDIENTS',
              style: TextStyle(
                color: kMutedGold,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ...ingredients.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final ing = entry.value;
                    final inPantry = pantryNames.contains(
                      ing['name']!.toLowerCase(),
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 120,
                                  child: TextField(
                                    controller: _ingredientNameControllers[idx],
                                    decoration: const InputDecoration(
                                      hintText: 'Ingredient',
                                      border: InputBorder.none,
                                    ),
                                    textCapitalization:
                                        TextCapitalization.words,
                                    style: const TextStyle(
                                      color: kDeepForestGreen,
                                      fontFamily: 'Playfair Display',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    onChanged: (val) {
                                      setState(() {
                                        ingredients[idx]['name'] = val;
                                      });
                                    },
                                  ),
                                ),
                                if (inPantry && ing['name']!.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kSageGreen.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'In Pantry',
                                      style: TextStyle(
                                        color: kSageGreen,
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: _ingredientAmountControllers[idx],
                              decoration: const InputDecoration(
                                hintText: 'Amount',
                                border: InputBorder.none,
                              ),
                              style: const TextStyle(
                                color: kMutedGold,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                              onChanged: (val) {
                                setState(() {
                                  ingredients[idx]['amount'] = val;
                                });
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: kSoftTerracotta,
                            ),
                            onPressed: ingredients.length > 1
                                ? () {
                                    setState(() {
                                      ingredients.removeAt(idx);
                                    });
                                  }
                                : null,
                          ),
                        ],
                      ),
                    );
                  }),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        ingredients.add({'name': '', 'amount': ''});
                      });
                    },
                    icon: const Icon(Icons.add, color: kSageGreen),
                    label: const Text(
                      'Add Ingredient',
                      style: TextStyle(color: kSageGreen),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'HOW TO MAKE',
                    style: TextStyle(
                      color: kMutedGold,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...instructions.asMap().entries.map((entry) {
                    final idx = entry.key;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${idx + 1}. ',
                            style: const TextStyle(
                              color: kDeepForestGreen,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _instructionControllers[idx],
                              maxLines: null,
                              decoration: const InputDecoration(
                                hintText: 'Step',
                                border: InputBorder.none,
                              ),
                              textCapitalization: TextCapitalization.sentences,
                              style: const TextStyle(
                                color: kDeepForestGreen,
                                fontFamily: 'Inter',
                                fontSize: 15,
                                height: 1.5,
                              ),
                              onChanged: (val) {
                                setState(() {
                                  instructions[idx] = val;
                                });
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: kSoftTerracotta,
                            ),
                            onPressed: instructions.length > 1
                                ? () {
                                    setState(() {
                                      instructions.removeAt(idx);
                                    });
                                  }
                                : null,
                          ),
                        ],
                      ),
                    );
                  }),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        instructions.add('');
                      });
                    },
                    icon: const Icon(Icons.add, color: kSageGreen),
                    label: const Text(
                      'Add Step',
                      style: TextStyle(color: kSageGreen),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        // Validate form
                        if (_titleController.text.trim().isEmpty) {
                          return;
                        }

                        // Create Recipe object from form data
                        final ingredientNames = _ingredientNameControllers
                            .map((c) => c.text.trim())
                            .where((name) => name.isNotEmpty)
                            .toList();

                        if (ingredientNames.isEmpty) {
                          return;
                        }

                        if (widget.existingRecipe != null) {
                          // Update existing recipe
                          final index = RecipeFeedScreenState.userRecipes
                              .indexWhere(
                                (r) => r['id'] == widget.existingRecipe!.id,
                              );
                          if (index != -1) {
                            RecipeFeedScreenState.userRecipes[index] = {
                              'id': widget.existingRecipe!.id,
                              'title': _titleController.text.trim(),
                              'ingredients': ingredientNames,
                              'cookTime':
                                  widget.existingRecipe!.cookTimeMinutes,
                              'rating': widget.existingRecipe!.rating,
                              'reviews': widget.existingRecipe!.reviewCount,
                              'imageUrl': widget.existingRecipe!.imageUrl,
                              'aspectRatio': widget.existingRecipe!.aspectRatio,
                              'authorName': widget.existingRecipe!.authorName,
                            };
                          }
                          Navigator.pop(context);
                        } else {
                          // Create new recipe
                          final newRecipe = Recipe(
                            id: DateTime.now().millisecondsSinceEpoch
                                .toString(),
                            title: _titleController.text.trim(),
                            imageUrl: '',
                            ingredients: ingredientNames,
                            ingredientTags: {},
                            cookTimeMinutes: 30,
                            rating: 5.0,
                            reviewCount: 0,
                            createdDate: DateTime.now(),
                            isSaved: false,
                          );
                          Navigator.pop(context, newRecipe);
                        }
                      },
                      child: Text(
                        widget.existingRecipe != null
                            ? 'UPDATE RECIPE'
                            : 'BRING TO POTLUCK',
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImagePickerModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose Recipe Photo',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: kCharcoal,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _pickImage(ImageSource.camera);
                      Navigator.pop(context);
                    },
                    child: Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: kSageGreen.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 40,
                            color: kSageGreen,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Camera',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _pickImage(ImageSource.gallery);
                      Navigator.pop(context);
                    },
                    child: Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: kMutedGold.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.photo_library,
                            size: 40,
                            color: kMutedGold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Gallery',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_recipeImage != null) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _recipeImage = null);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete, color: kSoftTerracotta),
                  label: const Text(
                    'Remove Photo',
                    style: TextStyle(color: kSoftTerracotta),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class RecipeFeedScreenState extends State<RecipeFeedScreen> {
  // Filter state
  late RecipeFilter _filter;
  final bool _debugForceShow = false;
  final EdamamRecipeService _edamamRecipeService = EdamamRecipeService();
  String? _remoteError;
  Future<List<Map<String, dynamic>>>? _remoteRecipesFuture;
  List<Map<String, dynamic>>? _cachedFilteredRecipes;
  String? _lastFilterSignature;
  // Track last pantry for significant change detection
  static const int _cacheMaxAgeMins = 30;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Profile-based filter state
  late Map<String, dynamic> _appliedFilters;
  bool _showDietaryBanner = true; // Track if banner is visible

  // Infinite scroll pagination state
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 20;
  int _currentPage = 0;
  List<Map<String, dynamic>> _displayedRecipes = [];
  List<Map<String, dynamic>> _allFilteredRecipes = [];
  bool _isLoadingMore = false;
  bool _hasMoreRecipes = true;

  // Feed toggle state: 'forYou' or 'discover'
  String _selectedFeed = 'forYou';

  @override
  void initState() {
    super.initState();
    _filter = RecipeFilter(
      allergyIngredients: widget.userProfile.allergies,
      avoidedIngredients: widget.userProfile.avoided,
    );

    // Initialize applied filters from Profile
    _appliedFilters = {
      'diets': widget.userProfile.selectedLifestyles.toList(),
      'intolerances': widget.userProfile.allergies.toList(),
      'cuisines': <String>[],
      'mealTypes': <String>[],
      'cookingMethods': <String>[],
      'macroGoals': <String>[],
      'prepTime': '',
    };

    _remoteRecipesFuture = _fetchRemoteRecipes();

    // Add scroll listener for infinite scroll
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Scroll listener for infinite scroll pagination
  void _onScroll() {
    if (_isLoadingMore || !_hasMoreRecipes) return;

    // Load more when user scrolls to 80% of the list
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final threshold = maxScroll * 0.8;

    if (currentScroll >= threshold) {
      _loadMoreRecipes();
    }
  }

  /// Load next page of recipes
  void _loadMoreRecipes() {
    if (_isLoadingMore || !_hasMoreRecipes) return;

    setState(() {
      _isLoadingMore = true;
    });

    // Simulate a small delay for smooth UX
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;

      final startIndex = (_currentPage + 1) * _pageSize;
      final endIndex = (startIndex + _pageSize).clamp(
        0,
        _allFilteredRecipes.length,
      );

      if (startIndex >= _allFilteredRecipes.length) {
        setState(() {
          _hasMoreRecipes = false;
          _isLoadingMore = false;
        });
        return;
      }

      final newRecipes = _allFilteredRecipes.sublist(startIndex, endIndex);

      setState(() {
        _displayedRecipes.addAll(newRecipes);
        _currentPage++;
        _hasMoreRecipes = endIndex < _allFilteredRecipes.length;
        _isLoadingMore = false;
      });
    });
  }

  /// Reset pagination when filters change or new data is loaded
  void _resetPagination(List<Map<String, dynamic>> allRecipes) {
    _allFilteredRecipes = allRecipes;
    _currentPage = 0;
    _hasMoreRecipes = allRecipes.length > _pageSize;

    // Load first page
    final endIndex = _pageSize.clamp(0, allRecipes.length);
    _displayedRecipes = allRecipes.sublist(0, endIndex);
  }

  @override
  void didUpdateWidget(RecipeFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userProfile != widget.userProfile) {
      setState(() {
        _filter = _filter.copyWith(
          allergyIngredients: widget.userProfile.allergies,
          avoidedIngredients: widget.userProfile.avoided,
        );
      });
    }

    // Refetch when pantry contents significantly change (not on every tiny change)

    if (_hasSignificantChange(
      oldWidget.sharedIngredients,
      widget.sharedIngredients,
    )) {
      setState(() {
        _remoteRecipesFuture = _fetchRemoteRecipes();
      });
    }
  }

  /// Get sorted list of pantry ingredient names for cache key/change detection
  List<String> _getPantryList() {
    return widget.sharedIngredients
        .where(
          (ing) => (ing.unitType == UnitType.volume
              ? (ing.amount as double) > 0
              : amountAsDouble(ing.amount) > 0),
        )
        .map((ing) => ing.name.toLowerCase())
        .toList()
      ..sort();
  }

  /// Detect if pantry changed significantly (added/removed items, not quantity tweaks)
  bool _hasSignificantChange(
    List<Ingredient> oldList,
    List<Ingredient> newList,
  ) {
    final oldNames = oldList
        .where(
          (ing) => (ing.unitType == UnitType.volume
              ? (ing.amount as double) > 0
              : amountAsDouble(ing.amount) > 0),
        )
        .map((ing) => ing.name)
        .toSet();

    final newNames = newList
        .where(
          (ing) => (ing.unitType == UnitType.volume
              ? (ing.amount as double) > 0
              : amountAsDouble(ing.amount) > 0),
        )
        .map((ing) => ing.name)
        .toSet();

    // Significant if items were added or removed (not just quantity changes)
    return oldNames != newNames;
  }

  /// Get cache key based on sorted pantry ingredients
  Future<String> _getCacheKey() async {
    final pantryNames = _getPantryList();
    if (pantryNames.isEmpty) return 'edamam_cache_v1_empty';
    return 'edamam_cache_v1_${pantryNames.join('_')}';
  }

  /// Check if cache is still valid (less than 30 minutes old)
  Future<bool> _isCacheValid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = await _getCacheKey();
      final timestampKey = '${cacheKey}_timestamp';

      final timestamp = prefs.getInt(timestampKey);
      if (timestamp == null) return false;

      final cacheAge = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(timestamp),
      );
      final isValid = cacheAge.inMinutes < _cacheMaxAgeMins;
      return isValid;
    } catch (e) {
      return false;
    }
  }

  /// Load recipes from cache
  Future<List<Map<String, dynamic>>?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = await _getCacheKey();
      final cachedJson = prefs.getString(cacheKey);

      if (cachedJson == null) {
        return null;
      }

      final decoded = jsonDecode(cachedJson) as List<dynamic>;
      final results = decoded.cast<Map<String, dynamic>>();
      return results;
    } catch (e) {
      return null;
    }
  }

  /// Save recipes to cache with timestamp
  Future<void> _saveToCache(List<Map<String, dynamic>> recipes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = await _getCacheKey();
      final timestampKey = '${cacheKey}_timestamp';

      final json = jsonEncode(recipes);
      await prefs.setString(cacheKey, json);
      await prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      // ignore: empty catch blocks
    }
  }

  /// Fetch recipes with cache-first strategy
  /// Set [forceRefresh] to true to bypass cache and fetch from network
  Future<List<Map<String, dynamic>>> _fetchRemoteRecipes({
    bool forceRefresh = false,
  }) async {
    final pantryNames = _getPantryList();

    // Try cache first (unless force refresh)
    // This allows showing cached recipes on app startup even if pantry hasn't loaded yet
    if (!forceRefresh) {
      if (await _isCacheValid()) {
        final cached = await _loadFromCache();
        // Only use cache if it has actual recipes (don't return empty cache)
        if (cached != null && cached.isNotEmpty) {
          _remoteError = null;
          return cached;
        }
      }
    }

    // If pantry is empty, don't fetch new recipes (only use cache)
    if (pantryNames.isEmpty) {
      _remoteError = null;
      return [];
    }

    // Cache miss or expired or forced refresh - fetch from network
    try {
      _remoteError = null;

      // Note: Edamam fetches recipes based on pantry items
      // Dietary filters will be applied client-side after generation
      // Fetch more recipes (100) for infinite scroll pagination
      final results = await _edamamRecipeService.fetchRecipesFromPantry(
        widget.sharedIngredients,
        forceRefresh: forceRefresh,
        maxResults: 100,
      );
      if (results.isNotEmpty) {
        // Only cache if we got actual results (don't cache empty responses)
        await _saveToCache(results);
      }
      return results;
    } catch (e) {
      _remoteError = e.toString();

      // On network error, try to fall back to stale cache if available
      try {
        final prefs = await SharedPreferences.getInstance();
        final cacheKey = await _getCacheKey();
        final cachedJson = prefs.getString(cacheKey);
        if (cachedJson != null) {
          final decoded = jsonDecode(cachedJson) as List<dynamic>;
          return decoded.cast<Map<String, dynamic>>();
        }
      } catch (_) {}

      throw Exception(_remoteError);
    }
  }

  // Mock recipes database
  // User-created recipes (no bundled mock data)
  static final List<Map<String, dynamic>> userRecipes = [];

  // Cached fetched recipes from Edamam API (accessible to ProfileScreen for saved/cooked)
  static List<Map<String, dynamic>> fetchedRecipesCache = [];

  /// Calculate recipe match percentage (case-insensitive, partial matching)
  double _getRecipeMatchPercentage(List<String> recipeIngredients) {
    if (recipeIngredients.isEmpty) return 0.0;
    if (widget.sharedIngredients.isEmpty) return 0.0;

    int matched = 0;
    for (var recipeIng in recipeIngredients) {
      if (IngredientMatchService.isBasicStaple(recipeIng)) {
        matched++;
        continue;
      }
      final hasIngredient = widget.sharedIngredients.any((pantryIng) {
        final hasQuantity =
            pantryIng.amount != null &&
            (pantryIng.unitType == UnitType.volume
                ? (pantryIng.amount as double) > 0
                : amountAsDouble(pantryIng.amount) > 0);
        if (!hasQuantity) return false;
        return IngredientMatchService.ingredientMatches(recipeIng, pantryIng.name);
      });
      if (hasIngredient) matched++;
    }

    return (matched / recipeIngredients.length) * 100.0;
  }

  /// Get count of missing ingredients
  int _getMissingIngredientsCount(List<String> recipeIngredients) {
    if (widget.sharedIngredients.isEmpty) {
      return recipeIngredients.length; // All missing if no pantry items
    }

    int missing = 0;
    for (var recipeIng in recipeIngredients) {
      if (IngredientMatchService.isBasicStaple(recipeIng)) {
        continue;
      }
      final hasIngredient = widget.sharedIngredients.any((pantryIng) {
        final hasQuantity =
            pantryIng.amount != null &&
            (pantryIng.unitType == UnitType.volume
                ? (pantryIng.amount as double) > 0
                : amountAsDouble(pantryIng.amount) > 0);
        if (!hasQuantity) return false;
        return IngredientMatchService.ingredientMatches(recipeIng, pantryIng.name);
      });
      if (!hasIngredient) missing++;
    }
    return missing;
  }

  /// Get list of missing ingredients
  List<String> _getMissingIngredients(List<String> recipeIngredients) {
    if (widget.sharedIngredients.isEmpty) {
      return recipeIngredients; // All missing if no pantry items
    }

    final missing = <String>[];
    for (var recipeIng in recipeIngredients) {
      if (IngredientMatchService.isBasicStaple(recipeIng)) {
        continue;
      }
      final hasIngredient = widget.sharedIngredients.any((pantryIng) {
        final hasQuantity =
            pantryIng.amount != null &&
            (pantryIng.unitType == UnitType.volume
                ? (pantryIng.amount as double) > 0
                : amountAsDouble(pantryIng.amount) > 0);
        if (!hasQuantity) return false;
        return IngredientMatchService.ingredientMatches(recipeIng, pantryIng.name);
      });
      if (!hasIngredient) missing.add(recipeIng);
    }
    return missing;
  }

  /// Check if recipe has all ingredients
  bool _isReadyToCook(List<String> recipeIngredients) {
    return _getMissingIngredientsCount(recipeIngredients) == 0;
  }

  /// Callback when AdvancedSearchScreen applies filters
  void _onFiltersApplied(Map<String, dynamic> filters) {
    // Update UI immediately for responsive feel
    setState(() {
      _appliedFilters = filters;
    });

    // Refetch recipes after UI update (non-blocking)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _remoteRecipesFuture = _fetchRemoteRecipes();
        });
      }
    });
  }

  /// Check if any filters are currently active
  bool _hasActiveFilters() {
    final diets = (_appliedFilters['diets'] as List<String>?) ?? [];
    final intolerances =
        (_appliedFilters['intolerances'] as List<String>?) ?? [];
    final cuisines = (_appliedFilters['cuisines'] as List<String>?) ?? [];
    final mealTypes = (_appliedFilters['mealTypes'] as List<String>?) ?? [];
    final cookingMethods =
        (_appliedFilters['cookingMethods'] as List<String>?) ?? [];
    final macroGoals = (_appliedFilters['macroGoals'] as List<String>?) ?? [];
    final prepTime = (_appliedFilters['prepTime'] as String?) ?? '';
    final searchQuery = (_appliedFilters['searchQuery'] as String?) ?? '';

    return diets.isNotEmpty ||
        intolerances.isNotEmpty ||
        cuisines.isNotEmpty ||
        mealTypes.isNotEmpty ||
        cookingMethods.isNotEmpty ||
        macroGoals.isNotEmpty ||
        prepTime.isNotEmpty ||
        searchQuery.isNotEmpty;
  }

  /// Get list of active filter chips with their type and value
  List<Map<String, String>> _getActiveFilterChips() {
    final chips = <Map<String, String>>[];

    final diets = (_appliedFilters['diets'] as List<String>?) ?? [];
    final intolerances =
        (_appliedFilters['intolerances'] as List<String>?) ?? [];
    final cuisines = (_appliedFilters['cuisines'] as List<String>?) ?? [];
    final mealTypes = (_appliedFilters['mealTypes'] as List<String>?) ?? [];
    final cookingMethods =
        (_appliedFilters['cookingMethods'] as List<String>?) ?? [];
    final macroGoals = (_appliedFilters['macroGoals'] as List<String>?) ?? [];
    final prepTime = (_appliedFilters['prepTime'] as String?) ?? '';
    final searchQuery = (_appliedFilters['searchQuery'] as String?) ?? '';

    for (final diet in diets) {
      chips.add({'type': 'diets', 'value': diet});
    }
    for (final intolerance in intolerances) {
      chips.add({'type': 'intolerances', 'value': intolerance});
    }
    for (final cuisine in cuisines) {
      chips.add({'type': 'cuisines', 'value': cuisine});
    }
    for (final mealType in mealTypes) {
      chips.add({'type': 'mealTypes', 'value': mealType});
    }
    for (final method in cookingMethods) {
      chips.add({'type': 'cookingMethods', 'value': method});
    }
    for (final macro in macroGoals) {
      chips.add({'type': 'macroGoals', 'value': macro});
    }
    if (prepTime.isNotEmpty) {
      chips.add({'type': 'prepTime', 'value': prepTime});
    }
    if (searchQuery.isNotEmpty) {
      chips.add({'type': 'searchQuery', 'value': '"$searchQuery"'});
    }

    return chips;
  }

  /// Remove a specific filter
  void _removeFilter(String filterType, String value) {
    setState(() {
      if (filterType == 'prepTime') {
        _appliedFilters['prepTime'] = '';
      } else if (filterType == 'searchQuery') {
        _appliedFilters['searchQuery'] = '';
      } else {
        final list = (_appliedFilters[filterType] as List<String>?) ?? [];
        list.remove(value);
        _appliedFilters[filterType] = list;
      }
      // Refetch recipes with updated filters
      _remoteRecipesFuture = _fetchRemoteRecipes();
    });
  }

  /// Clear all filters
  void _clearAllFilters() {
    // Update UI immediately - no need to refetch since recipes are cached
    setState(() {
      _appliedFilters = {
        'diets': <String>[],
        'intolerances': <String>[],
        'cuisines': <String>[],
        'mealTypes': <String>[],
        'cookingMethods': <String>[],
        'macroGoals': <String>[],
        'prepTime': '',
        'searchQuery': '',
      };
      // Reset pagination to show all recipes
      _resetPagination(_allFilteredRecipes);
    });
  }

  /// Build the filter chips widget
  Widget _buildFilterChips() {
    final chips = _getActiveFilterChips();
    if (chips.isEmpty) return const SizedBox.shrink();

    // Compact horizontal strip with explicit small height so it always renders
    return SizedBox(
      height: 28,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // Clear All button
          GestureDetector(
            onTap: _clearAllFilters,
            child: Container(
              // Extra-thin Clear All chip with fixed height
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              margin: const EdgeInsets.only(right: 8),
              constraints: const BoxConstraints(minHeight: 16, maxHeight: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.grey.withOpacity(0.6),
                  width: 0.8,
                ),
              ),
              child: Text(
                'Clear All',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                  height: 1.0,
                ),
              ),
            ),
          ),
          // Individual filter chips
          ...chips.map((chip) {
            final type = chip['type']!;
            final value = chip['value']!;
            // Clean up display value (remove quotes for searchQuery)
            final displayValue = type == 'searchQuery' ? value : value;

            return Container(
              margin: const EdgeInsets.only(right: 8),
              child: Chip(
                // Minimal gap between label text and close icon
                labelPadding: const EdgeInsets.only(left: 8, right: 0),
                label: Text(
                  displayValue,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: kDeepForestGreen,
                  ),
                ),
                deleteIcon: const Icon(Icons.close, size: 13),
                deleteIconColor: kDeepForestGreen.withOpacity(0.7),
                onDeleted: () => _removeFilter(
                  type,
                  type == 'searchQuery' ? value.replaceAll('"', '') : value,
                ),
                backgroundColor: kDeepForestGreen.withOpacity(0.1),
                side: BorderSide(color: kDeepForestGreen.withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _remoteRecipesFuture,
        builder: (context, snapshot) {
          final isLoading = snapshot.connectionState == ConnectionState.waiting;
          final remoteRecipes = snapshot.data ?? [];
          final remoteError = snapshot.error?.toString() ?? _remoteError;

          // Cache fetched recipes for ProfileScreen's saved/cooked tabs
          // remoteRecipes are already converted by EdamamRecipeService.fetchRecipesFromPantry()
          if (remoteRecipes.isNotEmpty) {
            // Build set of IDs that are saved or cooked — never overwrite these
            // so that restored profile data survives a feed refresh
            final savedIds = <String>{
              ...widget.userProfile.savedRecipeIds,
              ...widget.userProfile.cookedRecipeIds,
            };

            // Start from existing cache (preserves restored saved/cooked entries)
            final recipesById = <String, Map<String, dynamic>>{
              for (final r in fetchedRecipesCache)
                if (r['id']?.toString() != null) r['id'].toString(): r,
            };

            // Add new remote recipes, but never overwrite saved/cooked entries
            for (final recipe in remoteRecipes) {
              final id = recipe['id']?.toString();
              if (id != null && id.isNotEmpty && !savedIds.contains(id)) {
                recipesById[id] = recipe;
              }
            }

            fetchedRecipesCache = recipesById.values.toList();
          }

          // Combine cached recipes with user recipes (no duplicates)
          // Use fetchedRecipesCache which already has deduplicated remote recipes
          var allRecipes = <Map<String, dynamic>>[
            ...fetchedRecipesCache,
            ...userRecipes,
          ];

          // Safety check: If data is missing, show error
          if (allRecipes.isEmpty && !isLoading) {
            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 0,
                  backgroundColor: kBoneCreame,
                  title: const Text('Potluck'),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh Recipes',
                      onPressed: () {
                        setState(() {
                          _remoteRecipesFuture = _fetchRemoteRecipes(
                            forceRefresh: true,
                          );
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'Post a Recipe',
                      onPressed: () async {
                        final newRecipe = await Navigator.push<Recipe>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RecipeEntryScreen(
                              pantryIngredients: widget.sharedIngredients,
                            ),
                          ),
                        );

                        if (newRecipe != null && mounted) {
                          // Use empty string for imageUrl since we're not using ImagenService
                          final imageUrl = '';
                          setState(() {
                            final aspectChoices = [0.85, 0.88, 0.9, 0.92, 0.95];
                            final ar =
                                aspectChoices[Random().nextInt(
                                  aspectChoices.length,
                                )];
                            userRecipes.insert(0, {
                              'id': newRecipe.id,
                              'title': newRecipe.title,
                              'ingredients': newRecipe.ingredients,
                              'cookTime': newRecipe.cookTimeMinutes,
                              'rating': newRecipe.rating,
                              'reviews': newRecipe.reviewCount,
                              'imageUrl': imageUrl,
                              'aspectRatio': ar,
                              'authorName': newRecipe.authorName,
                            });
                          });
                        }
                      },
                    ),
                  ],
                  bottom: PreferredSize(
                    preferredSize: Size.fromHeight(
                      _hasActiveFilters() ? 120 : 76,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push<Map<String, dynamic>>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AdvancedSearchScreen(
                                    userProfile: widget.userProfile,
                                    onApplyFilters: _onFiltersApplied,
                                  ),
                                ),
                              );
                            },
                            child: AbsorbPointer(
                              child: TextField(
                                controller: _searchController,
                                onChanged: (value) {
                                  setState(() {
                                    _searchQuery = value.toLowerCase();
                                  });
                                },
                                decoration: InputDecoration(
                                  hintText: 'Search recipes...',
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    color: Colors.grey,
                                  ),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() {
                                              _searchQuery = '';
                                            });
                                          },
                                        )
                                      : null,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: kDeepForestGreen,
                                      width: 2,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: kDeepForestGreen,
                                      width: 2,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: kDeepForestGreen,
                                      width: 2,
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: kBoneCreame.withOpacity(0.5),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: _buildFilterChips(),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.restaurant_menu,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                        Text(
                          'No recipes available',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add a recipe or ingredients to get started!',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          // Cache filtering/sorting to avoid recomputation on tab switches
          final pantryKey = _getPantryList().join('|');
          final dietsKey =
              ((_appliedFilters['diets'] as List<dynamic>?) ?? [])
                  .map((e) => e.toString().toLowerCase())
                  .toList()
                ..sort();
          final intolerancesKey =
              ((_appliedFilters['intolerances'] as List<dynamic>?) ?? [])
                  .map((e) => e.toString().toLowerCase())
                  .toList()
                ..sort();
          final cuisinesKey =
              ((_appliedFilters['cuisines'] as List<dynamic>?) ?? [])
                  .map((e) => e.toString().toLowerCase())
                  .toList()
                ..sort();
          final mealTypesKey =
              ((_appliedFilters['mealTypes'] as List<dynamic>?) ?? [])
                  .map((e) => e.toString().toLowerCase())
                  .toList()
                ..sort();
          final cookingMethodsKey =
              ((_appliedFilters['cookingMethods'] as List<dynamic>?) ?? [])
                  .map((e) => e.toString().toLowerCase())
                  .toList()
                ..sort();
          final macroGoalsKey =
              ((_appliedFilters['macroGoals'] as List<dynamic>?) ?? [])
                  .map((e) => e.toString().toLowerCase())
                  .toList()
                ..sort();
          final prepTimeKey = (_appliedFilters['prepTime'] as String?) ?? '';
          final advancedSearchQuery =
              (_appliedFilters['searchQuery'] as String?) ?? '';
          final allIdsKey = allRecipes
              .map((r) => r['id']?.toString() ?? '')
              .join('|');
          final signature = [
            pantryKey,
            allIdsKey,
            dietsKey.join(','),
            intolerancesKey.join(','),
            cuisinesKey.join(','),
            mealTypesKey.join(','),
            cookingMethodsKey.join(','),
            macroGoalsKey.join(','),
            prepTimeKey,
            _searchQuery,
            advancedSearchQuery,
            _debugForceShow.toString(),
          ].join('::');

          List<Map<String, dynamic>> filteredRecipes;
          if (_lastFilterSignature == signature &&
              _cachedFilteredRecipes != null) {
            filteredRecipes = _cachedFilteredRecipes!;
            // Ensure pagination is initialized from cache
            if (_allFilteredRecipes.isEmpty ||
                _allFilteredRecipes != filteredRecipes) {
              _resetPagination(filteredRecipes);
            }
          } else {
            // Sort by pantry match percentage first (more matches = better), then by rating
            allRecipes.sort((a, b) {
              // Calculate match percentages
              final aIngredients = (a['ingredients'] as List<dynamic>? ?? [])
                  .map((e) => e.toString().toLowerCase().trim())
                  .toList();
              final bIngredients = (b['ingredients'] as List<dynamic>? ?? [])
                  .map((e) => e.toString().toLowerCase().trim())
                  .toList();

              final pantryNames = widget.sharedIngredients
                  .where(
                    (ing) =>
                        ing.amount != null &&
                        ((ing.unitType == UnitType.volume &&
                                (ing.amount as double) > 0) ||
                            (ing.unitType != UnitType.volume &&
                                amountAsDouble(ing.amount) > 0)),
                  )
                  .map((e) => e.name.toLowerCase().trim())
                  .toSet();

              int aMatches = 0, bMatches = 0;
              for (var ing in aIngredients) {
                if (IngredientMatchService.isBasicStaple(ing)) {
                  aMatches++;
                  continue;
                }
                if (pantryNames.any(
                  (p) => IngredientMatchService.ingredientMatches(ing, p),
                )) {
                  aMatches++;
                }
              }
              for (var ing in bIngredients) {
                if (IngredientMatchService.isBasicStaple(ing)) {
                  bMatches++;
                  continue;
                }
                if (pantryNames.any(
                  (p) => IngredientMatchService.ingredientMatches(ing, p),
                )) {
                  bMatches++;
                }
              }

              // Higher match count comes first
              final aMatchPct = aIngredients.isNotEmpty
                  ? (aMatches / aIngredients.length) * 100
                  : 0;
              final bMatchPct = bIngredients.isNotEmpty
                  ? (bMatches / bIngredients.length) * 100
                  : 0;

              // Compare match percentages first (descending)
              final matchComparison = bMatchPct.compareTo(aMatchPct);
              if (matchComparison != 0) return matchComparison;

              // If match is equal, use rating as tiebreaker
              final ratingA = a['rating'] as double? ?? 0.0;
              final ratingB = b['rating'] as double? ?? 0.0;
              return ratingB.compareTo(ratingA);
            });

            // Apply feed-based filtering first
            if (_selectedFeed == 'forYou') {
              // FOR YOU: Show pantry-based recipes (Edamam API recipes)
              filteredRecipes = allRecipes.where((recipe) {
                final authorName = recipe['authorName'] as String? ?? '';
                // Show only API-fetched recipes (not user-created)
                return authorName != 'You' && authorName != 'Anonymous';
              }).toList();
            } else {
              // DISCOVER: Show community/user-created recipes
              filteredRecipes = allRecipes.where((recipe) {
                final authorName = recipe['authorName'] as String? ?? '';
                // Show only user-created recipes
                return authorName == 'You' || authorName == 'Anonymous';
              }).toList();
            }

            // Apply ingredient matching and dietary filtering
            if (_debugForceShow) {
              // Keep current filtered recipes
            } else {
              filteredRecipes = filteredRecipes.where((recipe) {
                final ingredientsList =
                    recipe['ingredients'] as List<dynamic>? ?? [];
                final ingredients = ingredientsList
                    .map((s) => s.toString().toLowerCase().trim())
                    .toList();

                // Apply dietary filtering to ALL recipes (uses dietary_filter_service)
                if (dietsKey.isNotEmpty || intolerancesKey.isNotEmpty) {
                  for (final diet in dietsKey) {
                    final blocked = RecipeDataConstants.lifestyleRules[diet.toLowerCase()] ?? [];
                    if (blocked.isNotEmpty && ingredients.any((ing) => !FilterService.isIngredientSafe(ing, blocked))) {
                      return false;
                    }
                  }
                  for (final intolerance in intolerancesKey) {
                    if (RecipeFilterService.recipeContainsIntolerance(ingredients, intolerance)) {
                      return false;
                    }
                  }
                }

                // For "For You" feed, recipes are already pantry-matched by Edamam API
                if (_selectedFeed == 'forYou') {
                  return true;
                }

                // For "Discover" feed, no additional filtering needed
                return true;
              }).toList();
            }

            // Apply search filter from main search bar
            if (_searchQuery.isNotEmpty) {
              filteredRecipes = filteredRecipes.where((recipe) {
                final title = (recipe['title'] as String).toLowerCase();
                return title.contains(_searchQuery);
              }).toList();
            }

            // Apply search filter from Advanced Search page
            if (advancedSearchQuery.isNotEmpty) {
              filteredRecipes = filteredRecipes.where((recipe) {
                final title = (recipe['title'] as String).toLowerCase();
                return title.contains(advancedSearchQuery);
              }).toList();
            }

            // Apply prep time filter
            if (prepTimeKey.isNotEmpty) {
              filteredRecipes = filteredRecipes.where((recipe) {
                final cookTime = recipe['cookTime'] as int? ?? 30;
                if (prepTimeKey.contains('15')) {
                  return cookTime <= 15;
                } else if (prepTimeKey.contains('30')) {
                  return cookTime <= 30;
                } else if (prepTimeKey.contains('45')) {
                  return cookTime <= 45;
                } else if (prepTimeKey.contains('1hr') ||
                    prepTimeKey.contains('slow')) {
                  return cookTime > 45;
                }
                return true;
              }).toList();
            }

            // Apply meal type filter
            if (mealTypesKey.isNotEmpty) {
              filteredRecipes = filteredRecipes.where((recipe) {
                final recipeMealTypes =
                    (recipe['mealTypes'] as List<dynamic>?)
                        ?.map((e) => e.toString().toLowerCase())
                        .toList() ??
                    ['lunch'];
                // Check if any selected meal type matches
                return mealTypesKey.any((selectedType) {
                  final normalizedSelected = selectedType
                      .replaceAll(' ', '')
                      .toLowerCase();
                  return recipeMealTypes.any((recipeType) {
                    final normalizedRecipe = recipeType
                        .replaceAll(' ', '')
                        .toLowerCase();
                    return normalizedRecipe.contains(normalizedSelected) ||
                        normalizedSelected.contains(normalizedRecipe) ||
                        // Handle main course = dinner/lunch
                        (normalizedSelected == 'maincourse' &&
                            (normalizedRecipe == 'dinner' ||
                                normalizedRecipe == 'lunch'));
                  });
                });
              }).toList();
            }

            // Apply macro goals filter
            if (macroGoalsKey.isNotEmpty) {
              filteredRecipes = filteredRecipes.where((recipe) {
                final nutrition = recipe['nutrition'];
                if (nutrition == null) {
                  return true; // Don't filter out recipes without nutrition info
                }

                // Extract nutrition values
                int calories = 0;
                double protein = 0;
                double carbs = 0;
                double fat = 0;

                if (nutrition is Map<String, dynamic>) {
                  calories = (nutrition['calories'] as num?)?.toInt() ?? 0;
                  protein = (nutrition['protein'] as num?)?.toDouble() ?? 0;
                  carbs = (nutrition['carbs'] as num?)?.toDouble() ?? 0;
                  fat = (nutrition['fat'] as num?)?.toDouble() ?? 0;
                }

                for (final goal in macroGoalsKey) {
                  if (goal.contains('high protein') && protein < 20) {
                    return false;
                  }
                  if (goal.contains('low carb') && carbs > 20) return false;
                  if (goal.contains('low calorie') && calories > 400) {
                    return false;
                  }
                  if (goal.contains('low fat') && fat > 15) return false;
                }
                return true;
              }).toList();
            }

            // Filter by selected ingredients from Pantry screen
            if (widget.selectedIngredientIds.isNotEmpty) {
              // Get the names of selected ingredients
              final selectedIngredientNames = widget.sharedIngredients
                  .where((ing) => widget.selectedIngredientIds.contains(ing.id))
                  .map((ing) => ing.name.toLowerCase().trim())
                  .toSet();

              // Filter recipes that contain at least one selected ingredient
              filteredRecipes = filteredRecipes.where((recipe) {
                final ingredientsList =
                    recipe['ingredients'] as List<dynamic>? ?? [];
                final ingredients = ingredientsList
                    .map((s) => s.toString().toLowerCase().trim())
                    .toList();

                // Check if recipe contains any selected ingredient
                return selectedIngredientNames.any(
                  (selected) => ingredients.any(
                    (recipeIng) =>
                        IngredientMatchService.ingredientMatches(recipeIng, selected),
                  ),
                );
              }).toList();

              // Sort to prioritize recipes with more selected ingredients
              filteredRecipes.sort((a, b) {
                final aIngredients = (a['ingredients'] as List<dynamic>? ?? [])
                    .map((e) => e.toString().toLowerCase().trim())
                    .toList();
                final bIngredients = (b['ingredients'] as List<dynamic>? ?? [])
                    .map((e) => e.toString().toLowerCase().trim())
                    .toList();

                int aMatches = 0, bMatches = 0;
                for (final selected in selectedIngredientNames) {
                  if (aIngredients.any(
                    (ing) => IngredientMatchService.ingredientMatches(ing, selected),
                  )) {
                    aMatches++;
                  }
                  if (bIngredients.any(
                    (ing) => IngredientMatchService.ingredientMatches(ing, selected),
                  )) {
                    bMatches++;
                  }
                }

                // Sort by number of matching selected ingredients (descending)
                return bMatches.compareTo(aMatches);
              });
            }

            _cachedFilteredRecipes = filteredRecipes;
            _lastFilterSignature = signature;

            // Reset pagination when filter changes
            _resetPagination(filteredRecipes);
          }

          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 0,
                backgroundColor: kBoneCreame,
                title: const Text('Potluck'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh Recipes',
                    onPressed: () {
                      setState(() {
                        _remoteRecipesFuture = _fetchRemoteRecipes(
                          forceRefresh: true,
                        );
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Post a Recipe',
                    onPressed: () async {
                      final newRecipe = await Navigator.push<Recipe>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RecipeEntryScreen(
                            pantryIngredients: widget.sharedIngredients,
                          ),
                        ),
                      );

                      if (newRecipe != null && mounted) {
                        // Use empty string for imageUrl since we're not using ImagenService
                        final imageUrl = '';
                        setState(() {
                          final aspectChoices = [0.85, 0.88, 0.9, 0.92, 0.95];
                          final ar =
                              aspectChoices[Random().nextInt(
                                aspectChoices.length,
                              )];
                          userRecipes.insert(0, {
                            'id': newRecipe.id,
                            'title': newRecipe.title,
                            'ingredients': newRecipe.ingredients,
                            'cookTime': newRecipe.cookTimeMinutes,
                            'rating': newRecipe.rating,
                            'reviews': newRecipe.reviewCount,
                            'imageUrl': imageUrl,
                            'aspectRatio': ar,
                            'authorName': newRecipe.authorName,
                          });
                        });
                      }
                    },
                  ),
                ],
                bottom: PreferredSize(
                  // Slightly tighter header so recipes start closer to the search bar
                  preferredSize: Size.fromHeight(
                    _hasActiveFilters() ? 152 : 112,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Segmented Control Toggle
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Container(
                          decoration: BoxDecoration(
                            color: kDeepForestGreen.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedFeed = 'forYou';
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _selectedFeed == 'forYou'
                                          ? kDeepForestGreen
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: _selectedFeed == 'forYou'
                                          ? [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.1,
                                                ),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : [],
                                    ),
                                    child: Text(
                                      'For You',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: _selectedFeed == 'forYou'
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: _selectedFeed == 'forYou'
                                            ? kBoneCreame
                                            : kDeepForestGreen.withOpacity(0.6),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedFeed = 'discover';
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _selectedFeed == 'discover'
                                          ? kDeepForestGreen
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: _selectedFeed == 'discover'
                                          ? [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.1,
                                                ),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : [],
                                    ),
                                    child: Text(
                                      'Discover',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: _selectedFeed == 'discover'
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: _selectedFeed == 'discover'
                                            ? kBoneCreame
                                            : kDeepForestGreen.withOpacity(0.6),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Search bar with symmetric gap above and below the filter chips
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push<Map<String, dynamic>>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AdvancedSearchScreen(
                                  userProfile: widget.userProfile,
                                  onApplyFilters: _onFiltersApplied,
                                ),
                              ),
                            );
                          },
                          child: AbsorbPointer(
                            child: TextField(
                              controller: _searchController,
                              onChanged: (value) {
                                setState(() {
                                  _searchQuery = value.toLowerCase();
                                });
                              },
                              decoration: InputDecoration(
                                hintText: 'Search recipes...',
                                prefixIcon: const Icon(
                                  Icons.search,
                                  color: Colors.grey,
                                ),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {
                                            _searchQuery = '';
                                          });
                                        },
                                      )
                                    : null,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: kDeepForestGreen,
                                    width: 2,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: kDeepForestGreen,
                                    width: 2,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: kDeepForestGreen,
                                    width: 2,
                                  ),
                                ),
                                filled: true,
                                fillColor: kBoneCreame.withOpacity(0.5),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: _buildFilterChips(),
                      ),
                    ],
                  ),
                ),
              ),
              // Dietary Restrictions Banner (dismissible)
              if (_showDietaryBanner &&
                  (widget.userProfile.allergies.isNotEmpty ||
                      widget.userProfile.avoided.isNotEmpty ||
                      widget.userProfile.selectedLifestyles.isNotEmpty))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: kDeepForestGreen.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: kDeepForestGreen.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: kDeepForestGreen,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Your Dietary Restrictions',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: kDeepForestGreen,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (widget
                                        .userProfile
                                        .allergies
                                        .isNotEmpty) ...[
                                      ...widget.userProfile.allergies.map(
                                        (allergy) => Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade50,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: Colors.red.shade200,
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Text(
                                            '⚠️ $allergy',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.red.shade700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (widget
                                        .userProfile
                                        .avoided
                                        .isNotEmpty) ...[
                                      ...widget.userProfile.avoided.map(
                                        (avoided) => Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.shade50,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: Colors.orange.shade200,
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Text(
                                            avoided,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.orange.shade700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (widget
                                        .userProfile
                                        .selectedLifestyles
                                        .isNotEmpty) ...[
                                      ...widget.userProfile.selectedLifestyles
                                          .map(
                                            (lifestyle) => Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: Colors.blue.shade200,
                                                  width: 0.5,
                                                ),
                                              ),
                                              child: Text(
                                                lifestyle,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.blue.shade700,
                                                ),
                                              ),
                                            ),
                                          ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DietaryHubScreen(
                                      userProfile: widget.userProfile,
                                      onProfileUpdated:
                                          widget.onProfileUpdated!,
                                    ),
                                  ),
                                ),
                                child: Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: kDeepForestGreen,
                                ),
                              ),
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _showDietaryBanner = false;
                                  });
                                },
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: kDeepForestGreen.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Selected Ingredients Filter Banner
              if (widget.selectedIngredientIds.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: kMutedGold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: kMutedGold.withOpacity(0.4),
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.filter_list, size: 20, color: kMutedGold),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Filtering by ${widget.selectedIngredientIds.length} selected ingredient${widget.selectedIngredientIds.length > 1 ? 's' : ''}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: kDeepForestGreen,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: widget.sharedIngredients
                                      .where(
                                        (ing) => widget.selectedIngredientIds
                                            .contains(ing.id),
                                      )
                                      .map(
                                        (ing) => Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: kMutedGold.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: kMutedGold.withOpacity(
                                                0.5,
                                              ),
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Text(
                                            ing.name,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: kDeepForestGreen,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              widget.onClearSelection?.call();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: kMutedGold.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: kDeepForestGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (isLoading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Finding recipes that match your pantry...'),
                      ],
                    ),
                  ),
                ),
              if (remoteError != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kSoftTerracotta.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        remoteError,
                        style: const TextStyle(color: kSoftTerracotta),
                      ),
                    ),
                  ),
                ),
              // Recipe grid with items
              if (widget.sharedIngredients.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_bag_outlined,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Add ingredients to get started!',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Browse all recipes or add items from your pantry',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: Padding(
                    // Remove extra top padding so recipes sit right under the header/banners
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: MasonryGridView.count(
                      // For You = 1 column; Discover = 2 columns
                      crossAxisCount: _selectedFeed == 'forYou' ? 1 : 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: _selectedFeed == 'forYou' ? 0 : 16,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _displayedRecipes.length,
                      itemBuilder: (context, index) {
                        final recipe = _displayedRecipes[index];
                        final ingredientsList =
                            recipe['ingredients'] as List<dynamic>? ?? [];
                        final ingredients = ingredientsList
                            .map((e) => e.toString())
                            .toList();

                        // Smart image URL: use existing URL if valid, otherwise use curated fallback
                        final recipeTitle = recipe['title'] as String;
                        final rawImageUrl = recipe['imageUrl'] as String?;
                        final imageUrl =
                            (rawImageUrl != null && rawImageUrl.isNotEmpty)
                            ? rawImageUrl
                            : ''; // No fallback - show no image

                        // Compute real rating & review count from community reviews
                        final recipeId = recipe['id'] as String;
                        final recipeReviews = widget.communityReviews
                            .where((r) => r.recipeId == recipeId)
                            .toList();
                        final realReviewCount = recipeReviews.length;
                        final realRating = realReviewCount > 0
                            ? recipeReviews
                                      .map((r) => r.rating)
                                      .reduce((a, b) => a + b) /
                                  realReviewCount
                            : 0.0; // Show 0 stars when no reviews

                        return RecipeCard(
                          sharedIngredients: widget.sharedIngredients,
                          onIngredientsUpdated: widget.onIngredientsUpdated,
                          recipeTitle: recipeTitle,
                          recipeIngredients: ingredients,
                          cookTime: recipe['cookTime'] as int,
                          rating: realRating.toDouble(),
                          reviewCount: realReviewCount,
                          matchPercentage: _getRecipeMatchPercentage(
                            ingredients,
                          ),
                          nutrition: recipe['nutrition'] != null
                              ? (recipe['nutrition'] is Nutrition
                                    ? recipe['nutrition'] as Nutrition
                                    : Nutrition.fromMap(
                                        (recipe['nutrition']
                                            as Map<String, dynamic>),
                                      ))
                              : null,
                          instructions:
                              (recipe['instructions'] as List<dynamic>?)
                                  ?.map((e) => e.toString())
                                  .toList() ??
                              [],
                          missingCount: _getMissingIngredientsCount(
                            ingredients,
                          ),
                          missingIngredients: _getMissingIngredients(
                            ingredients,
                          ),
                          isReadyToCook: _isReadyToCook(ingredients),
                          isRecommendation: false,
                          onTap: (context) => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RecipeDetailPage(
                                sharedIngredients: widget.sharedIngredients,
                                onIngredientsUpdated: widget.onIngredientsUpdated,
                                recipeTitle: recipeTitle,
                                recipeIngredients: ingredients,
                                ingredientMeasurements:
                                    (recipe['ingredientMeasurements']
                                            as Map<String, dynamic>?)
                                        ?.cast<String, String>() ??
                                    {},
                                userProfile: widget.userProfile,
                                onProfileUpdated: widget.onProfileUpdated,
                                recipeId: recipe['id'] as String,
                                onAddCommunityReview: widget.onAddCommunityReview,
                                reviews: widget.communityReviews
                                    .where((r) =>
                                        r.recipeId == (recipe['id'] as String))
                                    .toList(),
                                imageUrl: imageUrl,
                                cookTime: recipe['cookTime'] as int,
                                rating: realRating.toDouble(),
                                nutrition: recipe['nutrition'] != null
                                    ? (recipe['nutrition'] is Nutrition
                                          ? recipe['nutrition'] as Nutrition
                                          : Nutrition.fromMap(
                                              (recipe['nutrition']
                                                  as Map<String, dynamic>),
                                            ))
                                    : null,
                                instructions:
                                    (recipe['instructions'] as List<dynamic>?)
                                        ?.map((e) => e.toString())
                                        .toList() ??
                                    [],
                                sourceUrl: recipe['sourceUrl'] as String?,
                                defaultServings:
                                    (recipe['servings'] as int?) ?? 4,
                                dismissedRestockIds: widget.dismissedRestockIds,
                              ),
                            ),
                          ),
                          ensureRecipeImageCached:
                              (recipeId, imageUrl) async {
                            if (imageUrl == null ||
                                imageUrl.isEmpty ||
                                imageUrl.startsWith('/')) return;
                            try {
                              final localImagePath = await RecipeImageFileService
                                  .downloadAndSaveImage(
                                imageUrl: imageUrl,
                                recipeId: recipeId,
                              );
                              if (localImagePath == null) return;
                              final fetchedIndex = RecipeFeedScreenState
                                  .fetchedRecipesCache
                                  .indexWhere((r) => r['id'] == recipeId);
                              if (fetchedIndex != -1) {
                                RecipeFeedScreenState
                                    .fetchedRecipesCache[fetchedIndex]['imageUrl'] =
                                    localImagePath;
                              }
                              final userIndex = RecipeFeedScreenState
                                  .userRecipes
                                  .indexWhere((r) => r['id'] == recipeId);
                              if (userIndex != -1) {
                                RecipeFeedScreenState
                                    .userRecipes[userIndex]['imageUrl'] =
                                    localImagePath;
                              }
                            } catch (_) {}
                          },
                          onEditRecipe: (recipe['authorName'] ?? '') == 'You'
                              ? (context) {
                                  final recipeMap = RecipeFeedScreenState
                                      .userRecipes
                                      .firstWhere(
                                        (r) => r['id'] == recipe['id'],
                                        orElse: () => <String, dynamic>{},
                                      );
                                  if (recipeMap.isEmpty) return;
                                  final r = Recipe(
                                    id: recipeMap['id'],
                                    title: recipeMap['title'],
                                    imageUrl: recipeMap['imageUrl'] ?? '',
                                    ingredients: recipeMap['ingredients'],
                                    ingredientTags: {},
                                    cookTimeMinutes:
                                        recipeMap['cookTime'] ?? 30,
                                    rating: recipeMap['rating'] ?? 4.0,
                                    reviewCount: recipeMap['reviews'] ?? 0,
                                    createdDate: DateTime.now(),
                                    isSaved: false,
                                    mealTypes: ['lunch'],
                                    proteinGrams: 0,
                                    authorName:
                                        recipeMap['authorName'] ?? 'Anonymous',
                                    aspectRatio:
                                        recipeMap['aspectRatio'] ?? 1.0,
                                  );
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => RecipeEntryScreen(
                                        pantryIngredients:
                                            widget.sharedIngredients,
                                        existingRecipe: r,
                                      ),
                                    ),
                                  );
                                }
                              : null,
                          userProfile: widget.userProfile,
                          onProfileUpdated: widget.onProfileUpdated,
                          recipeId: recipe['id'] as String,
                          imageUrl: imageUrl,
                          ingredientMeasurements:
                              (recipe['ingredientMeasurements']
                                      as Map<String, dynamic>?)
                                  ?.cast<String, String>() ??
                              {},
                          aspectRatio: _selectedFeed == 'forYou'
                              ? 1.0
                              : (recipe['aspectRatio'] as double?) ?? 1.0,
                          isAuthor: (recipe['authorName'] ?? '') == 'You',
                          onAddCommunityReview: widget.onAddCommunityReview,
                          communityReviews: widget.communityReviews,
                          sourceUrl: recipe['sourceUrl'] as String?,
                          defaultServings: (recipe['servings'] as int?) ?? 4,
                          dismissedRestockIds: widget.dismissedRestockIds,
                          authorName: recipe['authorName'] as String?,
                          authorAvatar: recipe['authorAvatar'] as String?,
                          authorId: recipe['authorId'] as String?,
                          isDiscoverFeed: _selectedFeed == 'discover',
                          onFollowAuthor: widget.onFollowAuthor,
                          isFollowing: widget.isFollowingAuthor(
                            recipe['authorId'] as String?,
                          ),
                          onDelete: (id) {
                            setState(() {
                              userRecipes.removeWhere((r) => r['id'] == id);
                            });
                          },
                        );
                      },
                    ),
                  ),
                ),
              // Loading indicator for infinite scroll
              if (_isLoadingMore)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kDeepForestGreen,
                        ),
                      ),
                    ),
                  ),
                ),
              // "Load more" message or end of list
              if (!_isLoadingMore &&
                  _hasMoreRecipes &&
                  _displayedRecipes.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'Scroll for more recipes',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              // Bottom padding for navigation bar
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
    );
  }
}


// ================= RESTOCK SELECTION DIALOG =================
class _RestockSelectionDialog extends StatefulWidget {
  final List<String> recipeIngredients;

  const _RestockSelectionDialog({required this.recipeIngredients});

  @override
  State<_RestockSelectionDialog> createState() =>
      _RestockSelectionDialogState();
}

class _RestockSelectionDialogState extends State<_RestockSelectionDialog> {
  final Set<String> _selectedIngredients = {};

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: kBoneCreame,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kDeepForestGreen,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    'Kitchen Check:',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Lora',
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Need to restock anything?',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
            // Ingredient list
            Flexible(
              child: Scrollbar(
                thumbVisibility: true,
                thickness: 6,
                radius: const Radius.circular(3),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.recipeIngredients.length,
                  itemBuilder: (context, index) {
                    final ingredient = widget.recipeIngredients[index];
                    final isSelected = _selectedIngredients.contains(
                      ingredient,
                    );

                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            _selectedIngredients.add(ingredient);
                          } else {
                            _selectedIngredients.remove(ingredient);
                          }
                        });
                      },
                      title: Text(
                        ingredient[0].toUpperCase() + ingredient.substring(1),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: kDeepForestGreen,
                        ),
                      ),
                      activeColor: kDeepForestGreen,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 0,
                      ),
                      dense: true,
                    );
                  },
                ),
              ),
            ),
            // Action buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kBoneCreame,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop(<String>{});
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade700),
                        backgroundColor: Colors.grey.shade100,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop(_selectedIngredients);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kDeepForestGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      child: Text(
                        _selectedIngredients.isEmpty
                            ? 'Done'
                            : 'Add to Restock (${_selectedIngredients.length})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  late bool _isSaved;
  final GlobalKey _reviewsKey = GlobalKey();
  static const int _initialReviewsToShow = 1;
  // Track which reviews the current user has liked locally
  final Set<String> _likedReviewIds = {};
  // Track which replies the current user has liked locally
  final Set<String> _likedReplyIds = {};
  // Track which reviews' replies are expanded
  final Set<String> _expandedReviewIds = {};
  // Reference to modal's setState for rebuilding when replies are added
  StateSetter? _modalSetState;
  // Serving size selection
  late int _selectedServings;

  // Real instructions fetched via RecipeInstructionService
  List<String> _realInstructions = [];
  bool _isLoadingInstructions = true;
  String? _instructionError;

  // Real ingredients with measurements fetched via RecipeIngredientService
  Map<String, String> _realIngredientMeasurements = {};
  bool _isLoadingIngredients = true;

  // US/Metric toggle for ingredient measurements
  bool _useMetric = false;

  Future<void> _openSourceUrl() async {
    var url = widget.sourceUrl?.trim() ?? '';
    if (url.isEmpty) return;
    if (!url.contains('://')) {
      url = 'https://$url';
    }
    final uri = Uri.tryParse(Uri.encodeFull(url));
    if (uri == null) return;

    try {
      // Try launching directly — skip canLaunchUrl to avoid iOS channel errors
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        // Unable to open link
      }
    } catch (e) {
      // Platform channel not ready or other error — show friendly message
      if (!mounted) return;
    }
  }

  @override
  void initState() {
    super.initState();
    _isSaved =
        widget.userProfile != null &&
        widget.recipeId != null &&
        widget.userProfile!.savedRecipeIds.contains(widget.recipeId);
    _selectedServings = widget.defaultServings;
    // Use consolidated service for BOTH measurements and instructions in ONE API call
    _fetchRecipeData();
  }

  /// Fetch both measurements and instructions in a single Gemini API call.
  /// This saves API quota by combining two requests into one.
  Future<void> _fetchRecipeData() async {
    if (widget.recipeId == null) {
      setState(() {
        _isLoadingIngredients = false;
        _isLoadingInstructions = false;
      });
      return;
    }

    try {
      final data = await RecipeDataService.getRecipeData(
        recipeId: widget.recipeId!,
        title: widget.recipeTitle,
        ingredients: deduplicateIngredients(widget.recipeIngredients),
        existingMeasurements: widget.ingredientMeasurements,
        sourceUrl: widget.sourceUrl,
      );

      if (mounted) {
        setState(() {
          _realIngredientMeasurements = data.measurements;
          _realInstructions = data.instructions;
          _isLoadingIngredients = false;
          _isLoadingInstructions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _instructionError = e.toString();
          _isLoadingIngredients = false;
          _isLoadingInstructions = false;
        });
      }
    }
  }

  Future<void> _toggleSaveRecipe() async {
    if (widget.userProfile == null || widget.recipeId == null) return;

    setState(() {
      _isSaved = !_isSaved;
    });

    final updatedSavedIds = Set<String>.from(
      widget.userProfile!.savedRecipeIds,
    );

    if (_isSaved) {
      updatedSavedIds.add(widget.recipeId!);
    } else {
      updatedSavedIds.remove(widget.recipeId!);
    }

    final updatedProfile = widget.userProfile!.copyWith(
      savedRecipeIds: updatedSavedIds.toList(),
    );

    widget.onProfileUpdated?.call(updatedProfile);
  }

  Future<void> _onMadeThis() async {
    // Show dialog to let user select which ingredients to restock
    final selectedIngredients = await showDialog<Set<String>>(
      context: context,
      builder: (BuildContext context) {
        return _RestockSelectionDialog(
          recipeIngredients: widget.recipeIngredients,
        );
      },
    );

    // If user cancelled, do nothing
    if (selectedIngredients == null) return;

    // Move selected ingredients to restock (set needsPurchase = true)
    final updatedIngredients = List<Ingredient>.from(widget.sharedIngredients);

    for (final selectedIngredient in selectedIngredients) {
      final selectedLower = selectedIngredient.toLowerCase().trim();

      // Find matching pantry ingredient using fuzzy matching
      for (int i = 0; i < updatedIngredients.length; i++) {
        final pantryNameLower = updatedIngredients[i].name.toLowerCase().trim();

        if (selectedLower == pantryNameLower ||
            selectedLower.contains(pantryNameLower) ||
            pantryNameLower.contains(selectedLower)) {
          // Mark as needs purchase by setting amount to 0 (moves to restock tab)
          updatedIngredients[i] = updatedIngredients[i].copyWith(
            amount: switch (updatedIngredients[i].unitType) {
              UnitType.volume => 0.0,
              UnitType.count => 0,
              UnitType.weight => 0,
            },
          );
          break;
        }
      }
    }

    widget.onIngredientsUpdated(updatedIngredients);

    // Add recipe to cookedRecipeIds if not already present
    if (widget.userProfile != null && widget.recipeId != null) {
      final cookedIds = List<String>.from(widget.userProfile!.cookedRecipeIds);
      if (!cookedIds.contains(widget.recipeId!)) {
        cookedIds.add(widget.recipeId!);

        final updatedProfile = widget.userProfile!.copyWith(
          cookedRecipeIds: cookedIds,
        );

        widget.onProfileUpdated?.call(updatedProfile);
      }
    }

    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selectedIngredients.isEmpty
                ? 'Recipe marked as cooked!'
                : 'Recipe marked as cooked! ${selectedIngredients.length} item${selectedIngredients.length > 1 ? 's' : ''} moved to restock.',
          ),
          backgroundColor: kDeepForestGreen,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use real AI-extracted instructions, fall back to widget.instructions
    final displayInstructions = _realInstructions.isNotEmpty
        ? _realInstructions
        : (widget.instructions.isNotEmpty ? widget.instructions : <String>[]);
    final sourceUrl = widget.sourceUrl?.trim() ?? '';
    final hasSourceUrl = sourceUrl.isNotEmpty;
    final sourceHost = Uri.tryParse(sourceUrl)?.host ?? '';

    return Scaffold(
      backgroundColor: kBoneCreame,
      appBar: AppBar(
        backgroundColor: kBoneCreame,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kDeepForestGreen),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.recipeTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: kDeepForestGreen,
            fontFamily: 'Lora',
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (widget.userProfile != null && widget.recipeId != null) ...[
            IconButton(
              icon: const Icon(Icons.ios_share, color: kDeepForestGreen),
              onPressed: () async {
                // Use a standard URL format that Messages will recognize
                final shareText =
                    '${widget.recipeTitle}\n\nView this recipe: https://potluck.app/recipes/${widget.recipeId}';

                // Compute safe origin rect for iPad/Tablet popovers
                Rect shareOrigin = Rect.zero;
                try {
                  final RenderBox? box =
                      context.findRenderObject() as RenderBox?;
                  if (box != null) {
                    shareOrigin = box.localToGlobal(Offset.zero) & box.size;
                  }
                } catch (_) {
                  shareOrigin = Rect.zero;
                }

                try {
                  XFile? xImage;

                  // Get the same image URL that's used in the potluck feed
                  final feedImageUrl =
                      (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
                      ? widget.imageUrl!
                      : ''; // No fallback - show no image

                  // Try to get image from local file path
                  if (feedImageUrl.startsWith('/')) {
                    final file = File(feedImageUrl);
                    if (await file.exists()) {
                      xImage = XFile(
                        file.path,
                        name: 'recipe_${widget.recipeId}.jpg',
                        mimeType: 'image/jpeg',
                      );
                    }
                  }

                  // Try to download network image (including curated Pexels URLs)
                  if (xImage == null &&
                      feedImageUrl.isNotEmpty &&
                      (feedImageUrl.startsWith('http://') ||
                          feedImageUrl.startsWith('https://'))) {
                    HttpClient? httpClient;
                    try {
                      httpClient = HttpClient();
                      final request = await httpClient.getUrl(
                        Uri.parse(feedImageUrl),
                      );
                      final response = await request.close();
                      if (response.statusCode == 200) {
                        final bytes = await response.fold<List<int>>(<int>[], (
                          prev,
                          el,
                        ) {
                          prev.addAll(el);
                          return prev;
                        });

                        xImage = XFile.fromData(
                          Uint8List.fromList(bytes),
                          name: 'recipe_${widget.recipeId}.jpg',
                          mimeType: 'image/jpeg',
                        );
                      }
                    } finally {
                      httpClient?.close(force: true);
                    }
                  }

                  // Try to share image + text first
                  if (xImage != null) {
                    await Share.shareXFiles(
                      [xImage],
                      subject: widget.recipeTitle,
                      text: shareText,
                      sharePositionOrigin: shareOrigin,
                    );
                  } else {
                    // Fallback: share text only
                    await Share.share(
                      shareText,
                      subject: widget.recipeTitle,
                      sharePositionOrigin: shareOrigin,
                    );
                  }
                } catch (e) {
                  // Final fallback: copy to clipboard
                  try {
                    await Clipboard.setData(ClipboardData(text: shareText));
                  } catch (_) {}
                }
              },
            ),
            IconButton(
              icon: Icon(
                _isSaved ? Icons.favorite : Icons.favorite_outline,
                color: kDeepForestGreen,
              ),
              onPressed: _toggleSaveRecipe,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Recipe Image Hero
            Container(
              height: 280,
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: widget.imageUrl != null && widget.imageUrl!.isNotEmpty
                    ? (widget.imageUrl!.startsWith('/')
                          ? Image.file(
                              File(widget.imageUrl!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  _buildPlaceholderImage(),
                            )
                          : Image.network(
                              widget.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  _buildPlaceholderImage(),
                            ))
                    : _buildPlaceholderImage(),
              ),
            ),
            const SizedBox(height: 24),

            // Recipe Title and Meta
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.recipeTitle,
                    style: const TextStyle(
                      fontFamily: 'Lora',
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: kDeepForestGreen,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Cook time and rating row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: kDeepForestGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.access_time,
                              size: 16,
                              color: kDeepForestGreen,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formatCookTime(widget.cookTime),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: kDeepForestGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: kMutedGold.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, size: 16, color: kMutedGold),
                            const SizedBox(width: 4),
                            Text(
                              widget.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: kDeepForestGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Recipe Complete Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _onMadeThis,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kDeepForestGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Mark as Cooked',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Ingredients Section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 248, 243, 234),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: kDeepForestGreen.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.shopping_basket,
                                color: kDeepForestGreen,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Ingredients',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Lora',
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: kDeepForestGreen,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Header row with servings selector and US/Metric switch
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              // Left column: Serving size selector (flex: 3)
                              Expanded(
                                flex: 3,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kDeepForestGreen.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: kDeepForestGreen.withOpacity(
                                          0.2,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        GestureDetector(
                                          onTap: _selectedServings > 1
                                              ? () {
                                                  setState(() {
                                                    _selectedServings--;
                                                  });
                                                }
                                              : null,
                                          child: Icon(
                                            Icons.remove,
                                            size: 18,
                                            color: _selectedServings > 1
                                                ? kDeepForestGreen
                                                : Colors.grey.shade400,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          child: Text(
                                            '$_selectedServings servings',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: kDeepForestGreen,
                                            ),
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _selectedServings++;
                                            });
                                          },
                                          child: const Icon(
                                            Icons.add,
                                            size: 18,
                                            color: kDeepForestGreen,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              // Gutter
                              const SizedBox(width: 16),
                              // Right column: US/Metric switch (flex: 2)
                              Expanded(
                                flex: 2,
                                child: Container(
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Stack(
                                    children: [
                                      // Sliding selection background
                                      AnimatedPositioned(
                                        duration: const Duration(
                                          milliseconds: 250,
                                        ),
                                        curve: Curves.easeInOut,
                                        left: _useMetric ? null : 0,
                                        right: _useMetric ? 0 : null,
                                        top: 2,
                                        bottom: 2,
                                        width: 60,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: kDeepForestGreen,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // US segment
                                      Positioned(
                                        left: 0,
                                        top: 0,
                                        bottom: 0,
                                        width: 60,
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _useMetric = false;
                                            });
                                          },
                                          child: Center(
                                            child: Text(
                                              'US',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: _useMetric
                                                    ? FontWeight.w500
                                                    : FontWeight.w700,
                                                color: _useMetric
                                                    ? Colors.grey.shade600
                                                    : Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Metric segment
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        bottom: 0,
                                        width: 60,
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _useMetric = true;
                                            });
                                          },
                                          child: Center(
                                            child: Text(
                                              'Metric',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: _useMetric
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                color: _useMetric
                                                    ? Colors.white
                                                    : Colors.grey.shade600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: widget.recipeIngredients.length,
                          itemBuilder: (context, index) {
                            final ingredient = widget.recipeIngredients[index];

                            // Filter out empty ingredient names
                            if (ingredient.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            final haveIt =
                                IngredientMatchService.isBasicStaple(ingredient) ||
                                widget.sharedIngredients.any((ing) {
                                  final nameMatch =
                                      IngredientMatchService.ingredientMatches(
                                        ingredient,
                                        ing.name,
                                      );
                                  final hasQuantity =
                                      ing.amount != null &&
                                      (ing.unitType == UnitType.volume
                                          ? (ing.amount as double) > 0
                                          : amountAsDouble(ing.amount) > 0);
                                  return nameMatch && hasQuantity;
                                });

                            // Get clean measurement from API and format with fractions
                            // E.g., "1/2 cup", "2 1/3 cups", etc.
                            // Scale by serving size
                            // Prefer Gemini-fetched measurements over Edamam
                            String rawMeasurement;
                            if (_isLoadingIngredients) {
                              rawMeasurement =
                                  widget.ingredientMeasurements[ingredient] ??
                                  '1 serving';
                            } else {
                              // Try exact match first (case-insensitive)
                              final ingredientLower = ingredient
                                  .toLowerCase()
                                  .trim();
                              rawMeasurement =
                                  _realIngredientMeasurements[ingredientLower] ??
                                  // Try partial match if exact match fails
                                  _findPartialMeasurementMatch(
                                    ingredientLower,
                                    _realIngredientMeasurements,
                                  ) ??
                                  // Fall back to Edamam measurements
                                  widget.ingredientMeasurements[ingredient] ??
                                  '1 serving';
                            }
                            String displayMeasurement;
                            final numMatch = RegExp(
                              r'([\d./]+(?:\s+[\d./]+)?)',
                            ).firstMatch(rawMeasurement);
                            if (numMatch != null) {
                              final matchedNum = numMatch.group(1)!.trim();
                              // Parse fraction or mixed number
                              double baseValue;
                              if (matchedNum.contains('/')) {
                                final parts = matchedNum.split(RegExp(r'\s+'));
                                double whole = 0;
                                String fractionPart = matchedNum;
                                if (parts.length == 2) {
                                  whole = double.tryParse(parts[0]) ?? 0;
                                  fractionPart = parts[1];
                                }
                                final fracParts = fractionPart.split('/');
                                if (fracParts.length == 2) {
                                  final num =
                                      double.tryParse(fracParts[0]) ?? 0;
                                  final den =
                                      double.tryParse(fracParts[1]) ?? 1;
                                  baseValue = whole + (den > 0 ? num / den : 0);
                                } else {
                                  baseValue =
                                      double.tryParse(matchedNum) ?? 1.0;
                                }
                              } else {
                                baseValue = double.tryParse(matchedNum) ?? 1.0;
                              }
                              final scaledValue =
                                  baseValue *
                                  _selectedServings /
                                  widget.defaultServings;

                              // Extract unit from raw measurement and abbreviate it
                              // Remove the number part to get just the unit
                              final unitPart = rawMeasurement
                                  .replaceFirst(RegExp(r'[\d./\s]+'), '')
                                  .trim();

                              // Convert to metric if toggle is on
                              double finalValue = scaledValue;
                              String finalUnit = unitPart;
                              if (_useMetric && unitPart.isNotEmpty) {
                                final converted = convertToMetric(
                                  scaledValue,
                                  unitPart,
                                );
                                finalValue = converted.$1;
                                finalUnit = converted.$2;
                              }

                              final abbreviatedUnit = finalUnit.isNotEmpty
                                  ? abbreviateUnit(finalUnit)
                                  : '';

                              // Format the value - use fractions for US, decimals for metric
                              String formattedValue;
                              if (_useMetric) {
                                formattedValue = finalValue >= 10
                                    ? finalValue.round().toString()
                                    : finalValue.toStringAsFixed(
                                        finalValue.truncateToDouble() ==
                                                finalValue
                                            ? 0
                                            : 1,
                                      );
                              } else {
                                formattedValue = decimalToFraction(finalValue);
                              }

                              displayMeasurement = abbreviatedUnit.isNotEmpty
                                  ? '$formattedValue $abbreviatedUnit'
                                  : formattedValue;
                            } else {
                              // No number found — use raw measurement with abbreviation
                              final parts = rawMeasurement.trim().split(
                                RegExp(r'\s+'),
                              );
                              if (parts.length >= 2) {
                                final unitPart = parts.sublist(1).join(' ');
                                final abbreviatedUnit = abbreviateUnit(
                                  unitPart,
                                );
                                displayMeasurement =
                                    '${parts[0]} $abbreviatedUnit';
                              } else {
                                displayMeasurement = rawMeasurement.trim();
                              }
                            }

                            final isLast =
                                index == widget.recipeIngredients.length - 1;

                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      // Left Column: Ingredient Names (flex: 3)
                                      Expanded(
                                        flex: 3,
                                        child: Row(
                                          children: [
                                            Icon(
                                              haveIt
                                                  ? Icons.check_circle
                                                  : Icons.circle_outlined,
                                              color: haveIt
                                                  ? kSageGreen
                                                  : kSoftTerracotta,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                ingredient.capitalize(),
                                                textAlign: TextAlign.left,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: haveIt
                                                      ? kDeepForestGreen
                                                      : kSoftTerracotta,
                                                  fontWeight: haveIt
                                                      ? FontWeight.w500
                                                      : FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Gutter
                                      const SizedBox(width: 16),
                                      // Right Column: Measurements (flex: 2)
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          displayMeasurement,
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Divider (except after last item)
                                if (!isLast)
                                  Divider(
                                    height: 1,
                                    color: Colors.grey.shade300,
                                    thickness: 0.5,
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Nutrition Section removed from here and will be shown
                  // below the "How to Make" instructions to improve flow.

                  // Instructions Section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 248, 243, 234),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: kMutedGold.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.menu_book,
                                color: kMutedGold,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'How to Make',
                              style: TextStyle(
                                fontFamily: 'Lora',
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: kDeepForestGreen,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Show loading spinner while fetching real instructions
                        if (_isLoadingInstructions) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: kDeepForestGreen,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Loading instructions...',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: kSoftSlateGray,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (_instructionError != null &&
                            _realInstructions.isEmpty &&
                            widget.instructions.isEmpty) ...[
                          // Error state with retry
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Column(
                              children: [
                                Text(
                                  'Could not load instructions.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: kSoftSlateGray,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _isLoadingInstructions = true;
                                      _instructionError = null;
                                    });
                                    _fetchRecipeData();
                                  },
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('Retry'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: kDeepForestGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          // Show instruction steps
                          ...displayInstructions.asMap().entries.map((entry) {
                            return _buildInstructionStep(
                              entry.key + 1,
                              entry.value,
                            );
                          }),
                        ],
                        // Source link at the bottom of instructions
                        if (hasSourceUrl) ...[
                          const SizedBox(height: 16),
                          Center(
                            child: TextButton.icon(
                              onPressed: _openSourceUrl,
                              icon: Icon(
                                Icons.open_in_new,
                                size: 16,
                                color: kDeepForestGreen.withOpacity(0.7),
                              ),
                              label: Text(
                                'View original on ${sourceHost.isNotEmpty ? sourceHost : "source site"}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: kDeepForestGreen.withOpacity(0.7),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  // Canonical NutritionSummaryBar relocated here (below instructions)
                  if (widget.nutrition != null) ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 248, 243, 234),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: kMutedGold.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.local_dining,
                                  color: kMutedGold,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Nutrition Facts',
                                style: TextStyle(
                                  fontFamily: 'Lora',
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: kDeepForestGreen,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          NutritionSummaryBar(
                            nutrition: widget.nutrition!,
                            servingMultiplier:
                                _selectedServings / widget.defaultServings,
                          ),
                          const SizedBox(height: 12),
                          ExpansionTile(
                            title: const Text(
                              'Additional Nutritional Info',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: kDeepForestGreen,
                              ),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                                child: CompactNutritionDetails(
                                  nutrition: widget.nutrition!,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Duplicate nutrition block removed — canonical NutritionSummaryBar shown earlier

                  // Reviews (always visible)
                  Container(
                    key: _reviewsKey,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 248, 243, 234),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: kSageGreen.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.rate_review,
                                color: kSageGreen,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Reviews',
                              style: TextStyle(
                                fontFamily: 'Lora',
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: kDeepForestGreen,
                              ),
                            ),
                          ],
                        ),

                        // (Sticky Show Less will be shown inside the expanded review list)

                        // Community images (if any)
                        if (widget.reviews.any(
                          (r) => r.imageUrl != null && r.imageUrl!.isNotEmpty,
                        )) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 100,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: widget.reviews
                                  .where(
                                    (r) =>
                                        r.imageUrl != null &&
                                        r.imageUrl!.isNotEmpty,
                                  )
                                  .length,
                              itemBuilder: (context, index) {
                                final review = widget.reviews
                                    .where(
                                      (r) =>
                                          r.imageUrl != null &&
                                          r.imageUrl!.isNotEmpty,
                                    )
                                    .toList()[index];
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: _buildCommunityDishThumbnail(review),
                                );
                              },
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),
                        // Review cards or empty state
                        if (widget.reviews.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text(
                                'No reviews yet. Be the first to share!',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: kSoftSlateGray,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          )
                        else ...[
                          // Use SIMPLE review cards here (no Reply button)
                          // Reply functionality is ONLY available in Show All modal
                          ..._buildSimpleReviewCards(),

                          // Show All opens bottom drawer (short underline centered)
                          const SizedBox(height: 12),
                          if (widget.reviews.length > _initialReviewsToShow)
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: _openReviewsDrawer,
                                  style: TextButton.styleFrom(
                                    foregroundColor: kDeepForestGreen,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                  ),
                                  child: const Text('Show All'),
                                ),
                                Center(
                                  child: Container(
                                    margin: const EdgeInsets.only(top: 2),
                                    width: 64,
                                    height: 2,
                                    decoration: BoxDecoration(
                                      color: kDeepForestGreen,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],

                        const SizedBox(height: 16),
                        // Write a Review button (always visible) - filled with white text
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _openReviewModal,
                            icon: const Icon(Icons.edit, size: 18),
                            label: const Text('Write a Review'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kDeepForestGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 100), // Bottom padding for nav bar
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Builder(
        builder: (context) {
          final shoppingListCount = widget.sharedIngredients
              .where(
                (ing) =>
                    ing.needsPurchase &&
                    !widget.dismissedRestockIds.contains(ing.id),
              )
              .length;

          return SizedBox(
            height: 80, // Fixed height to match main navigation
            child: PotluckNavigationBar(
              currentIndex: 1,
              onTap: (index) {
                // Close detail and return to root so main navigation becomes visible.
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              shoppingListCount: shoppingListCount,
            ),
          );
        },
      ),
    );
  }

  /// Find a measurement match for an ingredient using partial/fuzzy matching
  String? _findPartialMeasurementMatch(
    String ingredientLower,
    Map<String, String> measurements,
  ) {
    // Try to find a key that contains the ingredient name or vice versa
    for (final entry in measurements.entries) {
      final key = entry.key.toLowerCase().trim();

      // Exact match
      if (key == ingredientLower) {
        return entry.value;
      }

      // Partial match - ingredient contains key or key contains ingredient
      if (ingredientLower.contains(key) || key.contains(ingredientLower)) {
        return entry.value;
      }

      // Word-based matching - check if any significant words match
      final ingredientWords = ingredientLower.split(RegExp(r'\s+'));
      final keyWords = key.split(RegExp(r'\s+'));

      for (final iWord in ingredientWords) {
        if (iWord.length < 3) continue; // Skip short words
        for (final kWord in keyWords) {
          if (kWord.length < 3) continue;
          if (iWord == kWord ||
              iWord.contains(kWord) ||
              kWord.contains(iWord)) {
            return entry.value;
          }
        }
      }
    }

    return null;
  }

  Widget _buildPlaceholderImage() {
    return Container(
      color: kBoneCreame,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.restaurant,
              size: 60,
              color: kDeepForestGreen.withOpacity(0.3),
            ),
            const SizedBox(height: 8),
            Text(
              'Delicious awaits!',
              style: TextStyle(
                color: kDeepForestGreen.withOpacity(0.5),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionStep(int stepNumber, String instruction) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: kDeepForestGreen,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                '$stepNumber',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              instruction,
              style: const TextStyle(
                fontSize: 15,
                color: kSoftSlateGray,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityDishThumbnail(CommunityReview review) {
    return GestureDetector(
      onTap: () => _showFullScreenImage(review),
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Image.file(
                File(review.imageUrl!),
                fit: BoxFit.cover,
                width: 120,
                height: 120,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 120,
                  height: 120,
                  color: Colors.grey.shade300,
                  child: const Icon(
                    Icons.image_not_supported,
                    color: Colors.grey,
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.white,
                  child: Text(
                    review.userName.isNotEmpty
                        ? review.userName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: kDeepForestGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullScreenImage(CommunityReview review) {
    final imageReviews = widget.reviews
        .where((r) => r.imageUrl != null && r.imageUrl!.isNotEmpty)
        .toList();
    final initialIndex = imageReviews.indexWhere((r) => r.id == review.id);
    final pageController = PageController(initialPage: initialIndex);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.black,
        child: PageView.builder(
          controller: pageController,
          itemCount: imageReviews.length,
          itemBuilder: (context, pageIndex) {
            final currentReview = imageReviews[pageIndex];
            return Stack(
              children: [
                Center(
                  child: Image.file(
                    File(currentReview.imageUrl!),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.image_not_supported,
                      color: Colors.white,
                      size: 50,
                    ),
                  ),
                ),
                Positioned(
                  top: 40,
                  right: 20,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              currentReview.userName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Row(
                              children: List.generate(5, (index) {
                                return Icon(
                                  index < currentReview.rating
                                      ? Icons.star
                                      : Icons.star_border,
                                  size: 16,
                                  color: kMutedGold,
                                );
                              }),
                            ),
                          ],
                        ),
                        if (currentReview.comment.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            currentReview.comment,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          _formatDate(currentReview.createdDate),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ========== ARCHITECTURAL SEPARATION ==========
  // This class maintains strict separation of review rendering logic:
  //
  // 1. MAIN DETAIL PAGE (simple preview - NO reply functionality):
  //    - Uses _buildSimpleReviewCards() → _buildSimpleReviewCard()
  //    - Shows comment only - NO Reply button, NO reply counts
  //    - Users must click "Show All" to access reply functionality
  //
  // 2. SHOW ALL MODAL VIEW (full-featured):
  //    - _openReviewsDrawer() → _buildReviewCard() → complete review with replies
  //    - _buildReviewCard() contains Reply button, Show/Hide toggle, reply rendering
  //    - ONLY location where Reply button and reply functionality exists
  //
  // Recipe Card (feed preview) uses independent _topReviewComment for one-line preview.
  // All reply logic is confined to the Show All modal only.
  // =============================================

  /// Builds SIMPLE review cards for main detail page (NO reply functionality)
  /// This is used in the main RecipeDetailPage view before clicking "Show All"
  List<Widget> _buildSimpleReviewCards() {
    // Sort reviews by likes (highest first)
    final sortedReviews = List<CommunityReview>.from(widget.reviews)
      ..sort((a, b) => b.likes.compareTo(a.likes));

    // Show only top N reviews
    final reviewsToShow = sortedReviews.take(_initialReviewsToShow).toList();

    return reviewsToShow
        .map((review) => _buildSimpleReviewCard(review))
        .toList();
  }

  /// Builds SIMPLE review card - comment only, NO Reply button, NO reply counts
  /// Used in the main detail page view (before clicking Show All)
  Widget _buildSimpleReviewCard(CommunityReview review) {
    const double avatarSize = 40.0;
    final parts = review.userName.split(' ');
    String initials = '';
    if (parts.isNotEmpty) {
      initials = parts
          .where((p) => p.isNotEmpty)
          .map((p) => p[0].toUpperCase())
          .take(2)
          .join();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 248, 243, 234),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              color: kSageGreen.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initials.isNotEmpty ? initials : '?',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: kDeepForestGreen,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name and rating row
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        review.userName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: kDeepForestGreen,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Star rating
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(5, (index) {
                        return Icon(
                          index < review.rating
                              ? Icons.star
                              : Icons.star_border,
                          size: 12,
                          color: kMutedGold,
                        );
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Comment text only - NO reply info
                Text(
                  review.comment,
                  style: const TextStyle(
                    fontSize: 14,
                    color: kSoftSlateGray,
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Like count + Heart at top-right
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${review.likes}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  setState(() {
                    final liked = _likedReviewIds.contains(review.id);
                    final newLikes = liked
                        ? review.likes - 1
                        : review.likes + 1;
                    if (liked) {
                      _likedReviewIds.remove(review.id);
                    } else {
                      _likedReviewIds.add(review.id);
                    }

                    final index = widget.reviews.indexWhere(
                      (r) => r.id == review.id,
                    );
                    if (index != -1) {
                      widget.reviews[index] = CommunityReview(
                        id: review.id,
                        recipeId: review.recipeId,
                        userName: review.userName,
                        userAvatarUrl: review.userAvatarUrl,
                        rating: review.rating,
                        comment: review.comment,
                        imageUrl: review.imageUrl,
                        createdDate: review.createdDate,
                        likes: newLikes,
                        replies: review.replies,
                      );
                    }
                  });
                },
                child: Icon(
                  _likedReviewIds.contains(review.id)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  size: 16,
                  color: _likedReviewIds.contains(review.id)
                      ? Colors.red
                      : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Renders FULL review card with Reply button, Show/Hide toggle, and replies.
  /// ONLY used in Show All modal (_openReviewsDrawer).
  /// ONLY used in Show All modal (_openReviewsDrawer).
  /// Contains all reply-related logic and nested array mapping.
  Widget _buildReviewCard(CommunityReview review) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 248, 243, 234),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: avatar (initials) + name and rating
              Builder(
                builder: (context) {
                  const double avatarSize = 40.0;
                  final parts = review.userName.split(' ');
                  String initials = '';
                  if (parts.isNotEmpty) {
                    initials = parts
                        .where((p) => p.isNotEmpty)
                        .map((p) => p[0].toUpperCase())
                        .take(2)
                        .join();
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: BoxDecoration(
                          color: kSageGreen.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            initials.isNotEmpty ? initials : '?',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: kDeepForestGreen,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  fit: FlexFit.loose,
                                  child: Text(
                                    review.userName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: kDeepForestGreen,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _formatDate(review.createdDate),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: kCharcoal,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: List.generate(5, (index) {
                                return Icon(
                                  index < review.rating
                                      ? Icons.star
                                      : Icons.star_border,
                                  size: 16,
                                  color: kMutedGold,
                                );
                              }),
                            ),
                          ],
                        ),
                      ),

                      // Like count + Heart at top-right
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${review.likes}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              final liked = _likedReviewIds.contains(review.id);
                              final newLikes = liked
                                  ? review.likes - 1
                                  : review.likes + 1;
                              if (liked) {
                                _likedReviewIds.remove(review.id);
                              } else {
                                _likedReviewIds.add(review.id);
                              }

                              final index = widget.reviews.indexWhere(
                                (r) => r.id == review.id,
                              );
                              if (index != -1) {
                                widget.reviews[index] = CommunityReview(
                                  id: review.id,
                                  recipeId: review.recipeId,
                                  userName: review.userName,
                                  userAvatarUrl: review.userAvatarUrl,
                                  rating: review.rating,
                                  comment: review.comment,
                                  imageUrl: review.imageUrl,
                                  createdDate: review.createdDate,
                                  likes: newLikes,
                                  replies: review.replies,
                                );
                              }

                              // Update both modal and main page state
                              if (_modalSetState != null) {
                                _modalSetState!(() {});
                              }
                              setState(() {});
                            },
                            child: Icon(
                              _likedReviewIds.contains(review.id)
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 18,
                              color: _likedReviewIds.contains(review.id)
                                  ? Colors.red
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 12),

              // Comment body aligned with start of username
              Padding(
                padding: const EdgeInsets.only(left: 52.0),
                child: Text(
                  review.comment,
                  style: const TextStyle(
                    fontSize: 15,
                    color: kSoftSlateGray,
                    height: 1.6,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Reply button (subtle) aligned with comment; toggle shown on next indented line
              Padding(
                padding: const EdgeInsets.only(left: 52.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => _showReplyInput(review),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Reply',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (review.replies.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 12.0),
                        child: GestureDetector(
                          onTap: () {
                            // Use modal setState to update the toggle in the modal
                            if (_modalSetState != null) {
                              _modalSetState!(() {
                                if (_expandedReviewIds.contains(review.id)) {
                                  _expandedReviewIds.remove(review.id);
                                } else {
                                  _expandedReviewIds.add(review.id);
                                }
                              });
                            }
                          },
                          child: Text(
                            _expandedReviewIds.contains(review.id)
                                ? 'Hide ${review.replies.length} ${review.replies.length == 1 ? 'reply' : 'replies'}'
                                : 'Show ${review.replies.length} ${review.replies.length == 1 ? 'reply' : 'replies'}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Display replies (only when expanded)
              if (_expandedReviewIds.contains(review.id) &&
                  review.replies.isNotEmpty) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 52.0),
                  child: Builder(
                    builder: (context) {
                      // Get fresh review data to ensure we have latest replies
                      final freshReview = widget.reviews.firstWhere(
                        (r) => r.id == review.id,
                        orElse: () => review,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: freshReview.replies.map((reply) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      reply.userName,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: kDeepForestGreen,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _formatDate(reply.createdDate),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const Spacer(),
                                    // Like count and heart for replies
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${reply.likes}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        GestureDetector(
                                          onTap: () {
                                            final liked = _likedReplyIds
                                                .contains(reply.id);
                                            final newLikes = liked
                                                ? reply.likes - 1
                                                : reply.likes + 1;

                                            // Update tracking
                                            if (liked) {
                                              _likedReplyIds.remove(reply.id);
                                            } else {
                                              _likedReplyIds.add(reply.id);
                                            }

                                            // Update the reply in the review
                                            final reviewIndex = widget.reviews
                                                .indexWhere(
                                                  (r) => r.id == review.id,
                                                );
                                            if (reviewIndex != -1) {
                                              final replyIndex = widget
                                                  .reviews[reviewIndex]
                                                  .replies
                                                  .indexWhere(
                                                    (rep) => rep.id == reply.id,
                                                  );
                                              if (replyIndex != -1) {
                                                final updatedReplies =
                                                    List<ReviewReply>.from(
                                                      widget
                                                          .reviews[reviewIndex]
                                                          .replies,
                                                    );
                                                updatedReplies[replyIndex] =
                                                    ReviewReply(
                                                      id: reply.id,
                                                      userName: reply.userName,
                                                      comment: reply.comment,
                                                      createdDate:
                                                          reply.createdDate,
                                                      likes: newLikes,
                                                    );
                                                widget.reviews[reviewIndex] =
                                                    CommunityReview(
                                                      id: review.id,
                                                      recipeId: review.recipeId,
                                                      userName: review.userName,
                                                      userAvatarUrl:
                                                          review.userAvatarUrl,
                                                      rating: review.rating,
                                                      comment: review.comment,
                                                      imageUrl: review.imageUrl,
                                                      createdDate:
                                                          review.createdDate,
                                                      likes: review.likes,
                                                      replies: updatedReplies,
                                                    );
                                              }
                                            }

                                            // Update both modal and main page state
                                            if (_modalSetState != null) {
                                              _modalSetState!(() {});
                                            }
                                            setState(() {});
                                          },
                                          child: Icon(
                                            _likedReplyIds.contains(reply.id)
                                                ? Icons.favorite
                                                : Icons.favorite_border,
                                            size: 14,
                                            color:
                                                _likedReplyIds.contains(
                                                  reply.id,
                                                )
                                                ? Colors.red
                                                : Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  reply.comment,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: kSoftSlateGray,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
              ],

              const SizedBox(height: 8),

              // Metadata row removed (date moved to header)
            ],
          ),
        ),
      ],
    );
  }

  // ========== END OF SHOW ALL MODAL REVIEW RENDERING ==========
  // _buildReviewCard() above is the ONLY method that renders reviews with replies.
  // It contains all Reply button logic, Show/Hide toggle, and nested reply array mapping.
  // It is called ONLY from _openReviewsDrawer() modal.
  // The main detail page uses _buildSimpleReviewCards() which has NO reply functionality.
  // ============================================================

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    final minutes = difference.inMinutes;
    if (minutes < 60) {
      final m = minutes <= 0 ? 0 : minutes;
      return '${m}m';
    }

    final hours = difference.inHours;
    if (hours < 24) {
      return '${hours}h';
    }

    final days = difference.inDays;
    if (days < 7) {
      return '${days}d';
    }

    final weeks = (days / 7).floor();
    return '${weeks}w';
  }

  // Review survey is shown in a modal via _openReviewModal

  void _submitReviewOnly({
    required int rating,
    required String comment,
    File? imageFile,
  }) {
    // Create and add community review (no ingredient deduction)
    if (widget.recipeId != null) {
      final review = CommunityReview(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        recipeId: widget.recipeId!,
        userName: widget.userProfile?.userName ?? 'Anonymous',
        userAvatarUrl: widget.userProfile?.avatarUrl,
        rating: rating,
        comment: comment,
        imageUrl: imageFile?.path,
        createdDate: DateTime.now(),
        likes: Random().nextInt(20),
      );

      // Add review to local state for immediate display
      setState(() {
        widget.reviews.insert(0, review);
      });

      // Also notify parent to update global list
      widget.onAddCommunityReview?.call(review);
    }

    // Survey is shown in a modal; no inline flag to update
  }

  void _openReviewsDrawer() {
    // Keep replies collapsed by default (user clicks Show to expand)
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      isDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Capture the setModalState so we can use it from _addReplyToReview
            _modalSetState = setModalState;

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.80,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                // Sort reviews by likes (most liked first)
                final sortedReviews = List<CommunityReview>.from(widget.reviews)
                  ..sort((a, b) => b.likes.compareTo(a.likes));

                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Grabber bar at the top center
                      Padding(
                        padding: const EdgeInsets.only(top: 10.0, bottom: 12.0),
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                          ),
                        ),
                      ),

                      // Header: title and close button
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Reviews',
                              style: TextStyle(
                                fontFamily: 'Lora',
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: kDeepForestGreen,
                              ),
                            ),
                            // Close X button in top-right
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(
                                Icons.close,
                                color: kDeepForestGreen,
                                size: 24,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),

                      const Divider(height: 1, thickness: 1),

                      // Scrollable reviews list
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          itemCount: sortedReviews.length,
                          itemBuilder: (context, index) {
                            final review = sortedReviews[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _buildReviewCard(review),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    ).whenComplete(() {
      // Collapse replies that belong to this recipe's reviews when the drawer closes
      setState(() {
        for (var r in widget.reviews) {
          _expandedReviewIds.remove(r.id);
        }
      });
      // Clear modal state reference
      _modalSetState = null;
    });
  }

  void _showReplyInput(CommunityReview review) {
    final TextEditingController replyController = TextEditingController();

    // Ensure replies are visible when replying
    setState(() {
      _expandedReviewIds.add(review.id);
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Reply to ${review.userName}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: kDeepForestGreen,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: replyController,
              maxLines: 3,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Write your reply...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: kBoneCreame.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  var replyText = replyController.text.trim();
                  if (replyText.isNotEmpty) {
                    // Ensure first character is capitalized
                    if (replyText.length == 1) {
                      replyText = replyText.toUpperCase();
                    } else {
                      replyText =
                          replyText[0].toUpperCase() + replyText.substring(1);
                    }
                    _addReplyToReview(review, replyText);
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kDeepForestGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Post Reply',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _addReplyToReview(CommunityReview review, String replyText) {
    final newReply = ReviewReply(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userName: widget.userProfile?.userName ?? 'Anonymous',
      comment: replyText,
      createdDate: DateTime.now(),
    );

    // Update page state
    setState(() {
      final index = widget.reviews.indexWhere((r) => r.id == review.id);
      if (index != -1) {
        final updatedReplies = [...widget.reviews[index].replies, newReply];
        widget.reviews[index] = CommunityReview(
          id: review.id,
          recipeId: review.recipeId,
          userName: review.userName,
          userAvatarUrl: review.userAvatarUrl,
          rating: review.rating,
          comment: review.comment,
          imageUrl: review.imageUrl,
          createdDate: review.createdDate,
          likes: review.likes,
          replies: updatedReplies,
        );
        // Keep the replies expanded when a new reply is added
        _expandedReviewIds.add(review.id);
      }
    });

    // Also trigger modal rebuild to show new reply immediately
    if (_modalSetState != null) {
      _modalSetState!(() {
        // Modal state setter - forces modal to rebuild with new reply visible
      });
    }

    // Reply input modal is closed by the button's onPressed handler
    // Do NOT pop again here - that would close the reviews modal
  }

  void _openReviewModal() {
    final picker = ImagePicker();

    showGeneralDialog(
      context: context,
      barrierLabel: 'Write a review',
      barrierDismissible: true,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: 0.72,
            widthFactor: 1.0,
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.all(0),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: _ReviewSurveyContent(
                      picker: picker,
                      onSubmit: (rating, comment, imageFile) {
                        _submitReviewOnly(
                          rating: rating,
                          comment: comment,
                          imageFile: imageFile,
                        );
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim, secAnim, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: child,
        );
      },
    );
  }
}

// Separate stateful widget for review survey to properly manage state
class _ReviewSurveyContent extends StatefulWidget {
  final Function(int rating, String comment, File? imageFile) onSubmit;
  final ImagePicker picker;

  const _ReviewSurveyContent({required this.onSubmit, required this.picker});

  @override
  State<_ReviewSurveyContent> createState() => _ReviewSurveyContentState();
}

class _ReviewSurveyContentState extends State<_ReviewSurveyContent> {
  int _rating = 0;
  File? _selectedImage;
  final TextEditingController _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Share Your Experience',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: kDeepForestGreen,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            final isSelected = index < _rating;
            return IconButton(
              icon: Icon(
                isSelected ? Icons.star : Icons.star_border,
                color: kMutedGold,
                size: 28,
              ),
              onPressed: () {
                setState(() {
                  _rating = index + 1;
                });
              },
            );
          }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _commentController,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'How did it turn out? Any tips?',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: kBoneCreame.withOpacity(0.5),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () async {
            final source = await showDialog<ImageSource>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Choose Image Source'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, ImageSource.camera),
                    child: const Text('Camera'),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, ImageSource.gallery),
                    child: const Text('Gallery'),
                  ),
                ],
              ),
            );
            if (source != null) {
              try {
                final pickedFile = await widget.picker.pickImage(
                  source: source,
                );
                if (pickedFile != null) {
                  setState(() {
                    _selectedImage = File(pickedFile.path);
                  });
                }
              } catch (e) {
                // Image picking error - silently handle
              }
            }
          },
          child: Container(
            height: 80,
            width: double.infinity,
            decoration: BoxDecoration(
              color: kBoneCreame,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kMutedGold, width: 2),
            ),
            child: _selectedImage != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      _selectedImage!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt, size: 24, color: kMutedGold),
                        SizedBox(height: 4),
                        Text(
                          'Tap to add photo',
                          style: TextStyle(
                            color: kMutedGold,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              var comment = _commentController.text.trim();
              if (comment.isNotEmpty) {
                if (comment.length == 1) {
                  comment = comment.toUpperCase();
                } else {
                  comment = comment[0].toUpperCase() + comment.substring(1);
                }
              }
              widget.onSubmit(_rating, comment, _selectedImage);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kDeepForestGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Share Review',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}


