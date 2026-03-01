import 'package:flutter/material.dart';

import '../../../core/constants.dart';

/// Card for a lifestyle option (e.g. vegan, keto) in the dietary hub.
class LifestyleCard extends StatelessWidget {
  final String lifestyle;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onInfoTap;

  const LifestyleCard({
    super.key,
    required this.lifestyle,
    required this.isSelected,
    required this.onTap,
    required this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = lifestyle
        .replaceAll('-', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : w)
        .join(' ');

    return GestureDetector(
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                displayName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? const Color(0xFF10B981) : Colors.black87,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onInfoTap,
              child: Icon(
                Icons.info_outline,
                size: 14,
                color: isSelected
                    ? const Color.fromARGB(255, 114, 200, 171)
                    : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
