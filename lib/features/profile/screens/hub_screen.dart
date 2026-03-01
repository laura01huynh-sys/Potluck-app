import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../services/firebase_service.dart';

/// Hub screen shell: AppBar with settings (Sign Out / Delete Account) and a body.
/// The parent provides the body (e.g. ProfileScreen).
class HubScreen extends StatefulWidget {
  final Widget body;

  const HubScreen({
    super.key,
    required this.body,
  });

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  void _showSettingsMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: kBoneCreame,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Settings',
              style: TextStyle(
                fontFamily: 'Lora',
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: kDeepForestGreen,
              ),
            ),
            const SizedBox(height: 8),
            if (FirebaseService.currentUser?.email != null)
              Text(
                FirebaseService.currentUser!.email!,
                style: TextStyle(fontSize: 13, color: kSoftSlateGray),
              ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.logout, color: kDeepForestGreen),
              title: const Text('Sign Out'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await FirebaseService.signOut();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_forever, color: Colors.red.shade700),
              title: Text(
                'Delete Account',
                style: TextStyle(color: Colors.red.shade700),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteAccount(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBoneCreame,
        title: const Text(
          'Delete Account?',
          style: TextStyle(color: kDeepForestGreen),
        ),
        content: const Text(
          'This will permanently delete your account, recipes, and followers. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseService.deleteAccount();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: kBoneCreame,
        foregroundColor: kDeepForestGreen,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, size: 24),
            tooltip: 'Settings',
            onPressed: () => _showSettingsMenu(context),
          ),
        ],
      ),
      body: widget.body,
    );
  }
}
