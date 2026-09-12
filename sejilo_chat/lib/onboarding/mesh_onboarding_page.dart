import 'package:flutter/material.dart';
import '../design_system/sejilo_theme.dart';

class MeshOnboardingPage extends StatefulWidget {
  const MeshOnboardingPage({super.key, this.onComplete});

  final VoidCallback? onComplete;

  @override
  State<MeshOnboardingPage> createState() => _MeshOnboardingPageState();
}

class _MeshOnboardingPageState extends State<MeshOnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardingStep> _steps = const [
    _OnboardingStep(
      icon: Icons.wifi_rounded,
      title: 'Internet',
      description: 'Normal online communication.\n\nMessages are delivered instantly through the internet when available.',
      color: SejiloColors.primary,
    ),
    _OnboardingStep(
      icon: Icons.wifi_off_rounded,
      title: 'No Internet',
      description: 'Sejilo searches for compatible nearby routes.\n\nWhen internet isn\'t available, Sejilo looks for nearby devices to help deliver your messages.',
      color: SejiloColors.secondary,
    ),
    _OnboardingStep(
      icon: Icons.bluetooth_rounded,
      title: 'Mesh',
      description: 'Compatible devices may relay encrypted messages.\n\nYour messages stay private while traveling through the mesh network.',
      color: SejiloColors.accent,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      widget.onComplete?.call();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Meet Sejilo Mesh',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemCount: _steps.length,
              itemBuilder: (context, index) {
                final step = _steps[index];
                return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: step.color.withValues(alpha: .15),
                          border: Border.all(color: step.color.withValues(alpha: .3), width: 2),
                        ),
                        child: Icon(step.icon, size: 56, color: step.color),
                      ),
                      const SizedBox(height: 48),
                      Text(
                        step.title,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        step.description,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _steps.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentPage == index ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index
                            ? SejiloColors.primary
                            : theme.dividerColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      _currentPage < _steps.length - 1 ? 'Next' : 'Enable Mesh',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                if (_currentPage < _steps.length - 1)
                  TextButton(
                    onPressed: () => widget.onComplete?.call(),
                    child: const Text('Skip'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingStep {
  const _OnboardingStep({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;
}
