import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// Profile header with avatar, username, and optional tap-to-change-photo.
class PotluckProfileHeader extends StatelessWidget {
  final String userName;
  final String? avatarUrl;
  final VoidCallback? onAvatarTap;

  const PotluckProfileHeader({
    super.key,
    required this.userName,
    this.avatarUrl,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: kBoneCreame,
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: onAvatarTap,
            child: Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: kMutedGold, width: 1.5),
                  ),
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.white,
                    backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
                        ? (avatarUrl!.startsWith('/')
                              ? FileImage(File(avatarUrl!))
                              : NetworkImage(avatarUrl!) as ImageProvider)
                        : null,
                    child: avatarUrl == null || avatarUrl!.isEmpty
                        ? Icon(Icons.person, size: 60, color: kMutedGold)
                        : null,
                  ),
                ),
                if (onAvatarTap != null)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: kDeepForestGreen,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            userName.contains(' ') ? userName : '@$userName',
            style: const TextStyle(
              fontFamily: 'Lora',
              fontWeight: FontWeight.bold,
              fontSize: 24,
              color: kDeepForestGreen,
              letterSpacing: 0.5,
            ),
          ),
          if (userName.isNotEmpty && !userName.contains(' '))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Your unique handle',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: kSoftSlateGray,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
