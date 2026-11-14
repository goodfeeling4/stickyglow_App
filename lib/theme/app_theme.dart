import 'package:flutter/material.dart';

/// Represents a dual-mode pastel color pair used for sticky notes.
class StickyColor {
  /// Creates a [StickyColor] instance.
  const StickyColor({
    required this.name,
    required this.light,
    required this.dark,
  });

  /// Human-readable name of the color palette (e.g. 'Amber', 'Mint').
  final String name;

  /// Background color for light theme.
  final Color light;

  /// Background color for dark theme.
  final Color dark;
}

/// Application theme definitions and sticky note color palette.
abstract final class AppTheme {
  /// The warm amber seed color used for Material 3 ColorScheme generation.
  static const Color seedColor = Color(0xFFFFB300);

  /// The curated list of 6 pastel colors for sticky notes.
  static const List<StickyColor> stickyColors = <StickyColor>[
    StickyColor(
      name: 'Amber',
      light: Color(0xFFFFF8E1),
      dark: Color(0xFF4E3E00),
    ),
    StickyColor(
      name: 'Mint',
      light: Color(0xFFE0F2F1),
      dark: Color(0xFF003D36),
    ),
    StickyColor(
      name: 'Sky',
      light: Color(0xFFE3F2FD),
      dark: Color(0xFF002F5E),
    ),
    StickyColor(
      name: 'Lavender',
      light: Color(0xFFF3E5F5),
      dark: Color(0xFF3E0050),
    ),
    StickyColor(
      name: 'Rose',
      light: Color(0xFFFCE4EC),
      dark: Color(0xFF5E0020),
    ),
    StickyColor(
      name: 'Slate',
      light: Color(0xFFECEFF1),
      dark: Color(0xFF263238),
    ),
  ];

  /// Resolves the sticky note card color for a given [colorIndex] and [brightness].
  static Color cardColor(int colorIndex, Brightness brightness) {
    if (stickyColors.isEmpty) {
      return brightness == Brightness.dark
          ? const Color(0xFF1E1E1E)
          : Colors.white;
    }
    final safeIndex = (colorIndex >= 0 && colorIndex < stickyColors.length)
        ? colorIndex
        : (colorIndex % stickyColors.length).abs();
    final stickyColor = stickyColors[safeIndex];
    return brightness == Brightness.dark ? stickyColor.dark : stickyColor.light;
  }

  /// Builds the Material 3 light [ThemeData].
  static ThemeData lightTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      cardTheme: CardTheme(
        elevation: 1.5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(
          color: colorScheme.onSurface,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Builds the Material 3 dark [ThemeData].
  static ThemeData darkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      cardTheme: CardTheme(
        elevation: 1.5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(
          color: colorScheme.onSurface,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
