import 'package:flutter/material.dart';

/// Central place for API keys, IDs, and design tokens used by the app.
///
/// NOTE: For production apps you should NOT hardcode secrets in source.
/// Prefer environment variables, secure storage, or remote config.
class ApiKeys {
  /// Gemini API key (used by GeminiConfig).
  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    // Falls back to development key. Replace/remove before shipping.
    defaultValue: 'AIzaSyBx4div9cf11aBQdkrFpfESeSKnO1NbLWU',
  );

  /// Edamam Recipe API credentials.
  static const String edamamAppId = '46079ec0';
  static const String edamamAppKey = '375c5f612c07d29724251b57ea39d101';
}

/// Gemini API configuration for recipe generation and ingredient detection.
class GeminiConfig {
  /// Centralized Gemini API key (see ApiKeys above).
  static const String apiKey = ApiKeys.geminiApiKey;

  static const String recipeModel = 'gemini-2.5-flash';
  static const String detectionModel = 'gemini-2.5-flash';

  static String get endpoint =>
      'https://generativelanguage.googleapis.com/v1beta/models/$recipeModel:generateContent?key=$apiKey';

  static String get recipeEndpoint =>
      'https://generativelanguage.googleapis.com/v1beta/models/$recipeModel:generateContent?key=$apiKey';

  static String get detectionEndpoint =>
      'https://generativelanguage.googleapis.com/v1beta/models/$detectionModel:generateContent?key=$apiKey';
}

/// Design system colors
const Color kBoneCreame = Color.fromARGB(255, 239, 229, 203);
const Color kDarkerCreame = Color.fromARGB(255, 233, 228, 207);
const Color kDeepForestGreen = Color.fromARGB(255, 51, 93, 80);
const Color kMutedGold = Color.fromARGB(255, 203, 179, 98);
const Color kSoftSlateGray = Color(0xFF4F6D7A);
const Color kSoftTerracotta = Color(0xFFE2725B);
const Color kCharcoal = Color(0xFF333333);

