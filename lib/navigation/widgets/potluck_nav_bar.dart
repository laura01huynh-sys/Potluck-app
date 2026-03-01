import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// Model for a single tab in the bottom navigation bar (icon, label, center styling).
class NavTab {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isCenter;

  const NavTab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.isCenter = false,
  });
}

/// Glassmorphism bottom navigation bar with blur and custom gold center "+" tab.
/// Stateless: only rebuilds when [currentIndex] or [shoppingListCount] change.
class PotluckNavigationBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final int shoppingListCount;

  const PotluckNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.shoppingListCount = 0,
  });

  static const List<NavTab> tabs = [
    NavTab(
      icon: Icons.kitchen_outlined,
      activeIcon: Icons.kitchen,
      label: 'PANTRY',
    ),
    NavTab(
      icon: Icons.restaurant_outlined,
      activeIcon: Icons.restaurant,
      label: 'POTLUCK',
    ),
    NavTab(
      icon: Icons.add_circle_outline,
      activeIcon: Icons.add_circle,
      label: 'ADD',
      isCenter: true,
    ),
    NavTab(
      icon: Icons.shopping_cart_outlined,
      activeIcon: Icons.shopping_cart,
      label: 'SHOP',
    ),
    NavTab(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'PROFILE',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            tabs.length,
            (index) => _buildTab(tabs[index], index, index == currentIndex),
          ),
        ),
      ),
    );
  }

  Widget _buildTab(NavTab tab, int index, bool isActive) {
    final double tabWidth = tab.isCenter ? 72.0 : 62.0;
    return SizedBox(
      width: tabWidth,
      child: GestureDetector(
        onTap: () => onTap(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: tab.isCenter ? 56 : 40,
                    height: tab.isCenter ? 56 : 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tab.isCenter
                          ? kMutedGold
                          : (isActive ? Colors.black12 : Colors.transparent),
                    ),
                    alignment: Alignment.center,
                    child: tab.isCenter
                        ? Text(
                            '+',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.normal,
                              color: kDeepForestGreen,
                              height: 0.5,
                            ),
                          )
                        : Icon(
                            isActive ? tab.activeIcon : tab.icon,
                            color: kDeepForestGreen,
                            size: 24,
                          ),
                  ),
                  if (index == 3 && shoppingListCount > 0) ...[
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: Color.fromARGB(255, 255, 253, 253),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          shoppingListCount.toString(),
                          style: const TextStyle(
                            color: Color.fromARGB(255, 82, 77, 77),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (!tab.isCenter) ...[
                const SizedBox(height: 0),
                Text(
                  tab.label.toUpperCase(),
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: isActive
                        ? const Color.fromARGB(255, 16, 21, 20)
                        : const Color.fromARGB(255, 49, 72, 66),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
