import 'package:flutter/material.dart';
import '../sejilo_theme.dart';

enum SejiloButtonVariant { primary, secondary, text }

class SejiloButton extends StatelessWidget {
  const SejiloButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = SejiloButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.fullWidth = true,
    this.height = 48,
    this.borderRadius = SejiloRadius.md,
  });

  final String label;
  final VoidCallback? onPressed;
  final SejiloButtonVariant variant;
  final Widget? icon;
  final bool isLoading;
  final bool fullWidth;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEnabled = onPressed != null && !isLoading;

    Widget childContent;
    if (isLoading) {
      childContent = SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          valueColor: AlwaysStoppedAnimation<Color>(
            variant == SejiloButtonVariant.secondary
                ? (isDark ? Colors.white : Colors.black)
                : Colors.white,
          ),
        ),
      );
    } else {
      childContent = Row(
        mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            icon!,
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: variant == SejiloButtonVariant.secondary
                  ? (isDark ? Colors.white : Colors.black87)
                  : variant == SejiloButtonVariant.text
                      ? SejiloColors.primary
                      : Colors.white,
            ),
          ),
        ],
      );
    }

    if (variant == SejiloButtonVariant.primary) {
      return Container(
        width: fullWidth ? double.infinity : null,
        height: height,
        decoration: BoxDecoration(
          gradient: isEnabled ? SejiloColors.sejiloGradient : null,
          color: isEnabled ? null : (isDark ? Colors.white12 : Colors.black12),
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: SejiloColors.primary.withAlpha(80),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(borderRadius),
            onTap: isEnabled ? onPressed : null,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: childContent,
              ),
            ),
          ),
        ),
      );
    }

    if (variant == SejiloButtonVariant.secondary) {
      return Container(
        width: fullWidth ? double.infinity : null,
        height: height,
        decoration: BoxDecoration(
          color: isDark ? SejiloColors.darkSurface : SejiloColors.lightSurface,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: isDark ? SejiloColors.darkOutline : SejiloColors.lightOutline,
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(borderRadius),
            onTap: isEnabled ? onPressed : null,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: childContent,
              ),
            ),
          ),
        ),
      );
    }

    // Text button
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: height,
      child: TextButton(
        onPressed: isEnabled ? onPressed : null,
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        child: childContent,
      ),
    );
  }
}
