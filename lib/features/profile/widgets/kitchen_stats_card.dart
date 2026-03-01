import 'package:flutter/material.dart';

import '../../core/constants.dart';
import 'stat_item.dart';

/// Kitchen stats card: MADE, SHARED, FOLLOWERS.
class KitchenStatsCard extends StatelessWidget {
  final String madeCount;
  final String sharedCount;
  final String followerCount;

  const KitchenStatsCard({
    super.key,
    required this.madeCount,
    required this.sharedCount,
    required this.followerCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 248, 243, 234),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          StatItem(
            value: madeCount,
            label: 'MADE',
            icon: Icons.restaurant_menu,
          ),
          Container(
            width: 1,
            height: 60,
            color: kMutedGold.withOpacity(0.5),
          ),
          StatItem(
            value: sharedCount,
            label: 'SHARED',
            icon: Icons.room_service,
          ),
          Container(
            width: 1,
            height: 60,
            color: kMutedGold.withOpacity(0.5),
          ),
          StatItem(
            value: followerCount,
            label: 'FOLLOWERS',
            icon: Icons.people,
          ),
        ],
      ),
    );
  }
}
