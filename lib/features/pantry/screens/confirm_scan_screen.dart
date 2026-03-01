import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants.dart';
import '../../../core/format.dart';
import '../../../models/ingredient.dart';

// ================= CONFIRM DETECTED ITEMS SCREEN =================
class ConfirmDetectedItemsScreen extends StatefulWidget {
  final File imageFile;
  final Function(List<Ingredient>) onAddIngredients;

  const ConfirmDetectedItemsScreen({
    super.key,
    required this.imageFile,
    required this.onAddIngredients,
  });

  @override
  State<ConfirmDetectedItemsScreen> createState() =>
      _ConfirmDetectedItemsScreenState();
}

class _ConfirmDetectedItemsScreenState
    extends State<ConfirmDetectedItemsScreen> {
  late Future<List<Ingredient>> _detectionFuture;
  List<Ingredient> _detectedItems = [];
  bool _isLoading = true;
  String? _errorMessage;
  final ScrollController _ingredientsScrollController = ScrollController();

  // Rate limit protection
  DateTime? _lastApiCallTime;
  static const int _minSecondsBetweenCalls = 60;

  @override
  void initState() {
    super.initState();
    _detectionFuture = _detectAndClassifyWithGemini();
  }

  @override
  void dispose() {
    _ingredientsScrollController.dispose();
    super.dispose();
  }

  /// Check if rate limit protection allows API call
  bool _canMakeApiCall() {
    if (_lastApiCallTime == null) return true;

    final secondsElapsed = DateTime.now()
        .difference(_lastApiCallTime!)
        .inSeconds;
    return secondsElapsed >= _minSecondsBetweenCalls;
  }

  /// Get seconds remaining until next API call is allowed
  int _getSecondsUntilNextCall() {
    if (_lastApiCallTime == null) return 0;

    final secondsElapsed = DateTime.now()
        .difference(_lastApiCallTime!)
        .inSeconds;
    final remaining = _minSecondsBetweenCalls - secondsElapsed;
    return remaining > 0 ? remaining : 0;
  }

  /// Main method: Detect and classify ingredients using Gemini 2.0 Flash
  /// Single API call combines detection AND categorization - NO RETRIES
  Future<List<Ingredient>> _detectAndClassifyWithGemini() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // ===== RATE LIMIT PROTECTION =====
      if (!_canMakeApiCall()) {
        final secondsToWait = _getSecondsUntilNextCall();
        throw Exception(
          'Rate limit: Please wait $secondsToWait seconds before trying again (1 request per 60 seconds)',
        );
      }

      // Read and encode the image
      final bytes = await widget.imageFile.readAsBytes();
      final compressedBytes = await _compressImage(bytes);
      final base64Image = base64Encode(compressedBytes);

      // ===== SINGLE API CALL (NO RETRIES) =====
      // Using Gemini 2.0 Flash for ingredient detection (image analysis)
      final response = await http.post(
        Uri.parse(GeminiConfig.detectionEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text':
                      'Identify all visible ingredients in this food image. Return a JSON array with objects containing name, category, unit, and amount for each ingredient.',
                },
                {
                  'inline_data': {
                    'mime_type': 'image/jpeg',
                    'data': base64Image,
                  },
                },
              ],
            },
          ],
          'generationConfig': {
            'temperature': 0.2,
            'topP': 0.95,
            'topK': 40,
            'maxOutputTokens': 8192,
            'responseMimeType': 'application/json',
          },
        }),
      );

      // ===== ERROR HANDLING (NO RETRIES - SINGLE ATTEMPT ONLY) =====
      if (response.statusCode == 429) {
        // Rate limit from Gemini API - inform user with wait time
        final retryAfter = response.headers['retry-after'];
        final waitSeconds = retryAfter != null
            ? int.tryParse(retryAfter) ?? 60
            : 60;
        throw Exception(
          'API rate limit (429): The service is temporarily unavailable. Please wait at least $waitSeconds seconds and try again.',
        );
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception(
          'Authentication failed (${response.statusCode}): Please verify your API key is valid and has the necessary permissions.',
        );
      } else if (response.statusCode == 400) {
        final errorBody = jsonDecode(response.body);
        final errorMessage =
            errorBody['error']?['message'] ?? 'Invalid request';
        throw Exception('Invalid request (400): $errorMessage');
      } else if (response.statusCode == 500 || response.statusCode == 503) {
        throw Exception(
          'Server error (${response.statusCode}): The Gemini service is temporarily unavailable. Please try again in a moment.',
        );
      } else if (response.statusCode != 200) {
        throw Exception(
          'API error (${response.statusCode}): Failed to process image. Please try again.',
        );
      }

      // Parse the response
      final data = jsonDecode(response.body);

      // Check for API errors in the response body
      if (data.containsKey('error')) {
        final error = data['error'];
        final message = error['message'] ?? 'Unknown error';
        throw Exception('API error: $message');
      }

      // Safety check for expected response structure
      if (!data.containsKey('candidates') ||
          data['candidates'].isEmpty ||
          !data['candidates'][0].containsKey('content')) {
        throw Exception('Unexpected response format from Gemini API');
      }

      final responseText =
          data['candidates'][0]['content']['parts'][0]['text'] as String;

      // Convert to Ingredient objects
      final ingredients = _parseGeminiResponse(responseText);

      if (!mounted) return []; // Widget was disposed

      setState(() {
        _detectedItems = ingredients;
        _isLoading = false;
      });

      return ingredients;
    } catch (e) {
      if (!mounted) return []; // Widget was disposed

      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
      return [];
    }
  }

  /// Compress image to reduce API payload size and stay under rate limits
  /// Returns original bytes if small enough, otherwise returns as-is
  /// (Flutter's built-in codec doesn't support JPEG encoding, so we skip resize)
  Future<Uint8List> _compressImage(Uint8List bytes) async => bytes;

  /// Parse Gemini's JSON response into Ingredient objects
  /// Safely handles both raw JSON and markdown-wrapped JSON
  List<Ingredient> _parseGeminiResponse(String responseText) {
    try {
      // Clean response: remove markdown code blocks if present
      String cleanedText = responseText.trim();
      if (cleanedText.startsWith('```json')) {
        cleanedText = cleanedText.substring(7); // Remove ```json
      } else if (cleanedText.startsWith('```')) {
        cleanedText = cleanedText.substring(3); // Remove ```
      }
      if (cleanedText.endsWith('```')) {
        cleanedText = cleanedText.substring(
          0,
          cleanedText.length - 3,
        ); // Remove trailing ```
      }
      cleanedText = cleanedText.trim();

      // Parse the JSON array
      final data = jsonDecode(cleanedText) as List;

      // Convert each item to an Ingredient
      return data.map((item) {
        final categoryStr = item['category'] as String? ?? '';
        final category = _stringToCategory(categoryStr);
        final unit = item['unit'] as String? ?? 'ea';
        final name = item['name'] as String? ?? 'Unknown Item';
        final unitType = _getUnitTypeFromString(unit);

        // Parse amount from AI response, with fallback to defaults
        dynamic amount = item['amount'];
        if (amount == null) {
          // Fallback to default amount if AI didn't provide one
          amount = unitType == UnitType.volume ? 1.0 : 1;
        } else {
          // Ensure correct type based on unitType
          if (unitType == UnitType.volume) {
            amount = (amount as num).toDouble();
          } else {
            final parsed = (amount as num).toDouble();
            amount = parsed == parsed.roundToDouble() ? parsed.toInt() : parsed;
          }
        }

        return Ingredient(
          id:
              DateTime.now().millisecondsSinceEpoch.toString() +
              Random().nextInt(10000).toString(),
          name: name,
          category: category,
          unitType: unitType,
          amount: amount,
          baseUnit: unit,
        );
      }).toList();
    } catch (e) {
      throw Exception(
        'Failed to parse ingredient data. The API response was not in the expected format.',
      );
    }
  }

  /// Convert category string to enum (handles both display names and normalized names)
  IngredientCategory _stringToCategory(String categoryStr) {
    final normalized = categoryStr.toLowerCase().trim();

    // Handle the new format which uses display names
    switch (normalized) {
      case 'proteins':
        return IngredientCategory.proteins;
      case 'produce':
        return IngredientCategory.produce;
      case 'dairy & refrigerated':
      case 'dairyrefrigerated':
      case 'dairy':
        return IngredientCategory.dairyRefrigerated;
      case 'grains & legumes':
      case 'grainslegumes':
      case 'grains':
        return IngredientCategory.grainsLegumes;
      case 'canned goods':
      case 'cannedgoods':
      case 'canned':
        return IngredientCategory.cannedGoods;
      case 'condiments & sauces':
      case 'condimentssauces':
      case 'condiments':
        return IngredientCategory.condimentsSauces;
      case 'spices & seasonings':
      case 'spicesseasonings':
      case 'spices':
        return IngredientCategory.spicesSeasonings;
      case 'frozen':
        return IngredientCategory.frozen;
      case 'baking':
        return IngredientCategory.baking;
      case 'snacks & extras':
      case 'snacksextras':
      case 'snacks':
        return IngredientCategory.snacksExtras;
      default:
        return IngredientCategory.produce;
    }
  }

  /// Determine UnitType from string
  UnitType _getUnitTypeFromString(String unit) {
    final lower = unit.toLowerCase();
    if (lower.contains('ml') ||
        lower.contains('liter') ||
        lower.contains('cup') ||
        lower.contains('tbsp')) {
      return UnitType.volume;
    } else if (lower.contains('gram') ||
        lower.contains('kg') ||
        lower.contains('oz')) {
      return UnitType.weight;
    }
    return UnitType.count;
  }

  Map<IngredientCategory, List<Ingredient>> _groupByCategory(
    List<Ingredient> items,
  ) {
    final grouped = <IngredientCategory, List<Ingredient>>{};
    final categoryOrder = [
      IngredientCategory.produce,
      IngredientCategory.proteins,
      IngredientCategory.dairyRefrigerated,
      IngredientCategory.grainsLegumes,
      IngredientCategory.cannedGoods,
      IngredientCategory.frozen,
      IngredientCategory.condimentsSauces,
      IngredientCategory.spicesSeasonings,
      IngredientCategory.baking,
      IngredientCategory.snacksExtras,
    ];

    // Initialize all categories in order
    for (var category in categoryOrder) {
      grouped[category] = [];
    }

    // Sort items into categories
    for (var item in items) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    return grouped;
  }

  void _showQuantityAdjustment(int index) {
    final ingredient = _detectedItems[index];
    // Safely handle amount regardless of actual runtime type
    int currentQuantity;
    if (ingredient.amount is int) {
      currentQuantity = amountAsInt(ingredient.amount);
    } else if (ingredient.amount is double) {
      currentQuantity = (ingredient.amount as double).toInt();
    } else {
      currentQuantity = int.tryParse(ingredient.amount.toString()) ?? 1;
    }
    IngredientCategory selectedCategory = ingredient.category;
    String currentName = ingredient.name;
    String currentUnit = ingredient.baseUnit;
    final nameController = TextEditingController(text: currentName);

    // Simplified unit options (no plurals, smart defaults)
    final unitOptions = [
      'ea',
      'lb',
      'oz',
      'fl oz',
      'pk',
      'can',
      'jar',
      'bag',
      'box',
      'bunch',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Editable Name Field
                TextField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Ingredient Name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: kBoneCreame.withOpacity(0.5),
                  ),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: kDeepForestGreen,
                  ),
                  onChanged: (value) {
                    currentName = value;
                  },
                ),
                const SizedBox(height: 20),
                // Quantity Controls Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Minus Button
                    GestureDetector(
                      onTap: currentQuantity > 0
                          ? () {
                              setModalState(() {
                                currentQuantity--;
                              });
                            }
                          : null,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: currentQuantity > 0
                              ? kSageGreen.withOpacity(0.2)
                              : Colors.grey.shade100,
                        ),
                        child: Center(
                          child: Icon(
                            Icons.remove,
                            color: currentQuantity > 0
                                ? kDeepForestGreen
                                : Colors.grey.shade400,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Quantity Display
                    Column(
                      children: [
                        Text(
                          currentQuantity.toString(),
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: kDeepForestGreen,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 24),
                    // Plus Button
                    GestureDetector(
                      onTap: () {
                        setModalState(() {
                          currentQuantity++;
                        });
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kSageGreen.withOpacity(0.2),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.add,
                            color: kDeepForestGreen,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Unit Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButton<String>(
                    value: unitOptions.contains(currentUnit)
                        ? currentUnit
                        : unitOptions.first,
                    isExpanded: true,
                    underline: const SizedBox(),
                    hint: const Text('Select Unit'),
                    items: unitOptions.map((unit) {
                      return DropdownMenuItem(value: unit, child: Text(unit));
                    }).toList(),
                    onChanged: (newUnit) {
                      if (newUnit != null) {
                        setModalState(() {
                          currentUnit = newUnit;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // Category Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButton<IngredientCategory>(
                    value: selectedCategory,
                    isExpanded: true,
                    underline: const SizedBox(),
                    hint: const Text('Move to Category'),
                    items: IngredientCategory.values.map((category) {
                      return DropdownMenuItem(
                        value: category,
                        child: Text(category.displayName),
                      );
                    }).toList(),
                    onChanged: (newCategory) {
                      if (newCategory != null) {
                        setModalState(() {
                          selectedCategory = newCategory;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(height: 32),
                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: kDeepForestGreen),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: kDeepForestGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _detectedItems[index] = ingredient.copyWith(
                              name: currentName.trim().isNotEmpty
                                  ? currentName.trim()
                                  : ingredient.name,
                              amount: currentQuantity,
                              baseUnit: currentUnit,
                              category: selectedCategory,
                            );
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kSageGreen,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Save',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddManualIngredient() {
    final nameController = TextEditingController();
    IngredientCategory selectedCategory = IngredientCategory.produce;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Manual Ingredient',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: kDeepForestGreen,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Ingredient Name',
                  hintText: 'e.g., Garlic, Milk',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Category pill boxes
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Category',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: IngredientCategory.values.map((category) {
                      final isSelected = selectedCategory == category;
                      return GestureDetector(
                        onTap: () {
                          setModalState(() {
                            selectedCategory = category;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected ? kDeepForestGreen : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? kDeepForestGreen
                                  : Colors.grey.shade300,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Text(
                            category.displayName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: kDeepForestGreen),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: kDeepForestGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (nameController.text.trim().isNotEmpty) {
                          setState(() {
                            _detectedItems.add(
                              Ingredient(
                                id: DateTime.now().millisecondsSinceEpoch
                                    .toString(),
                                name: nameController.text.trim(),
                                category: selectedCategory,
                                unitType: UnitType.count,
                                amount: 1,
                                baseUnit: 'ea',
                              ),
                            );
                          });
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kSageGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Add',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Ingredient>>(
      future: _detectionFuture,
      builder: (context, snapshot) {
        // ===== LOADING STATE =====
        if (_isLoading) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Processing Image'),
              backgroundColor: kBoneCreame,
              foregroundColor: kDeepForestGreen,
            ),
            body: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Detecting ingredients...'),
                ],
              ),
            ),
          );
        }

        // ===== ERROR STATE =====
        if (_errorMessage != null) {
          final isRateLimitError = _errorMessage!.contains('rate limit');

          return Scaffold(
            appBar: AppBar(
              title: Text(
                isRateLimitError ? 'Rate Limit Exceeded' : 'Detection Error',
              ),
              backgroundColor: kBoneCreame,
              foregroundColor: kDeepForestGreen,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isRateLimitError ? Icons.schedule : Icons.error_outline,
                      size: 64,
                      color: isRateLimitError ? kMutedGold : kSoftTerracotta,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      isRateLimitError
                          ? 'Too Many Requests'
                          : 'Detection Error',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(color: kDeepForestGreen),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: kDeepForestGreen),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text(
                              'Go Back',
                              style: TextStyle(
                                color: kDeepForestGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _errorMessage = null;
                                _isLoading = true;
                                _detectionFuture =
                                    _detectAndClassifyWithGemini();
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kDeepForestGreen,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text(
                              'Retry',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isRateLimitError) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: kMutedGold.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '💡 Tip: Wait a few seconds before retrying. API quota resets periodically.',
                          style: TextStyle(
                            fontSize: 12,
                            color: kMutedGold,
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        final grouped = _groupByCategory(_detectedItems);
        final categoryOrder = [
          IngredientCategory.produce,
          IngredientCategory.proteins,
          IngredientCategory.dairyRefrigerated,
          IngredientCategory.grainsLegumes,
          IngredientCategory.cannedGoods,
          IngredientCategory.frozen,
          IngredientCategory.condimentsSauces,
          IngredientCategory.spicesSeasonings,
          IngredientCategory.baking,
          IngredientCategory.snacksExtras,
        ];

        return Scaffold(
          appBar: AppBar(
            title: const Text('Confirm Items'),
            backgroundColor: kBoneCreame,
            foregroundColor: kDeepForestGreen,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.info_outline, size: 20),
                onPressed: () {
                  // Show help dialog instead of snackbar
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('How to Use'),
                      content: const Text(
                        'Tap chips to adjust quantity or category. Use + to add items manually.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Got it'),
                        ),
                      ],
                    ),
                  );
                },
                tooltip: 'Help',
              ),
            ],
          ),
          body: _detectedItems.isEmpty
              // ===== EMPTY STATE =====
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      const Text('No items detected in the image'),
                      const SizedBox(height: 8),
                      Text(
                        'Try a different image or add items manually',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              // ===== FIXED IMAGE + SCROLLABLE INGREDIENTS LAYOUT =====
              : Column(
                  children: [
                    // ========== FIXED IMAGE AT TOP (does not scroll) ==========
                    Stack(
                      children: [
                        Container(
                          height: MediaQuery.of(context).size.height * 0.35,
                          width: double.infinity,
                          color: kBoneCreame,
                          child: InteractiveViewer(
                            minScale: 1.0,
                            maxScale: 4.0,
                            child: Image.file(
                              widget.imageFile,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    color: kBoneCreame,
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.image_not_supported,
                                            size: 48,
                                            color: Colors.grey.shade400,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Image cannot be displayed',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                            ),
                          ),
                        ),
                        // FAB positioned at bottom-right of image
                        Positioned(
                          bottom: 12,
                          right: 16,
                          child: FloatingActionButton(
                            onPressed: _showAddManualIngredient,
                            backgroundColor: kDeepForestGreen,
                            shape: const CircleBorder(),
                            child: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // ========== SCROLLABLE INGREDIENT LIST ==========
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        itemCount: categoryOrder.length,
                        itemBuilder: (context, index) {
                          final category = categoryOrder[index];

                          if (!grouped.containsKey(category) ||
                              grouped[category]!.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          final items = grouped[category]!;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Category Header with count badge
                              Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: kMutedGold,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      category.displayName,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: kDeepForestGreen,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kMutedGold.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      items.length.toString(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: kDeepForestGreen,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              // Ingredient chips
                              ExcludeSemantics(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: items.asMap().entries.map<Widget>((
                                    entry,
                                  ) {
                                    final globalIndex = _detectedItems.indexOf(
                                      entry.value,
                                    );
                                    final ing = entry.value;

                                    return Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        GestureDetector(
                                          onTap: () => _showQuantityAdjustment(
                                            globalIndex,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.only(
                                              left: 12,
                                              right: 8,
                                              top: 8,
                                              bottom: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: Colors.grey.shade300,
                                                width: 1.0,
                                              ),
                                            ),
                                            child: Text(
                                              ing.name,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: kCharcoal,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Floating X delete button
                                        Positioned(
                                          top: -6,
                                          right: -6,
                                          child: GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                _detectedItems.removeAt(
                                                  globalIndex,
                                                );
                                              });
                                            },
                                            child: Container(
                                              width: 20,
                                              height: 20,
                                              decoration: BoxDecoration(
                                                color: Colors.grey,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.close,
                                                size: 12,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
          bottomNavigationBar: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _detectedItems.isNotEmpty
                    ? () {
                        widget.onAddIngredients(_detectedItems);
                        Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kDeepForestGreen,
                  disabledBackgroundColor: Colors.grey.shade300,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: const Text(
                  'Confirm & Save',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
