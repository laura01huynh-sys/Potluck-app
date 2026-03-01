import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// Tab bar for profile sections (Saved, Cooked, My Dishes, Dietary).
class ProfileTabBar extends StatelessWidget {
  final List<String> tabNames;
  final String selectedTab;
  final ValueChanged<String> onTabSelected;

  const ProfileTabBar({
    super.key,
    required this.tabNames,
    required this.selectedTab,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: tabNames
          .map(
            (name) => TabButton(
              tabName: name,
              isSelected: selectedTab == name,
              onTap: () => onTabSelected(name),
            ),
          )
          .toList(),
    );
  }
}

/// Tab button for profile sections.
class TabButton extends StatelessWidget {
  final String tabName;
  final bool isSelected;
  final VoidCallback onTap;

  const TabButton({
    super.key,
    required this.tabName,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: isSelected
              ? BoxDecoration(
                  color: kDeepForestGreen.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: kDeepForestGreen.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                )
              : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                tabName.toUpperCase(),
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: isSelected ? kDeepForestGreen : kSoftSlateGray,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
