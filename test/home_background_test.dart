import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_notes_ssh/models/home_background.dart';

void main() {
  group('HomeBackground Model Tests', () {
    test('defaultTheme has correct type and defaults', () {
      const bg = HomeBackground.defaultTheme();
      expect(bg.type, HomeBackgroundType.defaultTheme);
      expect(bg.colorValue, isNull);
      expect(bg.gradientId, isNull);
      expect(bg.imagePath, isNull);
      expect(bg.overlayOpacity, 0.0);
    });

    test('color background serializes and deserializes', () {
      const bg = HomeBackground.color(0xFFFFF8E1);
      expect(bg.type, HomeBackgroundType.color);
      expect(bg.colorValue, 0xFFFFF8E1);

      final json = bg.toJson();
      final restored = HomeBackground.fromJson(json);

      expect(restored.type, HomeBackgroundType.color);
      expect(restored.colorValue, 0xFFFFF8E1);
      expect(restored, equals(bg));
    });

    test('gradient background serializes and resolves activeGradient', () {
      const bg = HomeBackground.gradient('sunset_glow');
      expect(bg.type, HomeBackgroundType.gradient);
      expect(bg.gradientId, 'sunset_glow');
      expect(bg.activeGradient?.name, 'Sunset Glow');

      final json = bg.toJson();
      final restored = HomeBackground.fromJson(json);

      expect(restored.gradientId, 'sunset_glow');
      expect(restored.activeGradient?.name, 'Sunset Glow');
      expect(restored, equals(bg));
    });

    test('image background with custom overlayOpacity roundtrips', () {
      const bg = HomeBackground.image(
        '/data/user/0/app/files/bg.jpg',
        overlayOpacity: 0.35,
      );
      expect(bg.type, HomeBackgroundType.image);
      expect(bg.imagePath, '/data/user/0/app/files/bg.jpg');
      expect(bg.overlayOpacity, 0.35);

      final json = bg.toJson();
      final restored = HomeBackground.fromJson(json);

      expect(restored.imagePath, '/data/user/0/app/files/bg.jpg');
      expect(restored.overlayOpacity, 0.35);
      expect(restored, equals(bg));
    });

    test('copyWith updates specified fields', () {
      const bg = HomeBackground.defaultTheme();
      final updated = bg.copyWith(
        type: HomeBackgroundType.color,
        colorValue: 0xFF121212,
      );

      expect(updated.type, HomeBackgroundType.color);
      expect(updated.colorValue, 0xFF121212);
    });

    test('presetGradients has at least 5 curated gradients', () {
      expect(HomeBackground.presetGradients.length, greaterThanOrEqualTo(5));
      for (final preset in HomeBackground.presetGradients) {
        expect(preset.colors.length, greaterThanOrEqualTo(2));
        expect(preset.name.isNotEmpty, isTrue);
      }
    });

    test('presetColors has curated colors', () {
      expect(HomeBackground.presetColors.length, greaterThanOrEqualTo(6));
    });
  });
}
