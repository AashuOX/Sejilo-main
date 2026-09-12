import 'package:flutter/material.dart';
import '../../core/hybrid_communication_manager.dart';
import '../sejilo_theme.dart';

class HybridStatusBadge extends StatelessWidget {
  const HybridStatusBadge({
    super.key,
    required this.networkState,
    this.activityState = HybridActivityState.idle,
    this.peerCount = 0,
    this.compact = false,
  });

  final HybridNetworkState networkState;
  final HybridActivityState activityState;
  final int peerCount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    IconData iconData;
    String label;

    if (activityState == HybridActivityState.syncing) {
      badgeColor = SejiloColors.accent;
      iconData = Icons.sync;
      label = 'Syncing';
    } else if (activityState == HybridActivityState.relaying) {
      badgeColor = const Color(0xFF8B5CF6); // Violet relay
      iconData = Icons.alt_route;
      label = 'Relaying';
    } else {
      switch (networkState) {
        case HybridNetworkState.online:
          badgeColor = const Color(0xFF10B981); // Emerald green
          iconData = Icons.cloud_done;
          label = 'Online';
          break;
        case HybridNetworkState.meshConnected:
          badgeColor = const Color(0xFF06B6D4); // Cyan mesh
          iconData = Icons.hub;
          label = peerCount > 1 ? 'Mesh ($peerCount)' : 'Mesh (1)';
          break;
        case HybridNetworkState.offline:
          badgeColor = const Color(0xFFF59E0B); // Amber offline
          iconData = Icons.cloud_off;
          label = 'Offline';
          break;
      }
    }

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: badgeColor.withValues(alpha: 0.4), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: badgeColor,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: badgeColor.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 13, color: badgeColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: badgeColor,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}
