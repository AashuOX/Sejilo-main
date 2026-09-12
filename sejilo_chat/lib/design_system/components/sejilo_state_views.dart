import 'package:flutter/material.dart';
import '../sejilo_theme.dart';
import 'sejilo_button.dart';

/// Standard Animated Shimmer Box for skeleton loaders
class SejiloSkeletonBox extends StatefulWidget {
  const SejiloSkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = SejiloRadius.sm,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  State<SejiloSkeletonBox> createState() => _SejiloSkeletonBoxState();
}

class _SejiloSkeletonBoxState extends State<SejiloSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF1E1E26) : const Color(0xFFE5E7EB);
    final highlight = isDark ? const Color(0xFF2C2C38) : const Color(0xFFF3F4F6);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(base, highlight, _controller.value),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}

/// Shimmer Skeleton for Feed Posts
class SejiloFeedSkeleton extends StatelessWidget {
  const SejiloFeedSkeleton({super.key, this.itemCount = 3});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 24),
      itemBuilder: (context, index) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const SejiloSkeletonBox(width: 38, height: 38, borderRadius: 19),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SejiloSkeletonBox(width: 110, height: 13, borderRadius: 4),
                      SizedBox(height: 6),
                      SejiloSkeletonBox(width: 70, height: 10, borderRadius: 4),
                    ],
                  ),
                  const Spacer(),
                  const SejiloSkeletonBox(width: 20, height: 20, borderRadius: 10),
                ],
              ),
            ),
            // Image Content
            const AspectRatio(
              aspectRatio: 1,
              child: SejiloSkeletonBox(width: double.infinity, height: double.infinity, borderRadius: 0),
            ),
            // Action Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: const [
                  SejiloSkeletonBox(width: 24, height: 24, borderRadius: 6),
                  SizedBox(width: 16),
                  SejiloSkeletonBox(width: 24, height: 24, borderRadius: 6),
                  SizedBox(width: 16),
                  SejiloSkeletonBox(width: 24, height: 24, borderRadius: 6),
                  Spacer(),
                  SejiloSkeletonBox(width: 24, height: 24, borderRadius: 6),
                ],
              ),
            ),
            // Likes & Caption
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SejiloSkeletonBox(width: 100, height: 12, borderRadius: 4),
                  SizedBox(height: 8),
                  SejiloSkeletonBox(width: 240, height: 12, borderRadius: 4),
                  SizedBox(height: 6),
                  SejiloSkeletonBox(width: 160, height: 10, borderRadius: 4),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Shimmer Skeleton for Stories Row
class SejiloStoriesSkeleton extends StatelessWidget {
  const SejiloStoriesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 98,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              SejiloSkeletonBox(width: 62, height: 62, borderRadius: 31),
              SizedBox(height: 6),
              SejiloSkeletonBox(width: 50, height: 10, borderRadius: 4),
            ],
          );
        },
      ),
    );
  }
}

/// Shimmer Skeleton for User Profile Header & Grid
class SejiloProfileSkeleton extends StatelessWidget {
  const SejiloProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SejiloSkeletonBox(width: 80, height: 80, borderRadius: 40),
                    const Spacer(),
                    Column(
                      children: const [
                        SejiloSkeletonBox(width: 36, height: 16, borderRadius: 4),
                        SizedBox(height: 6),
                        SejiloSkeletonBox(width: 44, height: 10, borderRadius: 4),
                      ],
                    ),
                    const SizedBox(width: 24),
                    Column(
                      children: const [
                        SejiloSkeletonBox(width: 36, height: 16, borderRadius: 4),
                        SizedBox(height: 6),
                        SejiloSkeletonBox(width: 54, height: 10, borderRadius: 4),
                      ],
                    ),
                    const SizedBox(width: 24),
                    Column(
                      children: const [
                        SejiloSkeletonBox(width: 36, height: 16, borderRadius: 4),
                        SizedBox(height: 6),
                        SejiloSkeletonBox(width: 54, height: 10, borderRadius: 4),
                      ],
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
                const SizedBox(height: 16),
                const SejiloSkeletonBox(width: 140, height: 14, borderRadius: 4),
                const SizedBox(height: 8),
                const SejiloSkeletonBox(width: 220, height: 12, borderRadius: 4),
                const SizedBox(height: 16),
                const SejiloSkeletonBox(width: double.infinity, height: 36, borderRadius: 8),
              ],
            ),
          ),
          const Divider(height: 1),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 9,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            itemBuilder: (_, __) => const SejiloSkeletonBox(width: double.infinity, height: double.infinity, borderRadius: 0),
          ),
        ],
      ),
    );
  }
}

/// Shimmer Skeleton for Explore Grid
class SejiloExploreSkeleton extends StatelessWidget {
  const SejiloExploreSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      itemCount: 15,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemBuilder: (_, __) => const SejiloSkeletonBox(
        width: double.infinity,
        height: double.infinity,
        borderRadius: 0,
      ),
    );
  }
}

/// Shimmer Skeleton for Direct Messages Conversations
class SejiloChatSkeleton extends StatelessWidget {
  const SejiloChatSkeleton({super.key, this.itemCount = 6});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              const SejiloSkeletonBox(width: 52, height: 52, borderRadius: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SejiloSkeletonBox(width: 120, height: 14, borderRadius: 4),
                    SizedBox(height: 6),
                    SejiloSkeletonBox(width: 180, height: 11, borderRadius: 4),
                  ],
                ),
              ),
              const SejiloSkeletonBox(width: 32, height: 10, borderRadius: 4),
            ],
          ),
        );
      },
    );
  }
}

/// Polished Loading View with Branded Spinner
class SejiloLoadingView extends StatelessWidget {
  const SejiloLoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SejiloColors.primary.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                valueColor: AlwaysStoppedAnimation<Color>(SejiloColors.primary),
              ),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 14),
            Text(
              message!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Polished Error State with Context & Action
class SejiloErrorView extends StatelessWidget {
  const SejiloErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.cloud_off_rounded,
    this.title = 'Unable to Load Content',
  });

  final String message;
  final String title;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SejiloColors.danger.withAlpha(24),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 42, color: SejiloColors.danger),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: 130,
                child: SejiloButton(
                  label: 'Try Again',
                  onPressed: onRetry,
                  height: 38,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Polished Empty State with Visual Illustration
class SejiloEmptyView extends StatelessWidget {
  const SejiloEmptyView({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.auto_awesome_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String description;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    SejiloColors.secondary.withAlpha(30),
                    SejiloColors.primary.withAlpha(30),
                    SejiloColors.accent.withAlpha(30),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(icon, size: 44, color: SejiloColors.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              SizedBox(
                width: 170,
                child: SejiloButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  height: 40,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
