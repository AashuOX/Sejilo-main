import 'package:flutter/material.dart';
import '../sejilo_theme.dart';

class SejiloBottomNav extends StatelessWidget {
  const SejiloBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.unreadMessagesCount = 0,
    this.hasNotifications = false,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int unreadMessagesCount;
  final bool hasNotifications;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? SejiloColors.darkBg : SejiloColors.lightBg;
    final outline =
        isDark ? SejiloColors.darkOutline : SejiloColors.lightOutline;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: outline, width: 0.6)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_filled, Icons.home_outlined),
              _buildNavItem(1, Icons.explore, Icons.explore_outlined),
              _buildCreateItem(2),
              _buildMessagesItem(3),
              _buildNavItem(4, Icons.person, Icons.person_outline),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
      int index, IconData selectedIcon, IconData unselectedIcon) {
    final isSelected = currentIndex == index;
    const labels = ['Home', 'Explore', 'Create', 'Messages', 'Profile'];
    return InkWell(
      onTap: () => onTap(index),
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 58,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isSelected ? selectedIcon : unselectedIcon,
                color: isSelected ? SejiloColors.primary : Colors.grey,
                size: 23),
            const SizedBox(height: 3),
            Text(labels[index],
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? SejiloColors.primary : Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateItem(int index) {
    return InkWell(
      onTap: () => onTap(index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          gradient: SejiloGradients.aurora,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: SejiloColors.darkViolet.withValues(alpha: .35),
                blurRadius: 16)
          ],
        ),
        child: Icon(
          Icons.add,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildMessagesItem(int index) {
    final isSelected = currentIndex == index;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(
            isSelected ? Icons.chat_bubble : Icons.chat_bubble_outline_rounded,
            color: isSelected ? SejiloColors.primary : Colors.grey,
            size: 24,
          ),
          onPressed: () => onTap(index),
        ),
        if (unreadMessagesCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: const BoxDecoration(
                color: SejiloColors.primary,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Center(
                child: Text(
                  unreadMessagesCount > 99
                      ? '99+'
                      : unreadMessagesCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
