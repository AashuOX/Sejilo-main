// server_settings_page.dart — which backend this install talks to.
//
// Salvaged from a settings screen that was never reachable. The one thing that
// changed is honesty: the old version drew a fixed "Online Mode: ACTIVE" banner
// regardless of whether the server answered. The banner now reports the result
// of the last ping, and says so when there has not been one.

import 'package:flutter/material.dart';
import '../auth/account_auth_controller.dart';
import '../core/api_config.dart';
import '../design_system/sejilo_theme.dart';

class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({required this.auth, super.key});

  final AccountAuthController auth;

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

enum _ProbeState { untested, testing, reachable, degraded, unreachable }

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  late final TextEditingController _urlController =
      TextEditingController(text: widget.auth.baseUrl);
  _ProbeState _probe = _ProbeState.untested;
  int? _latencyMs;

  // The old third entry was https://api.sejilo.app, a domain that does not
  // exist — picking it could only ever produce a failed lookup. The hosted
  // address is the one this build defaults to.
  static const List<(String, String)> _presets = [
    ('Sejilo cloud (default)', ApiConfig.hostedBaseUrl),
    ('Localhost (adb reverse tcp:8080)', 'http://localhost:8080'),
    ('Android emulator host', 'http://10.0.2.2:8080'),
  ];

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// Rejects anything that is not an absolute http(s) URL, since a typo here
  /// makes every later request fail with a confusing error.
  String? _validate(String raw) {
    if (raw.isEmpty) return null; // Empty means "go back to the default".
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.isAbsolute) return 'That is not a full URL.';
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'The address has to start with http:// or https://.';
    }
    return null;
  }

  Future<void> _testConnection() async {
    final raw = _urlController.text.trim();
    final problem = _validate(raw);
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    setState(() {
      _probe = _ProbeState.testing;
      _latencyMs = null;
    });
    final probe = await widget.auth.probeServer(raw.isEmpty ? null : raw);
    if (!mounted) return;
    setState(() {
      _latencyMs = probe.latencyMs;
      // A server whose database is missing answers /health perfectly well and
      // then fails every sign-in, so it cannot share a verdict with one that
      // works.
      _probe = switch (probe) {
        ServerProbe(isReady: true) => _ProbeState.reachable,
        ServerProbe(reachable: true) => _ProbeState.degraded,
        _ => _ProbeState.unreachable,
      };
    });
  }

  Future<void> _save() async {
    final raw = _urlController.text.trim();
    final problem = _validate(raw);
    final messenger = ScaffoldMessenger.of(context);
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    await widget.auth.updateBaseUrl(raw);
    if (!mounted) return;
    _urlController.text = widget.auth.baseUrl;
    setState(() {
      // The saved address may differ from what was pinged, so the old verdict
      // no longer describes it.
      _probe = _ProbeState.untested;
      _latencyMs = null;
    });
    messenger.showSnackBar(
      SnackBar(content: Text('Now using ${widget.auth.baseUrl}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Server',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ProbeBanner(state: _probe, latencyMs: _latencyMs),
          const SizedBox(height: 20),
          const Text(
            'Backend address',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: 'https://api.sejilo.app',
              helperText: 'Leave empty to use the address this build was compiled with.',
              helperMaxLines: 2,
              prefixIcon: const Icon(Icons.dns_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _probe == _ProbeState.testing ? null : _testConnection,
                  icon: _probe == _ProbeState.testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_rounded),
                  label: const Text('Test'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save'),
                ),
              ),
            ],
          ),
          const Divider(height: 36),
          Text(
            'PRESETS',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: .6,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          for (final (label, url) in _presets)
            ListTile(
              dense: true,
              title: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              subtitle: Text(url, style: const TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.north_west_rounded, size: 16),
              onTap: () => setState(() {
                _urlController.text = url;
                _probe = _ProbeState.untested;
                _latencyMs = null;
              }),
            ),
          const SizedBox(height: 8),
          Text(
            'Signing out is not required after a change, but an account only '
            'exists on the server that created it — switching addresses can '
            'invalidate your session.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProbeBanner extends StatelessWidget {
  const _ProbeBanner({required this.state, required this.latencyMs});

  final _ProbeState state;
  final int? latencyMs;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String title, String detail) = switch (state) {
      _ProbeState.untested => (
          Icons.help_outline_rounded,
          Theme.of(context).colorScheme.onSurfaceVariant,
          'Not tested',
          'Tap Test to check whether this address answers.',
        ),
      _ProbeState.testing => (
          Icons.wifi_tethering_rounded,
          SejiloColors.primary,
          'Testing…',
          'Waiting for the server to answer /health.',
        ),
      _ProbeState.reachable => (
          Icons.cloud_done_rounded,
          SejiloColors.darkSuccess,
          'Reachable · ${latencyMs}ms',
          'The server answered and its database is attached. Accounts, posts '
              'and online chat will work.',
        ),
      _ProbeState.degraded => (
          Icons.cloud_queue_rounded,
          SejiloColors.darkWarning,
          'Up, but not ready · ${latencyMs}ms',
          'The server is running without a working database, so signing in, '
              'posting and chat will fail. Set DATABASE_URL on the host, then '
              'test again.',
        ),
      _ProbeState.unreachable => (
          Icons.cloud_off_rounded,
          SejiloColors.danger,
          'No answer',
          'No SejiloChat server responded at this address. The app stays '
              'usable offline — mesh messaging does not need a server.',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
