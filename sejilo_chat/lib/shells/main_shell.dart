import 'package:flutter/material.dart';
import '../auth/account_auth_controller.dart';
import '../core/app_preferences.dart';
import '../core/connectivity_notifier.dart';
import '../core/mesh_client.dart';
import '../core/responsive.dart';
import '../design_system/components/sejilo_avatar.dart';
import '../design_system/components/sejilo_bottom_nav.dart';
import '../design_system/components/sejilo_connectivity_chip.dart';
import '../design_system/components/aurora_backdrop.dart';
import '../design_system/sejilo_theme.dart';
import '../mesh/mesh_dashboard_page.dart';
import '../settings/settings_page.dart';
import 'create_shell.dart';
import 'explore_shell.dart';
import 'home_shell.dart';
import 'messages_shell.dart';
import 'profile_shell.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.auth,
    this.preferences,
    this.meshClient,
  });

  final AccountAuthController auth;
  final AppPreferences? preferences;
  final MeshClient? meshClient;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  /// Reachability for the status chip. Owned here because this is the first
  /// widget that stays mounted for the whole signed-in session.
  late final ConnectivityNotifier _connectivity;

  @override
  void initState() {
    super.initState();
    _connectivity = ConnectivityNotifier();
    _connectivity.initialize();

    final mesh = widget.meshClient;
    if (mesh != null) {
      mesh.addListener(_onMeshChanged);
      _connectivity.updateMeshPeerCount(mesh.nearbyPeers.length);
    }

    widget.auth.addListener(_syncMeshIdentity);
    _syncMeshIdentity();
  }

  @override
  void dispose() {
    widget.auth.removeListener(_syncMeshIdentity);
    widget.meshClient?.removeListener(_onMeshChanged);
    _connectivity.dispose();
    super.dispose();
  }

  void _onMeshChanged() {
    final mesh = widget.meshClient;
    if (mesh == null) return;
    _connectivity.updateMeshPeerCount(mesh.nearbyPeers.length);
  }

  /// Puts the account's handle on the mesh identity.
  ///
  /// `MeshClient.setUsername` was only ever called from a screen that is no
  /// longer reachable, so every device advertised the default 'Sejilo user'
  /// over BLE no matter who was signed in — peers could not tell each other
  /// apart. Nothing is sent anywhere new: this is the same local name the mesh
  /// service already broadcasts.
  void _syncMeshIdentity() {
    final mesh = widget.meshClient;
    final profile = widget.auth.profile;
    if (mesh == null || profile == null) return;
    final handle = profile.username.trim();
    if (handle.isEmpty || mesh.username == handle) return;
    mesh.setUsername(handle);
  }

  void _onNavTap(int index) {
    if (index == 2) {
      _showCreateSheet(context);
    } else {
      setState(() => _currentIndex = index);
    }
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: .4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Create',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CreateOption(
                    icon: Icons.photo_library_outlined,
                    label: 'Post',
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _currentIndex = 2);
                    },
                  ),
                  _CreateOption(
                    icon: Icons.movie_creation_outlined,
                    label: 'Reel',
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _currentIndex = 2);
                    },
                  ),
                  _CreateOption(
                    icon: Icons.article_outlined,
                    label: 'Story',
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _currentIndex = 2);
                    },
                  ),
                  _CreateOption(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Message',
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _currentIndex = 3);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final isTablet = Responsive.isTablet(context);

    final pages = [
      HomeShell(
        auth: widget.auth,
        // The tab index lives here, so the feed's chat icon asks rather than
        // telling the reader to go and find the Messages tab themselves.
        onOpenMessages: () => _onNavTap(3),
      ),
      ExploreShell(auth: widget.auth),
      CreateShell(auth: widget.auth),
      MessagesShell(auth: widget.auth),
      ProfileShell(
        auth: widget.auth,
        preferences: widget.preferences,
        meshClient: widget.meshClient,
      ),
    ];

    if (isDesktop || isTablet) {
      return Scaffold(
        body: Row(
          children: [
            _buildSidebar(isDesktop),
            const VerticalDivider(width: 1),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: CurvedAnimation(
                        parent: animation, curve: Curves.easeOut),
                    child: child,
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey<int>(_currentIndex),
                  child: pages[_currentIndex],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: AuroraBackdrop(
        showParticles: false,
        child: IndexedStack(index: _currentIndex, children: pages),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatusStrip(),
          SejiloBottomNav(
            currentIndex: _currentIndex,
            onTap: _onNavTap,
          ),
        ],
      ),
    );
  }

  /// The always-visible reachability strip above the bottom bar.
  ///
  /// Tapping it opens the mesh dashboard, which is where the peer list and the
  /// queue actually live.
  Widget _buildStatusStrip() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _connectivity,
      builder: (context, _) => Material(
        color: isDark ? SejiloColors.darkSurface : SejiloColors.lightSurface,
        child: SizedBox(
          height: 30,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SejiloConnectivityChip(
                status: _connectivity.status,
                meshPeerCount: _connectivity.meshPeerCount,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        MeshDashboardPage(meshClient: widget.meshClient),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(bool isDesktop) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = widget.auth.profile;

    return Container(
      width: isDesktop ? 230 : 76,
      color: isDark ? SejiloColors.darkBg : SejiloColors.lightBg,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      child: Column(
        crossAxisAlignment:
            isDesktop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          // Logo & Branding
          if (isDesktop) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: SejiloColors.sejiloGradient,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Center(
                      child: Icon(Icons.bolt_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ShaderMask(
                    shaderCallback: (bounds) =>
                        SejiloColors.sejiloGradient.createShader(bounds),
                    child: const Text(
                      'SejiloChat',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Tooltip(
              message: 'SejiloChat',
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: SejiloColors.sejiloGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child:
                      Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),

          // Reachability, in the same place on every screen size.
          AnimatedBuilder(
            animation: _connectivity,
            builder: (context, _) => Padding(
              padding: EdgeInsets.symmetric(horizontal: isDesktop ? 12 : 0),
              child: Align(
                alignment:
                    isDesktop ? Alignment.centerLeft : Alignment.center,
                child: SejiloConnectivityChip(
                  status: _connectivity.status,
                  meshPeerCount: _connectivity.meshPeerCount,
                  compact: !isDesktop,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          MeshDashboardPage(meshClient: widget.meshClient),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Core Navigation Items
          _buildSidebarItem(
              0, Icons.home_filled, Icons.home_outlined, 'Home', isDesktop),
          _buildSidebarItem(
              1, Icons.explore, Icons.explore_outlined, 'Explore', isDesktop),
          _buildSidebarItem(
              2, Icons.add_box, Icons.add_box_outlined, 'Create', isDesktop),
          _buildSidebarItem(3, Icons.chat_bubble,
              Icons.chat_bubble_outline_rounded, 'Messages', isDesktop),
          _buildSidebarItem(4, Icons.person, Icons.person_outline_rounded,
              'Profile', isDesktop),

          const Spacer(),
          const Divider(height: 24),

          // Mesh Network Dashboard Quick Access
          _buildUtilityItem(
            icon: Icons.hub_outlined,
            label: 'Mesh Network',
            tooltip: 'View Peer-to-Peer Mesh Topology',
            isDesktop: isDesktop,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  // The live client, so the dashboard plots the peers this app
                  // is actually connected to. Passing nothing made the page
                  // spin up a second MeshClient with its own BLE session and
                  // its own — usually empty — peer list.
                  builder: (_) => MeshDashboardPage(meshClient: widget.meshClient),
                ),
              );
            },
          ),

          // Privacy & Security Quick Access
          _buildUtilityItem(
            icon: Icons.security_outlined,
            label: 'Privacy Vault',
            tooltip: 'Security and Ephemeral Key Settings',
            isDesktop: isDesktop,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsPage(
                    auth: widget.auth,
                    // The live objects only. The old fallbacks built a fresh
                    // AppPreferences/MeshClient, so anything toggled in
                    // Settings was written to an instance nothing reads.
                    preferences: widget.preferences,
                    meshClient: widget.meshClient,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 8),

          // User Profile Quick Bar at bottom
          if (profile != null)
            Semantics(
              label: 'User profile: ${profile.displayName}',
              child: InkWell(
                onTap: () => setState(() => _currentIndex = 4),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisAlignment: isDesktop
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      SejiloAvatar(
                        name: profile.displayName,
                        imageBytes: profile.avatarBytes,
                        size: SejiloAvatarSize.xs,
                      ),
                      if (isDesktop) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.username,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                profile.displayName,
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      isDark ? Colors.white54 : Colors.black54,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(
    int index,
    IconData activeIcon,
    IconData inactiveIcon,
    String label,
    bool isDesktop,
  ) {
    final isSelected = _currentIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: Tooltip(
        message: isDesktop ? '' : label,
        child: InkWell(
          onTap: () => setState(() => _currentIndex = index),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 12 : 8, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark
                      ? SejiloColors.darkSurface
                      : const Color(0xFFEFEFEF))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(
                      color: isDark
                          ? SejiloColors.darkOutline
                          : SejiloColors.lightOutline,
                      width: 0.8,
                    )
                  : null,
            ),
            child: Row(
              mainAxisAlignment: isDesktop
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  isSelected ? activeIcon : inactiveIcon,
                  color: isSelected
                      ? SejiloColors.primary
                      : (isDark ? Colors.white70 : Colors.black87),
                  size: 23,
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 14),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected
                          ? SejiloColors.primary
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUtilityItem({
    required IconData icon,
    required String label,
    required String tooltip,
    required bool isDesktop,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding:
              EdgeInsets.symmetric(horizontal: isDesktop ? 12 : 8, vertical: 8),
          child: Row(
            mainAxisAlignment:
                isDesktop ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isDark ? Colors.white54 : Colors.black54,
                size: 20,
              ),
              if (isDesktop) ...[
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white70 : Colors.black87,
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

class _CreateOption extends StatelessWidget {
  const _CreateOption({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: SejiloColors.primary.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: SejiloColors.primary),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
