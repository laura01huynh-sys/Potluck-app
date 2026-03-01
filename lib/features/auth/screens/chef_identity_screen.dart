import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/utils/username_generator.dart';
import '../../../services/firebase_service.dart';

/// Post-signup screen: pick username and display name (Chef Identity).
class ChefIdentityScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const ChefIdentityScreen({super.key, required this.onComplete});

  @override
  State<ChefIdentityScreen> createState() => _ChefIdentityScreenState();
}

class _ChefIdentityScreenState extends State<ChefIdentityScreen> {
  final _handleController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefillFromEmail();
  }

  void _prefillFromEmail() {
    final email = FirebaseService.currentUser?.email ?? '';
    final local = email.split('@').first;
    final cleaned = local.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    _handleController.text = cleaned;
    final display = local
        .replaceAll(RegExp(r'[._-]+'), ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
    _displayNameController.text = display;
  }

  void _shuffle() {
    setState(() {
      _handleController.text = generatePotluckUsername();
    });
  }

  @override
  void dispose() {
    _handleController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final handle = _handleController.text.trim();
    final displayName = _displayNameController.text.trim();
    if (handle.isEmpty) {
      setState(() => _error = 'Username cannot be empty.');
      return;
    }
    if (handle.contains(' ')) {
      setState(() => _error = 'Username cannot contain spaces.');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final uid = FirebaseService.currentUser?.uid;
      if (uid == null) return;
      await FirebaseService.updateProfile(
        userId: uid,
        username: handle,
        displayName: displayName.isEmpty ? handle : displayName,
      );
      if (mounted) widget.onComplete();
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        if (msg.contains('duplicate') || msg.contains('unique')) {
          setState(() {
            _error = 'That username is taken. Try another!';
            _saving = false;
          });
        } else {
          setState(() {
            _error = msg.replaceFirst('PostgrestException: ', '');
            _saving = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBoneCreame,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              32,
              48,
              32,
              MediaQuery.of(context).viewInsets.bottom + 32,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: kDeepForestGreen.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.restaurant_menu,
                    color: kDeepForestGreen,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Create your Chef Identity',
                  style: TextStyle(
                    fontFamily: 'Lora',
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: kDeepForestGreen,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pick a username and display name for your profile.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: kSoftSlateGray,
                  ),
                ),
                const SizedBox(height: 32),
                if (_error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                TextField(
                  controller: _handleController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    prefixText: '@',
                    prefixStyle: const TextStyle(
                      color: kDeepForestGreen,
                      fontWeight: FontWeight.w600,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(
                        Icons.casino,
                        color: kMutedGold,
                        size: 22,
                      ),
                      tooltip: 'Shuffle',
                      onPressed: _shuffle,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: kMutedGold.withOpacity(0.3),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: kMutedGold.withOpacity(0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: kDeepForestGreen,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Unique handle for tagging & following',
                    style: TextStyle(fontSize: 12, color: kSoftSlateGray),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _displayNameController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    labelText: 'Display Name',
                    prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: kMutedGold.withOpacity(0.3),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: kMutedGold.withOpacity(0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: kDeepForestGreen,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'What people see on your profile (can be anything)',
                    style: TextStyle(fontSize: 12, color: kSoftSlateGray),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: kDeepForestGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            "Let's Cook!",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
