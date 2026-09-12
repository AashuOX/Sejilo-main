// sejilo_connectivity_chip.dart — the 🟢 / 🟡 / 🔴 reachability indicator.
//
// [ConnectivityNotifier] has always computed the three states, but nothing in
// the live shell drew them: the only chip lived in an unreachable screen, so
// the app never told anyone whether it was online, mesh-only, or cut off.

import 'package:flutter/material.dart';

import '../../core/connectivity_notifier.dart';
import '../sejilo_theme.dart';

class SejiloConnectivityChip extends StatelessWidget {
  const SejiloConnectivityChip({
    super.key,
    required this.status,
    this.meshPeerCount = 0,
    this.compact = false,
    this.onTap,
  });

  final ConnectivityStatus status;

  /// Peers reachable over BLE/LAN right now. Shown alongside "Mesh" so the
  /// label states how many devices are actually in range rather than implying
  /// unlimited reach.
  final int meshPeerCount;

  /// Dot only, for the collapsed tablet sidebar.
  final bool compact;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (label, color, detail) = switch (status) {
      ConnectivityStatus.online => (
          'Online',
          SejiloColors.statusOnline,
          'Connected to the internet.',
        ),
      ConnectivityStatus.meshConnected => (
          meshPeerCount == 1 ? 'Mesh · 1 peer' : 'Mesh · $meshPeerCount peers',
          SejiloColors.statusMesh,
          'No internet. Messages travel over Bluetooth to nearby devices only.',
        ),
      ConnectivityStatus.offline => (
          'Offline',
          SejiloColors.statusOffline,
          'No internet and no nearby devices. Messages are queued until one '
              'comes back.',
        ),
    };

    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );

    final chip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 10,
        vertical: compact ? 6 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(SejiloRadius.pill),
        border: Border.all(color: color.withAlpha(70), width: 1),
      ),
      child: compact
          ? dot
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                dot,
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
    );

    return Semantics(
      label: 'Connection status: $label. $detail',
      button: onTap != null,
      child: Tooltip(
        message: detail,
        child: onTap == null
            ? chip
            : InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(SejiloRadius.pill),
                child: chip,
              ),
      ),
    );
  }
}
