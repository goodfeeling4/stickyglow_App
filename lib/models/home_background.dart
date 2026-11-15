import 'dart:convert';
import 'package:flutter/material.dart';

/// The type of background displayed on the home screen.
enum HomeBackgroundType {
  /// System default theme background.
  defaultTheme,

  /// Solid color background.
  color,

  /// Curated gradient preset.
  gradient,

  /// Custom image from device gallery.
  image,
}

/// Represents a curated gradient preset.
class HomeGradientPreset {
  /// Creates a [HomeGradientPreset].
  const HomeGradientPreset({
    required this.id,
    required this.name,
    required this.colors,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });

  /// Unique identifier of the preset.
  final String id;

  /// User-facing display name.
  final String name;

  /// Gradient color stops.
  final List<Color> colors;

  /// Alignment where gradient starts.
  final Alignment begin;

  /// Alignment where gradient ends.
  final Alignment end;
}

/// Configuration model for the home screen background.
class HomeBackground {
  /// Creates a [HomeBackground] instance.
  const HomeBackground({
    this.type = HomeBackgroundType.defaultTheme,
    this.colorValue,
    this.gradientId,
    this.imagePath,
    this.overlayOpacity = 0.15,
  });

  /// Default system background.
  const HomeBackground.defaultTheme()
      : type = HomeBackgroundType.defaultTheme,
        colorValue = null,
        gradientId = null,
        imagePath = null,
        overlayOpacity = 0.0;

  /// Solid color background.
  const HomeBackground.color(int value)
      : type = HomeBackgroundType.color,
        colorValue = value,
        gradientId = null,
        imagePath = null,
        overlayOpacity = 0.0;

  /// Gradient preset background.
  const HomeBackground.gradient(String id)
      : type = HomeBackgroundType.gradient,
        colorValue = null,
        gradientId = id,
        imagePath = null,
        overlayOpacity = 0.0;

  /// Custom gallery image background with optional [overlayOpacity].
  const HomeBackground.image(String path, {this.overlayOpacity = 0.15})
      : type = HomeBackgroundType.image,
        colorValue = null,
        gradientId = null,
        imagePath = path;

  /// The category of background.
  final HomeBackgroundType type;

  /// 32-bit ARGB color value when [type] is [HomeBackgroundType.color].
  final int? colorValue;

  /// Preset identifier when [type] is [HomeBackgroundType.gradient].
  final String? gradientId;

  /// Local filesystem path to the image when [type] is [HomeBackgroundType.image].
  final String? imagePath;

  /// Dimming overlay opacity (0.0 - 0.6) for contrast when displaying images.
  final double overlayOpacity;

  /// Curated gradient presets available for the home screen.
  static const List<HomeGradientPreset> presetGradients = <HomeGradientPreset>[
    HomeGradientPreset(
      id: 'sunset_glow',
      name: 'Sunset Glow',
      colors: <Color>[Color(0xFFFFE0B2), Color(0xFFFFCCBC), Color(0xFFF8BBD0)],
    ),
    HomeGradientPreset(
      id: 'aurora_mint',
      name: 'Aurora Mint',
      colors: <Color>[Color(0xFFE0F2F1), Color(0xFFC8E6C9), Color(0xFFB2DFDB)],
    ),
    HomeGradientPreset(
      id: 'oceanic_sky',
      name: 'Oceanic Sky',
      colors: <Color>[Color(0xFFE1F5FE), Color(0xFFBBDEFB), Color(0xFFC5CAE9)],
    ),
    HomeGradientPreset(
      id: 'lavender_dusk',
      name: 'Lavender Dusk',
      colors: <Color>[Color(0xFFEDE7F6), Color(0xFFE1BEE7), Color(0xFFF8BBD0)],
    ),
    HomeGradientPreset(
      id: 'cherry_blossom',
      name: 'Cherry Blossom',
      colors: <Color>[Color(0xFFFCE4EC), Color(0xFFFFCDD2), Color(0xFFFFE0B2)],
    ),
    HomeGradientPreset(
      id: 'midnight_slate',
      name: 'Midnight Slate',
      colors: <Color>[Color(0xFF1E222A), Color(0xFF16191F), Color(0xFF0F1115)],
    ),
    HomeGradientPreset(
      id: 'cosmic_night',
      name: 'Cosmic Night',
      colors: <Color>[Color(0xFF1F1A2E), Color(0xFF161320), Color(0xFF0D0B13)],
    ),
  ];

  /// Curated solid colors available for the home screen.
  static const List<({String name, int colorValue})> presetColors = [
    (name: 'Warm Amber', colorValue: 0xFFFFF8E1),
    (name: 'Fresh Mint', colorValue: 0xFFE8F5E9),
    (name: 'Soft Sky', colorValue: 0xFFE3F2FD),
    (name: 'Pale Lavender', colorValue: 0xFFF3E5F5),
    (name: 'Blush Rose', colorValue: 0xFFFCE4EC),
    (name: 'Warm Parchment', colorValue: 0xFFF5EFE6),
    (name: 'Dark Slate', colorValue: 0xFF1E222A),
    (name: 'AMOLED Black', colorValue: 0xFF121212),
  ];

  /// Returns the [HomeGradientPreset] matching [gradientId], or the first preset if not found.
  HomeGradientPreset? get activeGradient {
    if (gradientId == null) return null;
    return presetGradients.firstWhere(
      (g) => g.id == gradientId,
      orElse: () => presetGradients.first,
    );
  }

  /// Serializes to a Map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': type.name,
      'colorValue': colorValue,
      'gradientId': gradientId,
      'imagePath': imagePath,
      'overlayOpacity': overlayOpacity,
    };
  }

  /// Serializes to JSON string.
  String toJson() => jsonEncode(toMap());

  /// Deserializes from a Map.
  factory HomeBackground.fromMap(Map<String, dynamic> map) {
    final typeStr = map['type'] as String?;
    final type = HomeBackgroundType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => HomeBackgroundType.defaultTheme,
    );

    return HomeBackground(
      type: type,
      colorValue: (map['colorValue'] as num?)?.toInt(),
      gradientId: map['gradientId'] as String?,
      imagePath: map['imagePath'] as String?,
      overlayOpacity: (map['overlayOpacity'] as num?)?.toDouble() ?? 0.15,
    );
  }

  /// Deserializes from JSON string.
  factory HomeBackground.fromJson(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) {
        return HomeBackground.fromMap(decoded);
      }
    } catch (_) {}
    return const HomeBackground.defaultTheme();
  }

  /// Returns a copy with modified fields.
  HomeBackground copyWith({
    HomeBackgroundType? type,
    int? colorValue,
    String? gradientId,
    String? imagePath,
    double? overlayOpacity,
  }) {
    return HomeBackground(
      type: type ?? this.type,
      colorValue: colorValue ?? this.colorValue,
      gradientId: gradientId ?? this.gradientId,
      imagePath: imagePath ?? this.imagePath,
      overlayOpacity: overlayOpacity ?? this.overlayOpacity,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! HomeBackground || runtimeType != other.runtimeType) return false;
    return type == other.type &&
        colorValue == other.colorValue &&
        gradientId == other.gradientId &&
        imagePath == other.imagePath &&
        (overlayOpacity - other.overlayOpacity).abs() < 0.001;
  }

  @override
  int get hashCode => Object.hash(
        type,
        colorValue,
        gradientId,
        imagePath,
        overlayOpacity,
      );
}
