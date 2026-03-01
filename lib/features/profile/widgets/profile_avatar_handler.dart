import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../models/user_profile.dart';

/// Handles profile picture changes: camera, gallery, and remove.
/// Shows a bottom sheet for source selection and uses [ImagePicker].
class ProfileAvatarHandler {
  static final ImagePicker _imagePicker = ImagePicker();

  /// Shows the change-profile-picture bottom sheet and performs the selected action.
  /// [onProfileUpdated] is called when the avatar changes (new image or removed).
  static Future<void> changeProfilePicture(
    BuildContext context, {
    required UserProfile profile,
    required void Function(UserProfile) onProfileUpdated,
  }) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ChangeAvatarBottomSheet(
        profile: profile,
        onRemove: () {
          Navigator.pop(context);
          onProfileUpdated(profile.copyWith(avatarUrl: ''));
        },
      ),
    );

    if (source != null) {
      try {
        final pickedFile = await _imagePicker.pickImage(source: source);
        if (pickedFile != null) {
          onProfileUpdated(profile.copyWith(avatarUrl: pickedFile.path));
        }
      } catch (_) {
        // Image picking error - silently handle
      }
    }
  }
}

class _ChangeAvatarBottomSheet extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onRemove;

  const _ChangeAvatarBottomSheet({
    required this.profile,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Change Profile Picture',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: kDeepForestGreen,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context, ImageSource.camera),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: kSageGreen.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: kSageGreen,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Camera',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context, ImageSource.gallery),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: kMutedGold.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.photo_library,
                        color: kMutedGold,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Gallery',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                onRemove();
                Navigator.pop(context);
              },
              child: const Text(
                'Remove Photo',
                style: TextStyle(color: kSoftTerracotta),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
