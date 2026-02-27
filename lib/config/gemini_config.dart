/// Gemini API configuration for recipe generation and ingredient detection.
class GeminiConfig {
  /// API key loaded from environment variable (--dart-define=GEMINI_API_KEY=your_key)
  /// Falls back to hardcoded key for development only
  static const String apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: 'AIzaSyBx4div9cf11aBQdkrFpfESeSKnO1NbLWU',
  );

  static const String recipeModel = 'gemini-2.5-flash';
  static const String detectionModel = 'gemini-2.5-flash';

  static String get endpoint =>
      'https://generativelanguage.googleapis.com/v1beta/models/$recipeModel:generateContent?key=$apiKey';

  static String get recipeEndpoint =>
      'https://generativelanguage.googleapis.com/v1beta/models/$recipeModel:generateContent?key=$apiKey';

  static String get detectionEndpoint =>
      'https://generativelanguage.googleapis.com/v1beta/models/$detectionModel:generateContent?key=$apiKey';
}
