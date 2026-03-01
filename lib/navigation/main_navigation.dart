import 'package:flutter/material.dart';

import 'widgets/potluck_nav_bar.dart';

/// Visual shell for the main app: Stack + IndexedStack (keeps tab screens alive)
/// plus the bottom navigation bar. State (which tab, shopping count, tab content)
/// is owned by the host; this widget only handles layout and bar presentation.
class MainNavigation extends StatelessWidget {
  const MainNavigation({
    super.key,
    required this.currentIndex,
    required this.onTabTapped,
    required this.shoppingListCount,
    required this.tabBuilder,
  });

  final int currentIndex;
  final void Function(int) onTabTapped;
  final int shoppingListCount;
  final Widget Function(int index) tabBuilder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          IndexedStack(
            index: currentIndex,
            children: List.generate(5, (index) => tabBuilder(index)),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 80,
              child: PotluckNavigationBar(
                currentIndex: currentIndex,
                onTap: onTabTapped,
                shoppingListCount: shoppingListCount,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
