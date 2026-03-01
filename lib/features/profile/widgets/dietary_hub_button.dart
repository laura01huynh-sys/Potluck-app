import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../screens/dietary_hub_screen.dart';
import '../models/user_profile.dart';

/// Tappable card that navigates to the Dietary Hub screen.
class DietaryHubButton extends StatelessWidget {
  final UserProfile userProfile;
  final Function(UserProfile) onProfileUpdated;

  const DietaryHubButton({
    super.key,
    required this.userProfile,
    required this.onProfileUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DietaryHubScreen(
            userProfile: userProfile,
            onProfileUpdated: onProfileUpdated,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: kBoneCreame,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kMutedGold, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.restaurant_menu, color: kDeepForestGreen, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dietary Requirements',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: kDeepForestGreen,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manage allergies & preferences',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: kMutedGold),
          ],
        ),
      ),
    );
  }
}
