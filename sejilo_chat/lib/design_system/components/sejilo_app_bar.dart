import 'package:flutter/material.dart';
import '../sejilo_theme.dart';

class SejiloAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SejiloAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.showBrandLogo = false,
    this.leading,
    this.actions,
    this.bottom,
    this.centerTitle = false,
  });

  final String? title;
  final Widget? titleWidget;
  final bool showBrandLogo;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0.0));

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget? renderedTitle;
    if (showBrandLogo) {
      renderedTitle = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => SejiloColors.sejiloGradient.createShader(bounds),
            child: const Text(
              'SejiloChat',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
                color: Colors.white,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(left: 4, top: 4),
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: SejiloColors.primary,
              shape: BoxShape.circle,
            ),
          ),
        ],
      );
    } else if (titleWidget != null) {
      renderedTitle = titleWidget;
    } else if (title != null) {
      renderedTitle = Text(
        title!,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: isDark ? Colors.white : Colors.black,
        ),
      );
    }

    return AppBar(
      title: renderedTitle,
      centerTitle: centerTitle,
      leading: leading,
      actions: actions != null
          ? [
              ...actions!,
              const SizedBox(width: 8),
            ]
          : null,
      bottom: bottom,
      backgroundColor: isDark ? SejiloColors.darkBg : SejiloColors.lightBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    );
  }
}
