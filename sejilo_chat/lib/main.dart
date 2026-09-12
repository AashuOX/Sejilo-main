import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'ai/ai_provider.dart';
import 'ai/local_ai_provider.dart';
import 'auth/account_auth_controller.dart';
import 'auth/account_screens.dart';
import 'core/app_preferences.dart';
import 'core/connectivity_notifier.dart';
import 'core/mesh_client.dart';
import 'core/platform_capabilities.dart';
import 'design_system/sejilo_theme.dart';
import 'mesh/mesh_dashboard_page.dart';
import 'messaging/messaging.dart';
import 'settings/settings_page.dart';
import 'social/social_screens.dart';

import 'auth/screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = AppPreferences();
  await preferences.load();
  runApp(SejiloApp(preferences: preferences));
}

class FadeUpPageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeUpPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final fade = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
    );
    final slide = Tween<Offset>(begin: const Offset(0.0, 0.05), end: Offset.zero).animate(
      CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
    );
    return FadeTransition(opacity: fade, child: SlideTransition(position: slide, child: child));
  }
}

class SejiloApp extends StatefulWidget {
  const SejiloApp({required this.preferences, super.key});

  final AppPreferences preferences;

  @override
  State<SejiloApp> createState() => _SejiloAppState();
}

class _SejiloAppState extends State<SejiloApp> {
  late final MeshClient _meshClient;
  late final AccountAuthController _accountAuth;

  @override
  void initState() {
    super.initState();
    _meshClient = MeshClient(preferences: widget.preferences);
    _meshClient.initialize();
    _accountAuth = AccountAuthController(preferences: widget.preferences);
    _accountAuth.initialize();
  }

  @override
  void dispose() {
    _meshClient.dispose();
    _accountAuth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.preferences, _accountAuth]),
      builder: (context, _) => MaterialApp(
        title: 'SejiloChat',
        debugShowCheckedModeBanner: false,
        theme: SejiloTheme.light(),
        darkTheme: SejiloTheme.dark(),
        themeMode: widget.preferences.themeMode,
        home: SplashScreen(auth: _accountAuth, preferences: widget.preferences, meshClient: _meshClient),
      ),
    );
  }
}

class MeshHome extends StatefulWidget {
  const MeshHome(
      {required this.meshClient, required this.preferences, required this.accountAuth, super.key});

  final MeshClient meshClient;
  final AppPreferences preferences;
  final AccountAuthController accountAuth;

  @override
  State<MeshHome> createState() => _MeshHomeState();
}

class _MeshHomeState extends State<MeshHome> {
  _AppSection _section = _AppSection.home;
  late final ConnectivityNotifier _connectivity;

  @override
  void initState() {
    super.initState();
    _connectivity = ConnectivityNotifier();
    _connectivity.initialize();
    // Mirror mesh peer count into the connectivity notifier.
    widget.meshClient.addListener(_onMeshChanged);
  }

  void _onMeshChanged() {
    _connectivity.updateMeshPeerCount(widget.meshClient.nearbyPeers.length);
  }

  @override
  void dispose() {
    widget.meshClient.removeListener(_onMeshChanged);
    _connectivity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meshClient = widget.meshClient;
    return AnimatedBuilder(
      animation: meshClient,
      builder: (context, _) {
        if (!meshClient.isReady) {
          return const _StartupScreen();
        }
        if (meshClient.needsOnboarding) {
          return _OnboardingScreen(meshClient: meshClient);
        }
        return Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.keyK, control: true):
                _SearchIntent(),
            SingleActivator(LogicalKeyboardKey.keyN, control: true):
                _NewConversationIntent(),
            SingleActivator(LogicalKeyboardKey.comma, control: true):
                _SettingsIntent(),
            SingleActivator(LogicalKeyboardKey.escape): _EscapeIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _SearchIntent: CallbackAction<_SearchIntent>(
                onInvoke: (_) {
                  _showGlobalSearch();
                  return null;
                },
              ),
              _NewConversationIntent: CallbackAction<_NewConversationIntent>(
                onInvoke: (_) {
                  setState(() => _section = _AppSection.messages);
                  return null;
                },
              ),
              _SettingsIntent: CallbackAction<_SettingsIntent>(
                onInvoke: (_) {
                  setState(() => _section = _AppSection.settings);
                  return null;
                },
              ),
              _EscapeIntent: CallbackAction<_EscapeIntent>(
                onInvoke: (_) {
                  setState(() => _section = _AppSection.home);
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: LayoutBuilder(builder: (context, constraints) {
                final desktop = constraints.maxWidth >= 1050;
                final navigation = desktop ? _desktopNavigation : _mobileNavigation;
                final activeIndex = navigation.indexWhere((item) => item.section == _section);
                final selectedIndex = activeIndex < 0 ? 0 : activeIndex;
                final pages = navigation.map(_pageFor).toList(growable: false);
                return Scaffold(
                  appBar: !desktop
                      ? AppBar(
                          automaticallyImplyLeading: false,
                          titleSpacing: 16,
                          title: const _AppMark(),
                          actions: [
                            AnimatedBuilder(
                              animation: _connectivity,
                              builder: (_, __) => _ConnectivityChip(status: _connectivity.status),
                            ),
                            const SizedBox(width: 8),
                          ],
                        )
                      : null,
                  body: Row(children: [
                    if (desktop)
                      NavigationRail(
                        selectedIndex: selectedIndex,
                        onDestinationSelected: (value) => setState(() => _section = navigation[value].section),
                        labelType: NavigationRailLabelType.all,
                        leading: const Padding(
                          padding: EdgeInsets.only(top: 12, bottom: 20),
                          child: _AppMark(),
                        ),
                        destinations: navigation.map((item) => NavigationRailDestination(
                          icon: Icon(item.icon), selectedIcon: Icon(item.selectedIcon), label: Text(item.label),
                        )).toList(growable: false),
                      ),
                    Expanded(
                      child: IndexedStack(
                        index: selectedIndex,
                        children: pages,
                      ),
                    ),
                  ]),
                  bottomNavigationBar: desktop
                      ? null
                      : NavigationBar(
                          selectedIndex: selectedIndex,
                          onDestinationSelected: (value) => setState(() => _section = navigation[value].section),
                          destinations: navigation.map((item) => NavigationDestination(
                            icon: Icon(item.icon), selectedIcon: Icon(item.selectedIcon), label: item.label,
                          )).toList(growable: false),
                        ),
                );
              }),
            ),
          ),
        );
      },
    );
  }

  Widget _pageFor(_NavigationItem item) => switch (item.section) {
    _AppSection.home => SocialFeedPage(auth: widget.accountAuth),
    _AppSection.explore => ExplorePage(auth: widget.accountAuth),
    _AppSection.create => CreatePostPage(auth: widget.accountAuth),
    _AppSection.messages => _MessagesDestination(
        meshClient: widget.meshClient,
        accountAuth: widget.accountAuth,
      ),
    _AppSection.notifications => NotificationsPage(auth: widget.accountAuth),
    _AppSection.profile => OwnProfilePage(auth: widget.accountAuth, preferences: widget.preferences, meshClient: widget.meshClient),
    _AppSection.settings => SettingsPage(
      auth: widget.accountAuth,
      preferences: widget.preferences,
      meshClient: widget.meshClient,
    ),
    _AppSection.mesh => MeshDashboardPage(meshClient: widget.meshClient),
  };

  Future<void> _showGlobalSearch() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        final query = controller.text.trim().toLowerCase();
        final messages = query.isEmpty
            ? const <LocalMessage>[]
            : widget.meshClient.messages
                .where((message) =>
                    message.body.toLowerCase().contains(query) ||
                    message.author.toLowerCase().contains(query))
                .take(30)
                .toList();
        final people = query.isEmpty
            ? const <FriendProfile>[]
            : widget.meshClient.friends
                .where(
                    (friend) => friend.username.toLowerCase().contains(query))
                .take(10)
                .toList();
        return AlertDialog(
          title: const Text('Search Sejilo'),
          content: SizedBox(
            width: 560,
            height: 420,
            child: Column(children: [
              TextField(
                controller: controller,
                autofocus: true,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Messages and people',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                  child: query.isEmpty
                      ? const _CompactEmptyState(
                          icon: Icons.keyboard,
                          title: 'Start typing to search',
                          body: 'Tip: press Ctrl+K from anywhere.')
                      : (messages.isEmpty && people.isEmpty)
                          ? const _CompactEmptyState(
                              icon: Icons.search_off,
                              title: 'No results',
                              body: 'Try a different name or phrase.')
                          : ListView(children: [
                              ...people.map((friend) => ListTile(
                                    leading: const CircleAvatar(
                                        child: Icon(Icons.person_outline)),
                                    title: Text(friend.username),
                                    subtitle: const Text('Trusted contact'),
                                    onTap: () {
                                      widget.meshClient
                                          .openFriendConversation(friend);
                                      setState(() => _section = _AppSection.messages);
                                      Navigator.pop(context);
                                    },
                                  )),
                              ...messages.map((message) => ListTile(
                                    leading:
                                        const Icon(Icons.chat_bubble_outline),
                                    title: Text(
                                        message.body.isEmpty
                                            ? 'Attachment'
                                            : message.body,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Text(
                                        '${message.author} · ${message.timeLabel}'),
                                    onTap: () {
                                      setState(() => _section = _AppSection.messages);
                                      Navigator.pop(context);
                                    },
                                  )),
                            ])),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'))
          ],
        );
      }),
    );
    controller.dispose();
  }
}

enum _AppSection { home, explore, create, messages, notifications, profile, settings, mesh }

class _NavigationItem {
  const _NavigationItem(this.section, this.label, this.icon, this.selectedIcon);
  final _AppSection section;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _mobileNavigation = <_NavigationItem>[
  _NavigationItem(_AppSection.home, 'Home', Icons.home_outlined, Icons.home_filled),
  _NavigationItem(_AppSection.explore, 'Explore', Icons.search_rounded, Icons.search),
  _NavigationItem(_AppSection.create, 'Create', Icons.add_box_outlined, Icons.add_box_rounded),
  _NavigationItem(_AppSection.messages, 'Messages', Icons.send_outlined, Icons.send_rounded),
  _NavigationItem(_AppSection.profile, 'Profile', Icons.account_circle_outlined, Icons.account_circle_rounded),
];


const _desktopNavigation = <_NavigationItem>[
  _NavigationItem(_AppSection.home, 'Home', Icons.home_outlined, Icons.home_filled),
  _NavigationItem(_AppSection.explore, 'Explore', Icons.search_rounded, Icons.search),
  _NavigationItem(_AppSection.create, 'Create', Icons.add_box_outlined, Icons.add_box_rounded),
  _NavigationItem(_AppSection.messages, 'Messages', Icons.send_outlined, Icons.send_rounded),
  _NavigationItem(_AppSection.notifications, 'Notifications', Icons.favorite_border_rounded, Icons.favorite_rounded),
  _NavigationItem(_AppSection.profile, 'Profile', Icons.account_circle_outlined, Icons.account_circle_rounded),
  _NavigationItem(_AppSection.mesh, 'Mesh', Icons.hub_outlined, Icons.hub_rounded),
  _NavigationItem(_AppSection.settings, 'Settings', Icons.settings_outlined, Icons.settings),
];


class _SearchIntent extends Intent {
  const _SearchIntent();
}

class _NewConversationIntent extends Intent {
  const _NewConversationIntent();
}

class _SettingsIntent extends Intent {
  const _SettingsIntent();
}

class _EscapeIntent extends Intent {
  const _EscapeIntent();
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _AppMark(size: 58),
            SizedBox(height: 20),
            Text('Preparing your private local vault…',
                style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 18),
            SizedBox(width: 180, child: LinearProgressIndicator()),
          ]),
        ),
      );
}
class _AppMark extends StatelessWidget {
  const _AppMark({this.size = 30});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Sejilo Chat logo',
        image: true,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [SejiloColors.secondary, SejiloColors.primary],
            ),
            borderRadius: BorderRadius.circular(size * .28),
          ),
          child: Icon(Icons.forum_rounded,
              size: size * .58, color: Colors.white),
        ),
      );
}

/// Connectivity status pill shown in the AppBar.
class _ConnectivityChip extends StatelessWidget {
  const _ConnectivityChip({required this.status});
  final ConnectivityStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ConnectivityStatus.online => ('Online', SejiloColors.statusOnline),
      ConnectivityStatus.meshConnected => ('Mesh', SejiloColors.statusMesh),
      ConnectivityStatus.offline => ('Offline', SejiloColors.statusOffline),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(SejiloRadius.pill),
        border: Border.all(color: color.withAlpha(70), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
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


class _OnboardingScreen extends StatefulWidget {
  const _OnboardingScreen({required this.meshClient});
  final MeshClient meshClient;

  @override
  State<_OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<_OnboardingScreen> {
  final _name = TextEditingController();
  int _step = 0;
  int _avatar = 0;
  bool _busy = false;

  static const _avatars = <IconData>[
    Icons.wb_sunny_outlined,
    Icons.terrain_outlined,
    Icons.water_drop_outlined,
    Icons.bolt_outlined,
    Icons.eco_outlined,
    Icons.nightlight_outlined,
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_step == 0) {
      setState(() => _step = 1);
      return;
    }
    if (_step == 1) {
      if (_name.text.trim().isEmpty) return;
      setState(() => _step = 2);
      return;
    }
    setState(() => _busy = true);
    try {
      if (Platform.isAndroid) {
        final status = await const MethodChannel('sejilo/permissions')
                .invokeMapMethod<dynamic, dynamic>('requestEssential') ??
            const <dynamic, dynamic>{};
        final bluetoothGranted = status['bluetoothScan'] == true &&
            status['bluetoothConnect'] == true &&
            status['bluetoothAdvertise'] == true;
        if (bluetoothGranted) {
          await widget.meshClient.setPresence(enabled: true);
        }
      }
      await widget.meshClient.setAvatar(_avatar);
      await widget.meshClient.setUsername(_name.text);
    } on PlatformException {
      // The user can finish onboarding even when Bluetooth is unavailable.
      await widget.meshClient.setAvatar(_avatar);
      await widget.meshClient.setUsername(_name.text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const _AppMark(size: 54),
                          const SizedBox(width: 16),
                          const Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('Sejilo Chat',
                                    style: TextStyle(
                                        fontSize: 27,
                                        fontWeight: FontWeight.w800)),
                                Text('Nearby. Private. Resilient.'),
                              ])),
                          Text('${_step + 1} / 3',
                              style: TextStyle(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 28),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: switch (_step) {
                            0 => const _OnboardingCopy(
                                key: ValueKey(0),
                                icon: Icons.bluetooth_searching,
                                title: 'Chat without the internet',
                                body:
                                    'Sejilo finds nearby devices over Bluetooth and can relay signed messages through compatible peers. Keep the app open during the first connection.',
                                points: [
                                  'No account or phone number',
                                  'Messages stay on your devices',
                                  'You decide when you are discoverable'
                                ],
                              ),
                            1 => Column(
                                  key: const ValueKey(1),
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Make it yours',
                                        style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 8),
                                    const Text(
                                        'Choose a local display name and avatar. You can change both later.'),
                                    const SizedBox(height: 20),
                                    TextField(
                                        controller: _name,
                                        autofocus: true,
                                        maxLength: 32,
                                        textInputAction: TextInputAction.done,
                                        onSubmitted: (_) => _continue(),
                                        decoration: const InputDecoration(
                                            labelText: 'Display name',
                                            prefixIcon:
                                                Icon(Icons.person_outline))),
                                    const SizedBox(height: 8),
                                    Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: List.generate(
                                            _avatars.length,
                                            (index) => ChoiceChip(
                                                  selected: _avatar == index,
                                                  onSelected: (_) => setState(
                                                      () => _avatar = index),
                                                  avatar: Icon(_avatars[index]),
                                                  label: Text(
                                                      'Avatar ${index + 1}'),
                                                ))),
                                  ]),
                            _ => const _OnboardingCopy(
                                key: ValueKey(2),
                                icon: Icons.shield_outlined,
                                title: 'You stay in control',
                                body:
                                    'Bluetooth permission is needed to discover and connect. Camera, microphone, photos, location, and notifications are requested only when their features need them.',
                                points: [
                                  'Unknown devices are not trusted automatically',
                                  'Received files never open automatically',
                                  'Direct chats are signed, but not yet end-to-end encrypted'
                                ],
                              ),
                          },
                        ),
                        const SizedBox(height: 28),
                        Row(children: [
                          if (_step > 0)
                            TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() => _step--),
                                child: const Text('Back')),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: _busy ? null : _continue,
                            icon: _busy
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : Icon(_step == 2
                                    ? Icons.check_rounded
                                    : Icons.arrow_forward_rounded),
                            label: Text(
                                _step == 2 ? 'Start chatting' : 'Continue'),
                          ),
                        ]),
                      ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingCopy extends StatelessWidget {
  const _OnboardingCopy(
      {required this.icon,
      required this.title,
      required this.body,
      required this.points,
      super.key});
  final IconData icon;
  final String title;
  final String body;
  final List<String> points;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 46, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 18),
        Text(title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(body, style: const TextStyle(height: 1.45)),
        const SizedBox(height: 18),
        ...points.map((point) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                const Icon(Icons.check_circle_outline, size: 19),
                const SizedBox(width: 10),
                Expanded(child: Text(point)),
              ]),
            )),
      ]);
}

class _CompactEmptyState extends StatelessWidget {
  const _CompactEmptyState(
      {required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 42, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text(body, textAlign: TextAlign.center),
      ]));
}

// ─── Messages destination — wraps Mesh + Online in tabs ────────────────────

class _MessagesDestination extends StatefulWidget {
  const _MessagesDestination({
    required this.meshClient,
    required this.accountAuth,
  });

  final MeshClient meshClient;
  final AccountAuthController accountAuth;

  @override
  State<_MessagesDestination> createState() => _MessagesDestinationState();
}

class _MessagesDestinationState extends State<_MessagesDestination>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final OnlineMessagingController _onlineMessaging;

  @override
  void initState() {
    super.initState();
    _onlineMessaging = OnlineMessagingController(auth: widget.accountAuth);
    // On web/desktop, only Online tab. On mobile, Online + Nearby.
    _tabController = TabController(
      length: PlatformCapabilities.meshSupported ? 2 : 1,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _onlineMessaging.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasMesh = PlatformCapabilities.meshSupported;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages',
            style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: hasMesh
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Online', icon: Icon(Icons.wifi_rounded)),
                  Tab(text: 'Nearby', icon: Icon(Icons.bluetooth_rounded)),
                ],
              )
            : null,
      ),
      body: hasMesh
          ? TabBarView(
              controller: _tabController,
              children: [
                // Full online 1-to-1 & group conversations
                OnlineConversationsView(
                  messagingController: _onlineMessaging,
                  authController: widget.accountAuth,
                ),
                // Existing Mesh chat — completely unchanged
                _MeshChatBody(meshClient: widget.meshClient),
              ],
            )
          : Column(
              children: [
                Expanded(
                  child: OnlineConversationsView(
                    messagingController: _onlineMessaging,
                    authController: widget.accountAuth,
                  ),
                ),
                // Platform info card for web/desktop
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Theme.of(context).colorScheme.surface,
                  child: Row(
                    children: [
                      Icon(Icons.bluetooth_disabled_rounded,
                          size: 18,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: .5)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Mesh Chat is available on Android and iOS.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: .5),
                          ),
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


// ─── Mesh chat body extracted from _ChatDestination ─────────────────────────

class _MeshChatBody extends StatelessWidget {
  const _MeshChatBody({required this.meshClient});
  final MeshClient meshClient;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;
        return Row(
          children: [
            if (isWide) _Sidebar(meshClient: meshClient),
            Expanded(
              child: _ChatPanel(meshClient: meshClient, showHeader: isWide),
            ),
          ],
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.meshClient});

  final MeshClient meshClient;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 268,
      decoration: const BoxDecoration(
          color: Color(0xFF162426),
          border: Border(right: BorderSide(color: Color(0xFF26393B)))),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _BrandHeader(),
              const SizedBox(height: 28),
              const Text('CONVERSATIONS',
                  style: TextStyle(
                      color: Color(0xFF8FA9A5),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1)),
              const SizedBox(height: 10),
              _ChannelTile(
                  icon: Icons.forum_rounded,
                  title: 'Nearby mesh channel',
                  subtitle: 'Signed public BLE messages',
                  selected: meshClient.activeConversationId == null,
                  onTap: meshClient.openPublicChannel),
              const SizedBox(height: 22),
              Row(children: [
                const Expanded(
                    child: Text('FRIENDS',
                        style: TextStyle(
                            color: Color(0xFF8FA9A5),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1))),
                IconButton(
                    onPressed: () => _showFriendsSheet(context, meshClient),
                    icon: const Icon(Icons.manage_accounts_outlined, size: 18),
                    tooltip: 'Manage friends')
              ]),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: meshClient.friends.isEmpty
                      ? const [
                          Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 7),
                            child: Text(
                              'Add a verified friend code to begin.',
                              style: TextStyle(
                                  color: Color(0xFF8FA9A5), fontSize: 12),
                            ),
                          ),
                        ]
                      : meshClient.friends
                          .map((friend) => _ChannelTile(
                              icon: Icons.person_outline_rounded,
                              title: friend.username,
                              subtitle: friend.verificationCode,
                              selected:
                                  meshClient.activeConversationId == friend.id,
                              onTap: () =>
                                  meshClient.openFriendConversation(friend)))
                          .toList(growable: false),
                ),
              ),
              _IdentityCard(meshClient: meshClient, colors: colors),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                  onPressed: () => _showProfileDialog(context, meshClient),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: Text(meshClient.username),
                  style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      minimumSize: const Size.fromHeight(42))),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showProfileDialog(
    BuildContext context, MeshClient meshClient) async {
  final controller = TextEditingController(text: meshClient.username);
  await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
              title: const Text('Your username'),
              content: TextField(
                  controller: controller,
                  maxLength: 32,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Username')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () async {
                      await meshClient.setUsername(controller.text);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('Save'))
              ]));
  controller.dispose();
}

Future<void> _showAddFriendDialog(
    BuildContext context, MeshClient meshClient) async {
  final usernameController = TextEditingController();
  final idController = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Add a friend'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
            controller: usernameController,
            maxLength: 32,
            decoration: const InputDecoration(labelText: 'Friend username')),
        TextField(
            controller: idController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
                labelText: 'Friend verification code',
                hintText: 'SJ-ABCD-EF23-417')),
        const Text(
          'A short code works while that verified peer is nearby. Scan their QR invite when adding them remotely.',
          style: TextStyle(color: Color(0xFF9AB2AF), fontSize: 12),
        ),
        if (Platform.isAndroid)
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: () async {
                    final scanned = await Navigator.of(dialogContext)
                        .push<_FriendCode>(MaterialPageRoute(
                            builder: (_) => const _FriendScannerPage()));
                    if (scanned != null) {
                      usernameController.text = scanned.username;
                      idController.text = scanned.id;
                    }
                  },
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Scan QR code'))),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () async {
              final added = await meshClient.addFriend(
                  username: usernameController.text, id: idController.text);
              if (!dialogContext.mounted) return;
              if (added) {
                Navigator.pop(dialogContext);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                    'Use the short code of a verified nearby peer, or scan a valid QR invite. The friend may already be saved.',
                  ),
                ));
              }
            },
            child: const Text('Add'))
      ],
    ),
  );
  usernameController.dispose();
  idController.dispose();
}

Future<void> _showFriendsSheet(
    BuildContext context, MeshClient meshClient) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => AnimatedBuilder(
      animation: meshClient,
      builder: (context, _) {
        final code = meshClient.myVerificationCode;
        final fullKey = meshClient.myFullVerificationKey;
        final invite = fullKey == null
            ? null
            : Uri(
                scheme: 'sejilochat',
                host: 'friend',
                queryParameters: {
                  'username': meshClient.username,
                  'id': fullKey,
                },
              ).toString();
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.78,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
                child: Row(children: [
                  const Expanded(
                    child: Text('Friends and verification',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  FilledButton.icon(
                    onPressed: () => _showAddFriendDialog(context, meshClient),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Add'),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('YOUR VERIFICATION CODE',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1)),
                        const SizedBox(height: 8),
                        SelectableText(code ?? 'Preparing identity keys...',
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        const Text(
                          'Compare this short checksum code while both devices are nearby. Sejilo still stores and verifies the complete Ed25519 public key internally; QR invites carry that full key.',
                          style:
                              TextStyle(color: Color(0xFF9AB2AF), fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: invite == null
                              ? null
                              : () async {
                                  await Clipboard.setData(
                                      ClipboardData(text: invite));
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Friend invite copied. Send it through a trusted channel.')),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('Copy my friend invite'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('SAVED FRIENDS',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1)),
                ),
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.public_rounded)),
                title: const Text('Public mesh channel'),
                subtitle: const Text('Signed messages visible to nearby peers'),
                onTap: () {
                  meshClient.openPublicChannel();
                  Navigator.pop(sheetContext);
                },
              ),
              Expanded(
                child: meshClient.friends.isEmpty
                    ? const Center(
                        child: Text('No saved friends yet.',
                            style: TextStyle(color: Color(0xFF9AB2AF))))
                    : ListView.builder(
                        itemCount: meshClient.friends.length,
                        itemBuilder: (context, index) {
                          final friend = meshClient.friends[index];
                          return ListTile(
                            leading: const CircleAvatar(
                                child: Icon(Icons.person_outline_rounded)),
                            title: Text(friend.username),
                            subtitle: Text(
                              friend.verificationCode,
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                            onTap: () {
                              meshClient.openFriendConversation(friend);
                              Navigator.pop(sheetContext);
                            },
                            trailing: IconButton(
                              onPressed: () => _confirmDeleteFriend(
                                  context, meshClient, friend),
                              icon: const Icon(Icons.delete_outline_rounded),
                              tooltip: 'Delete friend',
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),
        );
      },
    ),
  );
}

Future<void> _confirmDeleteFriend(
    BuildContext context, MeshClient meshClient, FriendProfile friend) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete ${friend.username}?'),
      content: const Text(
          'This removes the saved contact. It does not delete messages already stored on either device.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete')),
      ],
    ),
  );
  if (confirmed == true) await meshClient.removeFriend(friend.id);
}

class _FriendCode {
  const _FriendCode({required this.username, required this.id});

  final String username;
  final String id;
}

class _FriendScannerPage extends StatelessWidget {
  const _FriendScannerPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan friend code')),
      body: MobileScanner(
        onDetect: (capture) {
          final rawValue = capture.barcodes.firstOrNull?.rawValue;
          if (rawValue == null) return;
          final uri = Uri.tryParse(rawValue);
          if (uri == null ||
              uri.scheme != 'sejilochat' ||
              uri.host != 'friend') {
            return;
          }
          final username = uri.queryParameters['username'];
          final id = uri.queryParameters['id'];
          if (username == null || id == null) return;
          Navigator.pop(context, _FriendCode(username: username, id: id));
        },
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
              color: Color(0xFF62E4BE),
              borderRadius: BorderRadius.all(Radius.circular(12))),
          child: SizedBox(
              width: 42,
              height: 42,
              child: Center(
                  child: Text('S',
                      style: TextStyle(
                          color: Color(0xFF0C2520),
                          fontSize: 22,
                          fontWeight: FontWeight.w900)))),
        ),
        SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SejiloChat',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
          Text('Private by design',
              style: TextStyle(color: Color(0xFF9AB2AF), fontSize: 12))
        ])),
      ],
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.selected,
      this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: selected ? const Color(0xFF224138) : Colors.transparent,
            borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(icon,
              color:
                  selected ? const Color(0xFF7DF0CD) : const Color(0xFF9AB2AF)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(subtitle,
                    style:
                        const TextStyle(color: Color(0xFF9AB2AF), fontSize: 11))
              ]))
        ]),
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.meshClient, required this.colors});

  final MeshClient meshClient;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final fingerprint = meshClient.myVerificationCode;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFF0E191B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2A4040))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.verified_user_outlined,
              size: 16, color: Color(0xFF7DF0CD)),
          SizedBox(width: 7),
          Text('DEVICE IDENTITY',
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1))
        ]),
        const SizedBox(height: 9),
        Text(fingerprint ?? 'Preparing secure keys…',
            style: const TextStyle(
                fontFamily: 'monospace', color: Color(0xFFCFE4E0))),
      ]),
    );
  }
}

class _ChatPanel extends StatefulWidget {
  const _ChatPanel({required this.meshClient, required this.showHeader});

  final MeshClient meshClient;
  final bool showHeader;

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final _searchController = TextEditingController();
  bool _showSearch = false;
  LocalMessage? _replyTo;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.showHeader) _ChatHeader(meshClient: widget.meshClient),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            if (widget.meshClient.pinnedMessages.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: const Color(0xFF1C3432),
                    borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.push_pin_outlined,
                      size: 15, color: Color(0xFF8BE8CD)),
                  const SizedBox(width: 5),
                  Text('${widget.meshClient.pinnedMessages.length} pinned',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
            const Spacer(),
            IconButton(
              onPressed: () => setState(() => _showSearch = !_showSearch),
              icon: Icon(
                  _showSearch ? Icons.close_rounded : Icons.search_rounded),
              tooltip: 'Search messages',
            ),
          ]),
        ),
        if (_showSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search encrypted local messages'),
            ),
          ),
        _SecurityBanner(meshClient: widget.meshClient),
        Expanded(
            child: _MessageList(
          messages: widget.meshClient.searchMessages(_searchController.text),
          onPin: widget.meshClient.togglePin,
          onReact: widget.meshClient.react,
          onDelete: widget.meshClient.deleteMessage,
          onEdit: widget.meshClient.editMessage,
          onReply: (message) => setState(() => _replyTo = message),
          onRetry: (message) => widget.meshClient.queueMessage(
            message.body,
            attachmentPath: message.attachmentPath,
            attachmentType: message.attachmentType,
            replyToId: message.replyToId,
          ),
        )),
        MessageComposer(
            enabled: widget.meshClient.isReady &&
                !widget.meshClient.isDirectConversation,
            preferences: widget.meshClient.preferences,
            replyTo: _replyTo,
            onCancelReply: () => setState(() => _replyTo = null),
            onSend: (body, {attachmentPath, attachmentType}) async {
              await widget.meshClient.queueMessage(
                body,
                attachmentPath: attachmentPath,
                attachmentType: attachmentType,
                replyToId: _replyTo?.id,
              );
              if (mounted) setState(() => _replyTo = null);
            }),
      ],
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.meshClient});

  final MeshClient meshClient;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
          color: Color(0xFF101D1F),
          border: Border(bottom: BorderSide(color: Color(0xFF26393B)))),
      child: Row(children: [
        CircleAvatar(
            radius: 23,
            backgroundColor: const Color(0xFF224138),
            child: Icon(
              meshClient.isDirectConversation
                  ? Icons.person_outline_rounded
                  : meshClient.isGroupConversation
                      ? Icons.groups_rounded
                      : Icons.bluetooth_searching_rounded,
              color: const Color(0xFF7DF0CD),
            )),
        const SizedBox(width: 13),
        Expanded(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(meshClient.activeConversationName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 19)),
              const SizedBox(height: 3),
              Text(
                  meshClient.isDirectConversation
                      ? 'Private sending blocked until reviewed end-to-end encryption is available'
                      : meshClient.isGroupConversation
                          ? 'Locality group chat over the nearby BLE mesh'
                          : 'Signed public messages visible to nearby Sejilo users',
                  style:
                      const TextStyle(color: Color(0xFF9AB2AF), fontSize: 13))
            ])),
        _ClearButton(meshClient: meshClient),
      ]),
    );
  }
}

class _SecurityBanner extends StatelessWidget {
  const _SecurityBanner({required this.meshClient});

  final MeshClient meshClient;

  @override
  Widget build(BuildContext context) {
    final hasError = meshClient.initializationError != null;
    final ready = meshClient.isReady;
    final color = hasError
        ? const Color(0xFFF9A8A8)
        : ready
            ? const Color(0xFF7DF0CD)
            : const Color(0xFFF2CF80);
    final icon = hasError
        ? Icons.error_outline
        : ready
            ? Icons.lock_rounded
            : Icons.hourglass_top_rounded;
    final text = hasError
        ? meshClient.initializationError!
        : ready
            ? meshClient.isMeshAvailable
                ? meshClient.isDirectConversation
                    ? 'P0 safety gate: plaintext-compatible direct messages cannot be sent'
                    : meshClient.isGroupConversation
                        ? 'Signed locality-group chat over nearby Bluetooth'
                        : 'Nearby public mesh - no internet required'
                : 'Local vault ready - enable visibility in Mesh to connect'
            : 'Creating your device identity…';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.28))),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 11.5)))
      ]),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList(
      {required this.messages,
      required this.onPin,
      required this.onReact,
      required this.onDelete,
      required this.onEdit,
      required this.onReply,
      required this.onRetry});

  final List<LocalMessage> messages;
  final Future<void> Function(String) onPin;
  final Future<void> Function(String, String) onReact;
  final Future<void> Function(String) onDelete;
  final Future<void> Function(String, String) onEdit;
  final ValueChanged<LocalMessage> onReply;
  final Future<void> Function(LocalMessage) onRetry;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.chat_bubble_outline_rounded,
            size: 42, color: Color(0xFF70908B)),
        SizedBox(height: 12),
        Text('No messages in this conversation',
            style: TextStyle(fontWeight: FontWeight.w700)),
        SizedBox(height: 4),
        Text('Send through the nearby Bluetooth mesh.',
            style: TextStyle(color: Color(0xFF9AB2AF)))
      ]));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      itemCount: messages.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _MessageBubble(
          message: messages[index],
          onPin: onPin,
          onReact: onReact,
          onDelete: onDelete,
          onEdit: onEdit,
          onReply: onReply,
          onRetry: onRetry),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble(
      {required this.message,
      required this.onPin,
      required this.onReact,
      required this.onDelete,
      required this.onEdit,
      required this.onReply,
      required this.onRetry});

  final LocalMessage message;
  final Future<void> Function(String) onPin;
  final Future<void> Function(String, String) onReact;
  final Future<void> Function(String) onDelete;
  final Future<void> Function(String, String) onEdit;
  final ValueChanged<LocalMessage> onReply;
  final Future<void> Function(LocalMessage) onRetry;

  @override
  Widget build(BuildContext context) {
    final ownMessage = message.author == 'You';
    final bubbleColor =
        ownMessage ? const Color(0xFF245E50) : const Color(0xFF18282B);
    return Align(
      alignment: ownMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: GestureDetector(
          onLongPress:
              message.id.isEmpty ? null : () => _showMessageActions(context),
          onSecondaryTapDown: message.id.isEmpty
              ? null
              : (details) => _showDesktopMenu(context, details.globalPosition),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
                color: bubbleColor,
                border: Border.all(
                    color: ownMessage
                        ? const Color(0xFF56AF94)
                        : const Color(0xFF2B4042)),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 10,
                      offset: Offset(0, 3))
                ],
                borderRadius: BorderRadius.circular(19).copyWith(
                    bottomRight: ownMessage ? const Radius.circular(5) : null,
                    bottomLeft: ownMessage ? null : const Radius.circular(5))),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (message.isPinned) ...[
                  const Icon(Icons.push_pin,
                      size: 13, color: Color(0xFF7DF0CD)),
                  const SizedBox(width: 5),
                ],
                Text(message.author,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFD4F6ED))),
                const SizedBox(width: 8),
                Text(message.timeLabel,
                    style:
                        const TextStyle(fontSize: 11, color: Color(0xFFACC8C3)))
              ]),
              if (message.attachmentType == 'photo' &&
                  message.attachmentPath != null &&
                  File(message.attachmentPath!).existsSync())
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(File(message.attachmentPath!),
                            height: 220, fit: BoxFit.cover)))
              else if (message.attachmentType == 'voice' &&
                  message.attachmentPath != null)
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _VoiceNotePlayer(path: message.attachmentPath!)),
              if (message.attachmentType == 'file' &&
                  message.attachmentPath != null)
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.description_outlined),
                    const SizedBox(width: 8),
                    Flexible(
                        child: Text(
                            File(message.attachmentPath!).uri.pathSegments.last,
                            overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    const Tooltip(
                        message: 'Received files never open automatically',
                        child: Icon(Icons.lock_outline, size: 16)),
                  ]),
                ),
              if (message.body.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SelectableText(message.body,
                        style: const TextStyle(height: 1.45, fontSize: 14.5))),
              if (message.reactions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                      spacing: 6,
                      children: message.reactions.entries
                          .map((entry) => Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text('${entry.key} ${entry.value}'),
                              ))
                          .toList()),
                ),
              if (ownMessage)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_deliveryIcon(message.deliveryState),
                        size: 12, color: const Color(0xFFACC8C3)),
                    const SizedBox(width: 4),
                    Text(message.deliveryState,
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFFACC8C3))),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  IconData _deliveryIcon(String state) {
    if (state.startsWith('failed')) return Icons.error_outline;
    if (state.startsWith('delivered')) return Icons.done_all_rounded;
    if (state.startsWith('sent')) return Icons.done_rounded;
    return Icons.schedule_rounded;
  }

  Future<void> _showDesktopMenu(BuildContext context, Offset position) async {
    final own = message.author == 'You';
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        const PopupMenuItem(
            value: 'reply',
            child: ListTile(
                leading: Icon(Icons.reply_rounded), title: Text('Reply'))),
        if (message.body.isNotEmpty)
          const PopupMenuItem(
              value: 'copy',
              child: ListTile(
                  leading: Icon(Icons.copy_rounded), title: Text('Copy'))),
        if (own && message.body.isNotEmpty)
          const PopupMenuItem(
              value: 'edit',
              child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit locally'))),
        PopupMenuItem(
            value: 'pin',
            child: ListTile(
                leading: const Icon(Icons.push_pin_outlined),
                title: Text(message.isPinned ? 'Unpin' : 'Pin'))),
        if (own && message.deliveryState.startsWith('failed'))
          const PopupMenuItem(
              value: 'retry',
              child: ListTile(
                  leading: Icon(Icons.refresh_rounded), title: Text('Retry'))),
        const PopupMenuDivider(),
        const PopupMenuItem(
            value: 'delete',
            child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Delete locally'))),
      ],
    );
    if (!context.mounted || action == null) return;
    await _handleAction(context, action);
  }

  Future<void> _handleAction(BuildContext context, String action) async {
    switch (action) {
      case 'reply':
        onReply(message);
        return;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.body));
        return;
      case 'pin':
        await onPin(message.id);
        return;
      case 'retry':
        await onRetry(message);
        return;
      case 'delete':
        await onDelete(message.id);
        return;
      case 'edit':
        final controller = TextEditingController(text: message.body);
        final value = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
                  title: const Text('Edit local copy'),
                  content: TextField(
                      controller: controller,
                      autofocus: true,
                      minLines: 1,
                      maxLines: 6),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, controller.text),
                        child: const Text('Save locally')),
                  ],
                ));
        controller.dispose();
        if (value != null) await onEdit(message.id, value);
        return;
    }
  }

  Future<void> _showMessageActions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(
                spacing: 8,
                children: ['👍', '❤️', '😂', '😮', '🙏']
                    .map((emoji) => ActionChip(
                          label:
                              Text(emoji, style: const TextStyle(fontSize: 20)),
                          onPressed: () async {
                            Navigator.pop(sheetContext);
                            await onReact(message.id, emoji);
                          },
                        ))
                    .toList()),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(sheetContext);
                onReply(message);
              },
            ),
            if (message.body.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy text'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await Clipboard.setData(ClipboardData(text: message.body));
                },
              ),
            ListTile(
              leading: Icon(
                  message.isPinned ? Icons.push_pin_outlined : Icons.push_pin),
              title: Text(message.isPinned ? 'Unpin message' : 'Pin message'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await onPin(message.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete locally'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await onDelete(message.id);
              },
            ),
          ]),
        ),
      ),
    );
  }
}

class _VoiceNotePlayer extends StatefulWidget {
  const _VoiceNotePlayer({required this.path});

  final String path;

  @override
  State<_VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<_VoiceNotePlayer> {
  final AudioPlayer _player = AudioPlayer();
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _player.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _position = Duration.zero);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (!File(widget.path).existsSync()) {
      setState(() => _error =
          'This voice-note file is no longer available on this device.');
      return;
    }
    try {
      if (_isPlaying) {
        await _player.pause();
      } else if (_position > Duration.zero) {
        await _player.resume();
      } else {
        await _player.play(DeviceFileSource(widget.path));
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to play this voice note.');
    }
  }

  String _format(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final maxMilliseconds =
        _duration.inMilliseconds <= 0 ? 1 : _duration.inMilliseconds;
    final value = _position.inMilliseconds.clamp(0, maxMilliseconds).toDouble();
    return Container(
      width: 260,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: const Color(0xFF102A27),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF3C7C6C))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton.filledTonal(
              onPressed: _togglePlayback,
              icon: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
              tooltip: _isPlaying ? 'Pause voice note' : 'Play voice note'),
          const SizedBox(width: 8),
          const Icon(Icons.graphic_eq_rounded, color: Color(0xFF7DF0CD)),
          const SizedBox(width: 6),
          Expanded(
              child: Text(_error ?? 'Voice note',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: Color(0xFFD6F5ED)))),
        ]),
        Slider(
            value: value,
            max: maxMilliseconds.toDouble(),
            onChanged: _error == null
                ? (milliseconds) =>
                    _player.seek(Duration(milliseconds: milliseconds.round()))
                : null),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('${_format(_position)}  /  ${_format(_duration)}',
                style:
                    const TextStyle(fontSize: 11, color: Color(0xFFABCDC5)))),
      ]),
    );
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.meshClient});

  final MeshClient meshClient;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: !meshClient.isReady
          ? null
          : () async {
              final shouldClear = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                          title: const Text('Clear local vault?'),
                          content: const Text(
                              'This deletes the encrypted local message history from this device.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel')),
                            FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Clear'))
                          ]));
              if (shouldClear == true) await meshClient.clearLocalMessages();
            },
      icon: const Icon(Icons.delete_outline_rounded),
      tooltip: 'Clear encrypted local messages',
    );
  }
}

class MessageComposer extends StatefulWidget {
  const MessageComposer(
      {required this.enabled,
      required this.preferences,
      required this.onSend,
      this.replyTo,
      this.onCancelReply,
      super.key});

  final bool enabled;
  final AppPreferences preferences;
  final Future<void> Function(String,
      {String? attachmentPath, String? attachmentType}) onSend;
  final LocalMessage? replyTo;
  final VoidCallback? onCancelReply;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  static const _maxAttachmentBytes = 96 * 1024;
  final TextEditingController _controller = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _recordingTimer;
  bool _isSending = false;
  bool _isRecording = false;
  String? _attachmentPath;
  String? _attachmentType;
  final AiProvider _localAi = const LocalAiProvider();

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _controller.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _controller.text.trim();
    if (!widget.enabled ||
        _isSending ||
        (message.isEmpty && _attachmentPath == null)) {
      return;
    }
    setState(() => _isSending = true);
    try {
      await widget.onSend(message,
          attachmentPath: _attachmentPath, attachmentType: _attachmentType);
      _controller.clear();
      _attachmentPath = null;
      _attachmentType = null;
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _runAi(AiOperation operation) async {
    final selected =
        _controller.selection.isValid && !_controller.selection.isCollapsed
            ? _controller.selection.textInside(_controller.text)
            : _controller.text;
    if (selected.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select or write a draft first.')),
      );
      return;
    }
    setState(() => _isSending = true);
    try {
      final result = await _localAi.process(AiRequest(
        operation: operation,
        selectedText: selected,
      ));
      if (!mounted) return;
      final replacement = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(result.label),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.lock_outline_rounded),
                title: Text('Only this draft was processed'),
                subtitle:
                    Text('No conversation history or message was uploaded.'),
              ),
              if (result.text != null) SelectableText(result.text!),
              if (result.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...result.warnings.map((warning) => Text('• $warning')),
              ],
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            if (result.text != null)
              FilledButton(
                onPressed: () => Navigator.pop(context, result.text),
                child: const Text('Use draft'),
              ),
          ],
        ),
      );
      if (replacement != null && mounted) {
        final selection = _controller.selection;
        if (selection.isValid && !selection.isCollapsed) {
          _controller.value = TextEditingValue(
            text: _controller.text
                .replaceRange(selection.start, selection.end, replacement),
            selection: TextSelection.collapsed(
                offset: selection.start + replacement.length),
          );
        } else {
          _controller.value = TextEditingValue(
            text: replacement,
            selection: TextSelection.collapsed(offset: replacement.length),
          );
        }
      }
    } on AiUnavailableException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on ArgumentError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('The selected draft is too large for AI processing.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.singleOrNull?.path;
    if (path == null || !mounted) return;
    setState(() => _isSending = true);
    try {
      final prepared = await _preparePhoto(path);
      if (!mounted) return;
      if (prepared == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('This photo could not be reduced for Bluetooth transfer.'),
        ));
        return;
      }
      setState(() {
        _attachmentPath = prepared;
        _attachmentType = 'photo';
      });
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickSmallFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'txt', 'csv', 'json', 'docx'],
      withData: false,
    );
    final path = result?.files.singleOrNull?.path;
    if (path == null || !mounted) return;
    final file = File(path);
    final size = await file.length();
    if (size <= 0 || size > _maxAttachmentBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Small files must be under 96 KB for reliable Bluetooth transfer.'),
        ));
      }
      return;
    }
    setState(() {
      _attachmentPath = path;
      _attachmentType = 'file';
    });
  }

  Future<String?> _preparePhoto(String sourcePath) async {
    final source = await File(sourcePath).readAsBytes();
    final directory = await getApplicationDocumentsDirectory();
    for (final width in const [640, 520, 420, 320, 240, 180]) {
      final codec = await ui.instantiateImageCodec(source, targetWidth: width);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      if (data == null) continue;
      final bytes = data.buffer.asUint8List();
      if (bytes.length <= _maxAttachmentBytes) {
        final path =
            '${directory.path}${Platform.pathSeparator}photo-${DateTime.now().microsecondsSinceEpoch}.png';
        await File(path).writeAsBytes(bytes, flush: true);
        return path;
      }
    }
    return null;
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      final path = await _recorder.stop();
      if (path != null) {
        final file = File(path);
        final exists = await file.exists();
        final isTooLarge = exists && await file.length() > _maxAttachmentBytes;
        if (!mounted) return;
        if (!exists || isTooLarge) {
          setState(() => _isRecording = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Voice notes are limited to about 20 seconds over Bluetooth.'),
          ));
          return;
        }
        setState(() {
          _attachmentPath = path;
          _attachmentType = 'voice';
          _isRecording = false;
        });
      } else if (mounted) {
        setState(() => _isRecording = false);
      }
      return;
    }
    if (!await _recorder.hasPermission()) return;
    final directory = await getApplicationDocumentsDirectory();
    final path =
        '${directory.path}${Platform.pathSeparator}voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
    if (!await _recorder.isEncoderSupported(AudioEncoder.aacLc)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Compressed voice recording is not supported on this device.'),
        ));
      }
      return;
    }
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 32000,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
    if (mounted) {
      setState(() => _isRecording = true);
      _recordingTimer = Timer(const Duration(seconds: 20), () {
        if (mounted && _isRecording) unawaited(_toggleRecording());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
        decoration: const BoxDecoration(
            color: Color(0xFF101A1C),
            border: Border(top: BorderSide(color: Color(0xFF26393B)))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.replyTo != null)
            Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: .10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.reply_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Replying to ${widget.replyTo!.author}',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800)),
                      Text(
                          widget.replyTo!.body.isEmpty
                              ? 'Attachment'
                              : widget.replyTo!.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ])),
                IconButton(
                    onPressed: widget.onCancelReply,
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Cancel reply'),
              ]),
            ),
          if (_attachmentPath != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(children: [
                  Icon(
                      _attachmentType == 'voice'
                          ? Icons.mic_rounded
                          : _attachmentType == 'file'
                              ? Icons.description_outlined
                              : Icons.image_rounded,
                      color: const Color(0xFF7DF0CD)),
                  const SizedBox(width: 7),
                  Expanded(
                      child: Text(
                          _attachmentType == 'voice'
                              ? 'Voice note ready'
                              : _attachmentType == 'file'
                                  ? 'Small file ready (never auto-opened)'
                                  : 'Photo ready',
                          style: const TextStyle(color: Color(0xFFCFE4E0)))),
                  IconButton(
                      onPressed: () => setState(() {
                            _attachmentPath = null;
                            _attachmentType = null;
                          }),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Remove attachment')
                ])),
          LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            return Row(children: [
              if (compact)
                PopupMenuButton<String>(
                  enabled: widget.enabled && !_isSending,
                  tooltip: 'Add attachment',
                  icon: const Icon(Icons.add_rounded),
                  onSelected: (value) {
                    if (value == 'photo') unawaited(_pickPhoto());
                    if (value == 'file') unawaited(_pickSmallFile());
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                        value: 'photo',
                        child: ListTile(
                            leading: Icon(Icons.image_outlined),
                            title: Text('Photo'))),
                    PopupMenuItem(
                        value: 'file',
                        child: ListTile(
                            leading: Icon(Icons.description_outlined),
                            title: Text('Small document'))),
                  ],
                )
              else ...[
                IconButton(
                    onPressed:
                        widget.enabled && !_isSending ? _pickPhoto : null,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    tooltip: 'Attach photo'),
                IconButton(
                    onPressed:
                        widget.enabled && !_isSending ? _pickSmallFile : null,
                    icon: const Icon(Icons.attach_file_rounded),
                    tooltip: 'Attach small document (96 KB max)'),
              ],
              IconButton.filledTonal(
                  onPressed:
                      widget.enabled && !_isSending ? _toggleRecording : null,
                  icon: Icon(_isRecording
                      ? Icons.stop_circle_outlined
                      : Icons.mic_none_rounded),
                  color: _isRecording ? const Color(0xFFF59A9A) : null,
                  tooltip: _isRecording
                      ? 'Stop voice recording'
                      : 'Record voice note'),
              if (widget.preferences.aiEnabled)
                PopupMenuButton<AiOperation>(
                  enabled: widget.enabled && !_isSending,
                  tooltip: '✨ Sejilo AI · On Device',
                  icon: const Icon(Icons.auto_awesome_rounded),
                  onSelected: (operation) => unawaited(_runAi(operation)),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: AiOperation.makeProfessional,
                      child: Text('Make professional · On Device 🔒'),
                    ),
                    PopupMenuItem(
                      value: AiOperation.makeFriendly,
                      child: Text('Make friendly · On Device 🔒'),
                    ),
                    PopupMenuItem(
                      value: AiOperation.makeShorter,
                      child: Text('Make shorter · On Device 🔒'),
                    ),
                    PopupMenuItem(
                      value: AiOperation.makeClearer,
                      child: Text('Make clearer · On Device 🔒'),
                    ),
                    PopupMenuItem(
                      value: AiOperation.fixGrammar,
                      child: Text('Fix grammar · On Device 🔒'),
                    ),
                    PopupMenuItem(
                      value: AiOperation.detectTone,
                      child: Text('Check my draft tone · On Device 🔒'),
                    ),
                  ],
                ),
              Expanded(
                  child: TextField(
                      controller: _controller,
                      enabled: widget.enabled && !_isSending,
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                          hintText: widget.enabled
                              ? compact
                                  ? 'Message'
                                  : 'Write a nearby mesh message'
                              : 'Preparing…',
                          prefixIcon: compact
                              ? null
                              : const Icon(Icons.chat_bubble_outline_rounded,
                                  size: 19),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 13)))),
              const SizedBox(width: 8),
              IconButton.filled(
                  onPressed: widget.enabled && !_isSending ? _send : null,
                  icon: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                  tooltip: 'Send message'),
            ]);
          })
        ]),
      ),
    );
  }
}
