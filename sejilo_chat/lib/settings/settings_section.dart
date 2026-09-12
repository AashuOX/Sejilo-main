import 'package:flutter/material.dart';
import '../design_system/sejilo_theme.dart';

/// A titled group of setting rows.
///
/// This widget used to be copy-pasted, identically, into every settings page.
/// It lives here so the card treatment is defined once.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
    super.key,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: SejiloColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: SejiloColors.primary,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: .6),
              width: .5,
            ),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// Formats a timestamp the way the settings screens want it: relative for the
/// last week, then an absolute date.
String settingsRelativeDate(DateTime when) {
  final delta = DateTime.now().difference(when);
  if (delta.inMinutes < 1) return 'just now';
  if (delta.inHours < 1) return '${delta.inMinutes}m ago';
  if (delta.inDays < 1) return '${delta.inHours}h ago';
  if (delta.inDays < 7) return '${delta.inDays}d ago';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = when.toLocal();
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}
