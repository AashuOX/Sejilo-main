import 'package:flutter/material.dart';
import '../sejilo_theme.dart';

class SejiloCard extends StatelessWidget {
  const SejiloCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.borderRadius = SejiloRadius.md,
    this.hasGradientBorder = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double borderRadius;
  final bool hasGradientBorder;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? SejiloColors.darkCard : SejiloColors.lightCard;
    final outlineColor = isDark ? SejiloColors.darkOutline : SejiloColors.lightOutline;

    Widget cardBody = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: hasGradientBorder ? null : Border.all(color: outlineColor, width: 0.8),
      ),
      child: child,
    );

    if (hasGradientBorder) {
      cardBody = Container(
        padding: const EdgeInsets.all(1.2),
        decoration: BoxDecoration(
          gradient: SejiloColors.sejiloGradient,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(borderRadius - 1),
          ),
          child: child,
        ),
      );
    }

    if (onTap != null) {
      cardBody = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: onTap,
          child: cardBody,
        ),
      );
    }

    if (margin != null) {
      return Padding(padding: margin!, child: cardBody);
    }

    return cardBody;
  }
}
