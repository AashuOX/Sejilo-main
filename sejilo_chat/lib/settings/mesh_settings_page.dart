// mesh_settings_page.dart — the Bluetooth mesh controls.
//
// Removed here: a "Nearby visibility: Contacts only" row that led nowhere, an
// "Allow relay" switch hardwired to true (relaying is part of the protocol and
// has no off switch), and a "Battery usage: Low" row that measured nothing. The
// connection row used to read "Online / Internet available" as fixed text; it
// now follows a live probe.

import 'package:flutter/material.dart';
import '../core/connectivity_notifier.dart';
import '../core/mesh_client.dart';
import '../design_system/sejilo_theme.dart';
import '../onboarding/mesh_onboarding_page.dart';
import 'settings_section.dart';

class MeshSettingsPage extends StatefulWidget {
  const MeshSettingsPage({required this.meshClient, super.key});

  final MeshClient meshClient;

  @override
  State<MeshSettingsPage> createState() => _MeshSettingsPageState();
}

class _MeshSettingsPageState extends State<MeshSettingsPage> {
  late final ConnectivityNotifier _connectivity = ConnectivityNotifier();

  @override
  void initState() {
    super.initState();
    _connectivity.initialize();
    _connectivity.updateMeshPeerCount(widget.meshClient.nearbyPeers.length);
    widget.meshClient.addListener(_syncPeerCount);
  }

  @override
  void dispose() {
    widget.meshClient.removeListener(_syncPeerCount);
    _connectivity.dispose();
    super.dispose();
  }

  void _syncPeerCount() {
    _connectivity.updateMeshPeerCount(widget.meshClient.nearbyPeers.length);
  }

  Future<void> _editLocality() async {
    final mesh = widget.meshClient;
    final controller = TextEditingController(text: mesh.localityName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Local area name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Devices that use the same name share one nearby channel. Pick '
              'something the people around you would also type — a campus, a '
              'building, a festival.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Area name',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    await mesh.setPresence(
      enabled: mesh.shareNearby,
      locality: name.isEmpty ? null : name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mesh = widget.meshClient;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mesh',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: ListenableBuilder(
        listenable: mesh,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SettingsSection(
              title: 'Mesh network',
              icon: Icons.bluetooth_outlined,
              children: [
                SwitchListTile(
                  value: mesh.shareNearby,
                  onChanged: (value) => mesh.setPresence(
                    enabled: value,
                    locality: mesh.localityName,
                  ),
                  title: const Text('Enable mesh'),
                  subtitle: const Text(
                    'Advertise over Bluetooth LE and carry messages for nearby '
                    'devices. Off stops scanning and advertising entirely.',
                  ),
                  secondary: Icon(
                    mesh.shareNearby
                        ? Icons.bluetooth_rounded
                        : Icons.bluetooth_disabled_rounded,
                    color: mesh.shareNearby ? SejiloColors.primary : null,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: const Text('Local area name'),
                  subtitle: Text(
                    mesh.localityName ?? 'Not set — you are in the open channel',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _editLocality,
                ),
                SwitchListTile(
                  value: mesh.preferences.trustedOnly,
                  onChanged: mesh.preferences.setTrustedOnly,
                  title: const Text('Verified contacts only'),
                  subtitle: const Text(
                    'Messages from keys you have not verified in person are '
                    'dropped on arrival — not stored, not shown. Your device '
                    'still relays them to other people.',
                  ),
                  secondary: const Icon(Icons.verified_user_outlined),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SettingsSection(
              title: 'Status',
              icon: Icons.signal_cellular_alt_rounded,
              children: [
                ListenableBuilder(
                  listenable: _connectivity,
                  builder: (context, _) {
                    final (String title, String detail, Color color, IconData icon) =
                        switch (_connectivity.status) {
                      ConnectivityStatus.online => (
                          'Online',
                          'The internet is reachable, so online chat and posts work.',
                          SejiloColors.statusOnline,
                          Icons.wifi_rounded,
                        ),
                      ConnectivityStatus.meshConnected => (
                          'Mesh only',
                          'No internet. Messages travel through nearby devices.',
                          SejiloColors.statusMesh,
                          Icons.hub_rounded,
                        ),
                      ConnectivityStatus.offline => (
                          'Offline',
                          'No internet and no peers in range. Messages are queued.',
                          SejiloColors.statusOffline,
                          Icons.cloud_off_rounded,
                        ),
                    };
                    return ListTile(
                      leading: Icon(icon, color: color),
                      title: Text(title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(detail),
                      trailing: IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: 'Check again',
                        onPressed: _connectivity.refresh,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.people_outline_rounded),
                  title: Text(
                    mesh.nearbyPeers.length == 1
                        ? '1 peer in range'
                        : '${mesh.nearbyPeers.length} peers in range',
                  ),
                  subtitle: Text(
                    mesh.shareNearby
                        ? 'Counted from Bluetooth advertisements right now'
                        : 'Mesh is off, so nothing is being counted',
                  ),
                ),
                if (mesh.meshError != null)
                  ListTile(
                    leading: const Icon(Icons.error_outline_rounded,
                        color: SejiloColors.danger),
                    title: const Text('Bluetooth problem'),
                    subtitle: Text(mesh.meshError!),
                  ),
                if (mesh.initializationError != null)
                  ListTile(
                    leading: const Icon(Icons.key_off_rounded,
                        color: SejiloColors.danger),
                    title: const Text('Device keys unavailable'),
                    subtitle: Text(mesh.initializationError!),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SettingsSection(
              title: 'Learn',
              icon: Icons.school_outlined,
              children: [
                ListTile(
                  leading: const Icon(Icons.play_circle_outline_rounded),
                  title: const Text('How mesh works'),
                  subtitle: const Text('Three screens, no account needed'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MeshOnboardingPage(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _RangeNote(),
          ],
        ),
      ),
    );
  }
}

/// Bluetooth LE reaches tens of metres, not kilometres. Relaying extends who a
/// message can reach, but only while there is a chain of devices in range.
class _RangeNote extends StatelessWidget {
  const _RangeNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bluetooth LE typically covers 10–30 m indoors and further in the '
              'open. A message can travel beyond that only by hopping through '
              'other devices, and each hop needs a phone that is in range, '
              'awake and running SejiloChat. There is no long-range mode.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
