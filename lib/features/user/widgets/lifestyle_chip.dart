import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../features/profile/models/user_profile.dart';

/// Standalone UI component for displaying a custom lifestyle chip.
/// Supports tap (toggle), swipe-to-dismiss (delete), and info icon tap.
class LifestyleChip extends StatelessWidget {
  final CustomLifestyle custom;
  final bool isSelected;
  final VoidCallback onDismiss;
  final VoidCallback onTap;
  final VoidCallback onInfoTap;

  const LifestyleChip({
    super.key,
    required this.custom,
    required this.isSelected,
    required this.onDismiss,
    required this.onTap,
    required this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(custom.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFF0F7F4) : kBoneCreame,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? kDeepForestGreen
                  : kSoftSlateGray.withValues(alpha: 0.2),
              width: 1.5,
            ),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: kDeepForestGreen.withValues(alpha: 0.08),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Stack(
            children: [
              Center(
                child: Text(
                  custom.name.isNotEmpty
                      ? custom.name[0].toUpperCase() + custom.name.substring(1)
                      : custom.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? const Color(0xFF10B981)
                        : Colors.black87,
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: onInfoTap,
                  child: Icon(
                    Icons.info_outline,
                    size: 14,
                    color: isSelected
                        ? const Color.fromARGB(255, 114, 200, 171)
                        : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
