import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/ble_mesh_service.dart';
import '../core/mesh_client.dart';
import '../design_system/sejilo_theme.dart';

/// Full-screen mesh topology dashboard.
///
/// Shows a radial visualization with YOU at center and nearby peers arranged
/// around it. Peers are color-coded by signal strength and annotated with
/// their username, hop count, and last-seen time.
class MeshDashboardPage extends StatefulWidget {
  const MeshDashboardPage({MeshClient? meshClient, super.key})
      : meshClient = meshClient,
        _ownsClient = meshClient == null;

  /// Lazily-initialized mesh client. When null, the page creates its own
  /// client in [initState] and disposes it on exit; when provided, the
  /// caller remains responsible for its lifecycle.
  final MeshClient? meshClient;
  final bool _ownsClient;

  @override
  State<MeshDashboardPage> createState() => _MeshDashboardPageState();
}

class _MeshDashboardPageState extends State<MeshDashboardPage>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _rotateCtrl;
  late final MeshClient _meshClient;

  @override
  void initState() {
    super.initState();
    _meshClient = widget.meshClient ?? MeshClient();
    if (widget._ownsClient) {
      _meshClient.initialize();
    }
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _rotateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
  }

  @override
  void dispose() {
    if (widget._ownsClient) {
      _meshClient.dispose();
    }
    _pulseCtrl.dispose();
    _rotateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesh Network'),
        actions: [
          _MeshStatusChip(meshClient: _meshClient),
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([_meshClient, _pulseCtrl, _rotateCtrl]),
        builder: (context, _) {
          final peers = _meshClient.nearbyPeers;
          final isActive = _meshClient.isMeshAvailable;

          return Column(
            children: [
              // ── Stats Row ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    _StatCard(
                      icon: Icons.people_outline,
                      value: peers.length.toString(),
                      label: 'Peers',
                      color: SejiloColors.statusMesh,
                    ),
                    const SizedBox(width: 10),
                    _StatCard(
                      icon: Icons.router_outlined,
                      value: _networkReach(peers).toString(),
                      label: 'Network reach',
                      color: SejiloColors.statusOnline,
                    ),
                    const SizedBox(width: 10),
                    _StatCard(
                      icon: Icons.sync_outlined,
                      value: isActive ? 'Active' : 'Off',
                      label: 'BLE Status',
                      color: isActive ? SejiloColors.statusOnline : SejiloColors.statusOffline,
                    ),
                  ],
                ),
              ),

              // ── Radial Topology ───────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _RadialTopology(
                    peers: peers,
                    pulseValue: _pulseCtrl.value,
                    rotateValue: _rotateCtrl.value,
                    username: _meshClient.username,
                  ),
                ),
              ),

              // ── Peer List ─────────────────────────────────────────
              if (peers.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text(
                          'Nearby Devices',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: peers.length,
                          itemBuilder: (_, i) => _PeerTile(peer: peers[i]),
                        ),
                      ),
                    ],
                  ),
                ),

              if (peers.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: _EmptyPeersCard(isActive: isActive),
                ),
            ],
          );
        },
      ),
    );
  }

  int _networkReach(List<NearbyMeshPeer> peers) {
    if (peers.isEmpty) return 0;
    // Estimate: direct peers + 2nd-hop estimate
    final direct = peers.where((p) => p.hops == 0).length;
    return direct + peers.length;
  }
}

// ── Radial Topology Painter ───────────────────────────────────────────────────

class _RadialTopology extends StatelessWidget {
  const _RadialTopology({
    required this.peers,
    required this.pulseValue,
    required this.rotateValue,
    required this.username,
  });

  final List<NearbyMeshPeer> peers;
  final double pulseValue;
  final double rotateValue;
  final String username;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(builder: (context, constraints) {
      final center = Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
      final radius = math.min(constraints.maxWidth, constraints.maxHeight) / 2 - 60;

      return CustomPaint(
        painter: _TopologyPainter(
          peers: peers,
          center: center,
          orbitRadius: radius,
          pulseValue: pulseValue,
          isDark: isDark,
        ),
        child: SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Stack(
            children: [
              // YOU center node
              Positioned(
                left: center.dx - 34,
                top: center.dy - 34,
                child: _CenterNode(
                  username: username,
                  pulseValue: pulseValue,
                ),
              ),

              // Peer nodes
              ...peers.asMap().entries.map((entry) {
                final i = entry.key;
                final peer = entry.value;
                final angle = (2 * math.pi / math.max(peers.length, 1)) * i - math.pi / 2;
                final peerRadius = peer.hops == 0 ? radius : radius * 0.7;
                final dx = center.dx + math.cos(angle) * peerRadius;
                final dy = center.dy + math.sin(angle) * peerRadius;
                return Positioned(
                  left: dx - 28,
                  top: dy - 28,
                  child: _PeerNode(peer: peer),
                );
              }),
            ],
          ),
        ),
      );
    });
  }
}

class _TopologyPainter extends CustomPainter {
  _TopologyPainter({
    required this.peers,
    required this.center,
    required this.orbitRadius,
    required this.pulseValue,
    required this.isDark,
  });

  final List<NearbyMeshPeer> peers;
  final Offset center;
  final double orbitRadius;
  final double pulseValue;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    // Pulse rings
    for (var ring = 1; ring <= 3; ring++) {
      final r = orbitRadius * ring / 3.2;
      final opacity = (0.08 - ring * 0.02 + pulseValue * 0.04).clamp(0.0, 1.0);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = SejiloColors.secondary.withAlpha((opacity * 255).toInt())
          ..strokeWidth = 1.2,
      );
    }

    // Edge lines to peers
    for (var i = 0; i < peers.length; i++) {
      final peer = peers[i];
      final angle = (2 * math.pi / math.max(peers.length, 1)) * i - math.pi / 2;
      final peerRadius = peer.hops == 0 ? orbitRadius : orbitRadius * 0.7;
      final peerOffset = Offset(
        center.dx + math.cos(angle) * peerRadius,
        center.dy + math.sin(angle) * peerRadius,
      );
      final sigColor = _signalColor(peer.rssi);
      canvas.drawLine(
        center,
        peerOffset,
        Paint()
          ..color = sigColor.withAlpha(60)
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke,
      );
    }
  }

  Color _signalColor(int rssi) {
    if (rssi >= -60) return SejiloColors.statusOnline;
    if (rssi >= -75) return SejiloColors.statusOffline;
    return SejiloColors.danger;
  }

  @override
  bool shouldRepaint(_TopologyPainter old) =>
      old.pulseValue != pulseValue || old.peers.length != peers.length;
}

// ── Center Node ───────────────────────────────────────────────────────────────

class _CenterNode extends StatelessWidget {
  const _CenterNode({required this.username, required this.pulseValue});
  final String username;
  final double pulseValue;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF833AB4), Color(0xFFE1306C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: SejiloColors.primary.withAlpha(
                  (60 + pulseValue * 80).toInt(),
                ),
                blurRadius: 20 + pulseValue * 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.person, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 6),
        Text(
          'YOU',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: SejiloColors.primary,
          ),
        ),
      ],
    );
  }
}

// ── Peer Node ─────────────────────────────────────────────────────────────────

class _PeerNode extends StatelessWidget {
  const _PeerNode({required this.peer});
  final NearbyMeshPeer peer;

  @override
  Widget build(BuildContext context) {
    final sigColor = _signalColor(peer.rssi);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.surfaceContainer,
            border: Border.all(color: sigColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: sigColor.withAlpha(50),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  peer.username.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    color: sigColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
              ),
              if (peer.isVerified)
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: SejiloColors.statusOnline,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(Icons.check, color: Colors.white, size: 10),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 72,
          child: Text(
            peer.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          peer.hops == 0 ? 'Direct' : '${peer.hops} hop${peer.hops != 1 ? "s" : ""}',
          style: TextStyle(fontSize: 9, color: sigColor),
        ),
      ],
    );
  }

  Color _signalColor(int rssi) {
    if (rssi >= -60) return SejiloColors.statusOnline;
    if (rssi >= -75) return SejiloColors.statusOffline;
    return SejiloColors.danger;
  }
}

// ── Peer List Tile ────────────────────────────────────────────────────────────

class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.peer});
  final NearbyMeshPeer peer;

  @override
  Widget build(BuildContext context) {
    final sigColor = _signalColor(peer.rssi);
    final age = DateTime.now().difference(peer.lastSeen);
    final ageLabel = age.inSeconds < 10
        ? 'Just now'
        : age.inSeconds < 60
            ? '${age.inSeconds}s ago'
            : '${age.inMinutes}m ago';

    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: sigColor.withAlpha(30),
        child: Text(
          peer.username.substring(0, 1).toUpperCase(),
          style: TextStyle(color: sigColor, fontWeight: FontWeight.w700),
        ),
      ),
      title: Row(
        children: [
          Text(
            peer.username,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          if (peer.isVerified) ...[
            const SizedBox(width: 4),
            const Icon(Icons.verified, color: SejiloColors.statusOnline, size: 14),
          ],
        ],
      ),
      subtitle: Text(
        '${peer.hops == 0 ? "Direct BLE" : "${peer.hops}-hop relay"} · ${peer.shortId} · $ageLabel',
        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withAlpha(120)),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _SignalBars(rssi: peer.rssi),
          const SizedBox(height: 2),
          Text(
            '${peer.rssi} dBm',
            style: TextStyle(fontSize: 10, color: sigColor),
          ),
        ],
      ),
    );
  }

  Color _signalColor(int rssi) {
    if (rssi >= -60) return SejiloColors.statusOnline;
    if (rssi >= -75) return SejiloColors.statusOffline;
    return SejiloColors.danger;
  }
}

// ── Signal Bars Widget ────────────────────────────────────────────────────────

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.rssi});
  final int rssi;

  @override
  Widget build(BuildContext context) {
    final bars = rssi >= -60 ? 4 : rssi >= -70 ? 3 : rssi >= -80 ? 2 : 1;
    final color = rssi >= -60
        ? SejiloColors.statusOnline
        : rssi >= -75
            ? SejiloColors.statusOffline
            : SejiloColors.danger;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final active = i < bars;
        return Container(
          width: 4,
          height: 4.0 + i * 3,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: active ? color : color.withAlpha(40),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}

// ── Stat Card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(SejiloRadius.md),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withAlpha(80),
            width: 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(140),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mesh Status Chip ─────────────────────────────────────────────────────────

class _MeshStatusChip extends StatelessWidget {
  const _MeshStatusChip({required this.meshClient});
  final MeshClient meshClient;

  @override
  Widget build(BuildContext context) {
    final peers = meshClient.nearbyPeers;
    final active = meshClient.isMeshAvailable;
    final color = active && peers.isNotEmpty
        ? SejiloColors.statusMesh
        : active
            ? SejiloColors.statusOffline
            : SejiloColors.darkMuted;
    final label = active
        ? peers.isNotEmpty
            ? '${peers.length} peer${peers.length != 1 ? "s" : ""}'
            : 'Scanning'
        : 'Off';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(SejiloRadius.pill),
        border: Border.all(color: color.withAlpha(80), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 5),
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
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyPeersCard extends StatelessWidget {
  const _EmptyPeersCard({required this.isActive});
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(SejiloRadius.lg),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withAlpha(80),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          Icon(
            isActive ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
            size: 36,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(80),
          ),
          const SizedBox(height: 12),
          Text(
            isActive ? 'Scanning for peers…' : 'Mesh is off',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            isActive
                ? 'Nearby Sejilo users will appear here when detected via BLE.'
                : 'Bluetooth permissions are required to discover nearby Sejilo devices.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(140),
            ),
          ),
        ],
      ),
    );
  }
}
