import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

/// Service for managing local recipe image files
class RecipeImageFileService {
  /// Download and save image to local documents directory
  /// Returns the local file path if successful, null otherwise
  static Future<String?> downloadAndSaveImage({
    required String imageUrl,
    required String recipeId,
  }) async {
    try {
      // Validate URL
      if (imageUrl.isEmpty) {
        debugPrint('Image URL is empty for recipe $recipeId');
        return null;
      }
      
      // Handle local file paths - already saved locally
      if (imageUrl.startsWith('/')) {
        debugPrint('Image is already a local file path: $imageUrl');
        return imageUrl;
      }
      
      if (!imageUrl.startsWith('http')) {
        debugPrint('Invalid image URL format: $imageUrl');
        return null;
      }

      // Get app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/recipe_images');
      
      // Create directory if it doesn't exist
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      // Generate filename from recipe ID
      final filename = 'recipe_$recipeId.jpg';
      final filepath = '${imagesDir.path}/$filename';

      debugPrint('Downloading image from: $imageUrl to $filepath');

      // Download image
      final response = await http.get(Uri.parse(imageUrl)).timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode == 200) {
        // Save to file
        final file = File(filepath);
        await file.writeAsBytes(response.bodyBytes);
        debugPrint('Image saved successfully to: $filepath');
        return filepath;
      } else {
        debugPrint('Failed to download image. Status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error downloading image for recipe $recipeId: $e');
    }
    return null;
  }

  /// Check if a local image file exists
  static Future<bool> imageFileExists(String localPath) async {
    try {
      return await File(localPath).exists();
    } catch (_) {
      return false;
    }
  }

  /// Delete a local image file
  static Future<void> deleteImageFile(String localPath) async {
    try {
      final file = File(localPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error deleting image file: $e');
    }
  }

  /// Get the image file for a recipe (returns File object)
  static Future<File?> getImageFile(String localPath) async {
    try {
      final file = File(localPath);
      if (await file.exists()) {
        return file;
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  /// Clear all cached recipe images
  static Future<void> clearAllImages() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/recipe_images');
      
      if (await imagesDir.exists()) {
        await imagesDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error clearing images: $e');
    }
  }
}
