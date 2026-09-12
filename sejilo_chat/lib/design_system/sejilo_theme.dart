import 'package:flutter/material.dart';

/// Aurora Mesh Design System
/// Premium dark-first theme with cyan, violet, and magenta accents
abstract final class SejiloColors {
  // ═══════════════════════════════════════════════════════════════════════
  // DARK THEME — Aurora Mesh (Primary)
  // ═══════════════════════════════════════════════════════════════════════

  static const darkBg = Color(0xFF070A12);              // Deep midnight
  static const darkBgSecondary = Color(0xFF0B1020);    // Slightly lighter
  static const darkSurface = Color(0xFF0D1220);        // Base surface
  static const darkSurfaceElevated = Color(0xFF121A2A); // Elevated surface
  static const darkSurfaceHighlight = Color(0xFF172238); // Highlight surface

  // Aurora Accent Colors (Dark)
  static const darkCyan = Color(0xFF22D3EE);           // Primary cyan
  static const darkViolet = Color(0xFF8B5CF6);         // Secondary violet
  static const darkMagenta = Color(0xFFEC4899);        // Accent magenta
  static const darkMeshBlue = Color(0xFF38BDF8);       // Mesh communication

  // Status & Utility (Dark)
  static const darkSuccess = Color(0xFF34D399);
  static const darkWarning = Color(0xFFFBBF24);
  static const darkError = Color(0xFFFB7185);

  // Text (Dark)
  static const darkText = Color(0xFFF8FAFC);           // Primary text
  static const darkTextSecondary = Color(0xFFCBD5E1); // Secondary text
  static const darkTextMuted = Color(0xFF94A3B8);     // Muted text
  static const darkTextDisabled = Color(0xFF475569);  // Disabled

  static const darkDivider = Color(0xFF1E293B);

  // ═══════════════════════════════════════════════════════════════════════
  // LIGHT THEME — Aurora Mesh (Secondary)
  // ═══════════════════════════════════════════════════════════════════════

  static const lightBg = Color(0xFFF7F9FC);            // Light background
  static const lightSurface = Color(0xFFFFFFFF);       // White surface
  static const lightSurfaceSecondary = Color(0xFFF1F5F9); // Secondary surface

  // Aurora Accent Colors (Light)
  static const lightCyan = Color(0xFF0891B2);          // Primary cyan
  static const lightViolet = Color(0xFF7C3AED);        // Secondary violet
  static const lightMagenta = Color(0xFFDB2777);       // Accent magenta

  // Status & Utility (Light)
  static const lightSuccess = Color(0xFF059669);
  static const lightError = Color(0xFFE11D48);

  // Text (Light)
  static const lightText = Color(0xFF0F172A);          // Primary text
  static const lightTextSecondary = Color(0xFF475569); // Secondary text
  static const lightTextMuted = Color(0xFF64748B);     // Muted text

  static const lightDivider = Color(0xFFE2E8F0);

  // ═══════════════════════════════════════════════════════════════════════
  // BACKWARD COMPATIBILITY ALIASES
  // ═══════════════════════════════════════════════════════════════════════

  // Old names → new Aurora names
  static const primary = darkCyan;              // Primary action color
  static const secondary = darkViolet;          // Secondary accent
  static const accent = darkMagenta;            // Accent color
  static const highlight = darkMeshBlue;        // Highlight color

  static const danger = darkError;              // Error/danger state
  static const darkMuted = darkTextMuted;       // Dark muted text
  static const lightMuted = lightTextMuted;     // Light muted text

  static const darkOutline = darkDivider;       // Dark divider
  static const lightOutline = lightDivider;     // Light divider

  static const statusOnline = darkSuccess;      // Online status (green)

  // Legacy gradient
  static const sejiloGradient = auroraGradient;

  // Instagram gradient aliases (for backward compatibility)
  static const storyGradient = auroraGradient;
  static const dmGradient = auroraGradient;
  static const instaGradient = auroraGradient;

  // Instagram color aliases
  static const instaBlue = darkCyan;
  static const instaHeartRed = darkError;
  static const instaPurple = darkViolet;
  static const instaPink = darkMagenta;
  static const instaOrange = darkMeshBlue;
  static const instaYellow = darkWarning;

  // Card aliases
  static const darkCard = darkSurface;
  static const lightCard = lightSurface;

  // Status aliases for mesh/connectivity
  static const statusMesh = darkMeshBlue;
  static const statusOffline = darkWarning;

  // ═══════════════════════════════════════════════════════════════════════
  // AURORA BRAND GRADIENT
  // ═══════════════════════════════════════════════════════════════════════

  static const auroraGradient = LinearGradient(
    colors: [
      Color(0xFF22D3EE),  // Cyan
      Color(0xFF8B5CF6),  // Violet
      Color(0xFFEC4899),  // Magenta
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Typography scales per spec
abstract final class SejiloTextStyles {
  // Display: 32–40 px / bold
  static const display = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.2,
  );

  // Large Heading: 28–32 px / bold
  static const largeHeading = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    height: 1.25,
  );

  // Heading: 22–26 px / semibold
  static const heading = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.3,
  );

  // Subheading: 18–20 px / semibold
  static const subheading = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    height: 1.35,
  );

  // Body: 15–17 px / regular
  static const body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.5,
  );

  // Body small: 13–14 px
  static const bodySmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    height: 1.4,
  );

  // Label: 13–14 px / semibold
  static const label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.3,
  );

  // Caption: 11–12 px
  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    height: 1.25,
  );
}

/// 8-point spacing system
abstract final class SejiloSpace {
  static const micro = 4.0;    // 4px
  static const xs = 8.0;       // 8px (small)
  static const sm = 12.0;      // 12px (compact)
  static const md = 16.0;      // 16px (normal)
  static const lg = 20.0;      // 20px (medium)
  static const xl = 24.0;      // 24px (large)
  static const xxl = 32.0;     // 32px (section)
  static const xxxl = 40.0;    // 40px (major section)
  static const hero = 48.0;    // 48px (hero)
  static const largeHero = 64.0; // 64px (large hero)
}

/// Border radius system
abstract final class SejiloRadius {
  static const small = 10.0;   // Small controls
  static const input = 14.0;   // Input fields
  static const card = 18.0;    // Cards
  static const largeCard = 22.0; // Large cards
  static const sheet = 24.0;   // Bottom sheets & modals
  static const pill = 999.0;   // Pills

  // Backward compatibility aliases
  static const sm = small;
  static const md = card;
  static const lg = largeCard;
  static const xl = sheet;
}

/// Reusable gradients
abstract final class SejiloGradients {
  static const aurora = SejiloColors.auroraGradient;
}

/// Theme builder for Aurora Mesh
abstract final class SejiloTheme {
  static ThemeData dark() => _buildDark();
  static ThemeData light() => _buildLight();

  static ThemeData _buildDark() {
    const bg = SejiloColors.darkBg;
    const surface = SejiloColors.darkSurface;
    const surfaceElevated = SejiloColors.darkSurfaceElevated;
    const primary = SejiloColors.darkCyan;
    const textColor = SejiloColors.darkText;
    const textSecondary = SejiloColors.darkTextSecondary;
    const divider = SejiloColors.darkDivider;

    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: primary,
      onPrimary: SejiloColors.darkBg,
      secondary: SejiloColors.darkViolet,
      onSecondary: Colors.white,
      tertiary: SejiloColors.darkMagenta,
      onTertiary: Colors.white,
      error: SejiloColors.darkError,
      onError: Colors.white,
      surface: bg,
      onSurface: textColor,
      surfaceContainerLow: SejiloColors.darkBgSecondary,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceElevated,
      surfaceContainerHighest: SejiloColors.darkSurfaceHighlight,
      outline: divider,
      outlineVariant: divider.withAlpha(128),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      visualDensity: VisualDensity.standard,
      fontFamily: 'Inter',
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: textColor,
        displayColor: textColor,
        fontFamily: 'Inter',
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textColor,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: SejiloTextStyles.heading.copyWith(color: textColor),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SejiloRadius.card),
          side: BorderSide(color: divider, width: 0.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SejiloSpace.md,
          vertical: SejiloSpace.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SejiloRadius.input),
          borderSide: BorderSide(color: divider, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SejiloRadius.input),
          borderSide: BorderSide(color: divider, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SejiloRadius.input),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SejiloRadius.input),
          borderSide: BorderSide(color: scheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SejiloRadius.input),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        hintStyle: TextStyle(
          color: SejiloColors.darkTextMuted,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: SejiloTextStyles.label.copyWith(color: textSecondary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        height: 56,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary, size: 24);
          }
          return const IconThemeData(
            color: SejiloColors.darkTextMuted,
            size: 24,
          );
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SejiloRadius.sheet),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: divider,
        thickness: 0.5,
        space: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceElevated,
        side: BorderSide(color: divider, width: 0.5),
        labelStyle: SejiloTextStyles.label.copyWith(color: textColor),
        padding: const EdgeInsets.symmetric(
          horizontal: SejiloSpace.sm,
          vertical: SejiloSpace.xs,
        ),
      ),
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(horizontal: SejiloSpace.md),
        minLeadingWidth: 0,
        textColor: textColor,
        subtitleTextStyle: SejiloTextStyles.bodySmall.copyWith(
          color: textSecondary,
        ),
      ),
      buttonTheme: ButtonThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SejiloRadius.card),
        ),
        textTheme: ButtonTextTheme.primary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: SejiloColors.darkBg,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: SejiloSpace.xl,
            vertical: SejiloSpace.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SejiloRadius.card),
          ),
          textStyle: SejiloTextStyles.label,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1.5),
          padding: const EdgeInsets.symmetric(
            horizontal: SejiloSpace.xl,
            vertical: SejiloSpace.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SejiloRadius.card),
          ),
          textStyle: SejiloTextStyles.label,
        ),
      ),
    );
  }

  static ThemeData _buildLight() {
    const bg = SejiloColors.lightBg;
    const surface = SejiloColors.lightSurface;
    const secondary = SejiloColors.lightSurfaceSecondary;
    const primary = SejiloColors.lightCyan;
    const textColor = SejiloColors.lightText;
    const textSecondary = SejiloColors.lightTextSecondary;
    const divider = SejiloColors.lightDivider;

    final scheme = ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      secondary: SejiloColors.lightViolet,
      onSecondary: Colors.white,
      tertiary: SejiloColors.lightMagenta,
      onTertiary: Colors.white,
      error: SejiloColors.lightError,
      onError: Colors.white,
      surface: bg,
      onSurface: textColor,
      surfaceContainerLow: secondary,
      surfaceContainer: surface,
      surfaceContainerHigh: secondary,
      surfaceContainerHighest: secondary,
      outline: divider,
      outlineVariant: divider.withAlpha(128),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      visualDensity: VisualDensity.standard,
      fontFamily: 'Inter',
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: textColor,
        displayColor: textColor,
        fontFamily: 'Inter',
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textColor,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: SejiloTextStyles.heading.copyWith(color: textColor),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SejiloRadius.card),
          side: BorderSide(color: divider, width: 0.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: secondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SejiloSpace.md,
          vertical: SejiloSpace.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SejiloRadius.input),
          borderSide: BorderSide(color: divider, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SejiloRadius.input),
          borderSide: BorderSide(color: divider, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SejiloRadius.input),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SejiloRadius.input),
          borderSide: BorderSide(color: scheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SejiloRadius.input),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        hintStyle: TextStyle(
          color: SejiloColors.lightTextMuted,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: SejiloTextStyles.label.copyWith(color: textSecondary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        height: 56,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary, size: 24);
          }
          return const IconThemeData(
            color: SejiloColors.lightTextMuted,
            size: 24,
          );
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SejiloRadius.sheet),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: divider,
        thickness: 0.5,
        space: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: secondary,
        side: BorderSide(color: divider, width: 0.5),
        labelStyle: SejiloTextStyles.label.copyWith(color: textColor),
        padding: const EdgeInsets.symmetric(
          horizontal: SejiloSpace.sm,
          vertical: SejiloSpace.xs,
        ),
      ),
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(horizontal: SejiloSpace.md),
        minLeadingWidth: 0,
        textColor: textColor,
        subtitleTextStyle: SejiloTextStyles.bodySmall.copyWith(
          color: textSecondary,
        ),
      ),
      buttonTheme: ButtonThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SejiloRadius.card),
        ),
        textTheme: ButtonTextTheme.primary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: SejiloSpace.xl,
            vertical: SejiloSpace.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SejiloRadius.card),
          ),
          textStyle: SejiloTextStyles.label,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1.5),
          padding: const EdgeInsets.symmetric(
            horizontal: SejiloSpace.xl,
            vertical: SejiloSpace.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SejiloRadius.card),
          ),
          textStyle: SejiloTextStyles.label,
        ),
      ),
    );
  }
}
