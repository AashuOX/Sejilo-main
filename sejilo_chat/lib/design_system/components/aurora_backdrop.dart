import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../sejilo_theme.dart';

/// The restrained dark Aurora canvas used by auth and social surfaces.
/// It keeps the mesh identity visible without competing with content.
class AuroraBackdrop extends StatelessWidget {
  const AuroraBackdrop(
      {super.key, required this.child, this.showParticles = true});

  final Widget child;
  final bool showParticles;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).brightness != Brightness.dark) return child;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF003C46), SejiloColors.darkBg, Color(0xFF1B123B)],
          stops: [0, .48, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
              child: IgnorePointer(
                  child: CustomPaint(painter: _AuroraGlowPainter()))),
          if (showParticles)
            Positioned.fill(
                child: IgnorePointer(
                    child: CustomPaint(painter: _MeshParticlePainter()))),
          child,
        ],
      ),
    );
  }
}

class _AuroraGlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);
    paint.color = SejiloColors.darkCyan.withValues(alpha: .12);
    canvas.drawCircle(
        Offset(size.width * .07, size.height * .03), size.width * .32, paint);
    paint.color = SejiloColors.darkViolet.withValues(alpha: .13);
    canvas.drawCircle(
        Offset(size.width * .93, size.height * .18), size.width * .30, paint);
    paint.color = SejiloColors.darkMagenta.withValues(alpha: .07);
    canvas.drawCircle(
        Offset(size.width * .62, size.height * 1.08), size.width * .30, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MeshParticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(58);
    final paint = Paint()..color = SejiloColors.darkCyan.withValues(alpha: .56);
    for (var index = 0; index < 28; index++) {
      final point = Offset(
          random.nextDouble() * size.width, random.nextDouble() * size.height);
      canvas.drawCircle(point, index % 5 == 0 ? 2 : 1.1, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
