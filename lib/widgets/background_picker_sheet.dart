import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sticky_notes_ssh/models/home_background.dart';

/// Modal bottom sheet allowing users to customize the home screen background
/// with preset colors, beautiful gradients, or custom images from the gallery.
class BackgroundPickerSheet extends StatefulWidget {
  /// Creates a [BackgroundPickerSheet].
  const BackgroundPickerSheet({
    super.key,
    required this.currentBackground,
    required this.onBackgroundChanged,
    required this.onPickGalleryImage,
  });

  /// The currently active background configuration.
  final HomeBackground currentBackground;

  /// Callback when a preset color, gradient, or reset is selected.
  final ValueChanged<HomeBackground> onBackgroundChanged;

  /// Callback to launch image picker and store image locally.
  final Future<void> Function() onPickGalleryImage;

  /// Helper to show this bottom sheet.
  static Future<void> show({
    required BuildContext context,
    required HomeBackground currentBackground,
    required ValueChanged<HomeBackground> onBackgroundChanged,
    required Future<void> Function() onPickGalleryImage,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => BackgroundPickerSheet(
        currentBackground: currentBackground,
        onBackgroundChanged: onBackgroundChanged,
        onPickGalleryImage: onPickGalleryImage,
      ),
    );
  }

  @override
  State<BackgroundPickerSheet> createState() => _BackgroundPickerSheetState();
}

class _BackgroundPickerSheetState extends State<BackgroundPickerSheet> {
  late HomeBackground _background;

  @override
  void initState() {
    super.initState();
    _background = widget.currentBackground;
  }

  void _selectBackground(HomeBackground newBg) {
    setState(() {
      _background = newBg;
    });
    widget.onBackgroundChanged(newBg);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    'Home Background',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _selectBackground(const HomeBackground.defaultTheme());
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Section: Gallery Photo
              Text(
                'CUSTOM WALLPAPER',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),

              if (_background.type == HomeBackgroundType.image &&
                  _background.imagePath != null &&
                  File(_background.imagePath!).existsSync()) ...<Widget>[
                // Active image preview with overlay slider
                Container(
                  height: 110,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    image: DecorationImage(
                      image: FileImage(File(_background.imagePath!)),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.black.withValues(
                        alpha: _background.overlayOpacity,
                      ),
                    ),
                    padding: const EdgeInsets.all(12),
                    alignment: Alignment.bottomRight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.black.withValues(alpha: 0.6),
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                          ),
                          onPressed: () async {
                            await widget.onPickGalleryImage();
                          },
                          icon: const Icon(Icons.photo_library_rounded, size: 16),
                          label: const Text('Change Photo'),
                        ),
                        IconButton(
                          tooltip: 'Remove photo',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withValues(alpha: 0.6),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            _selectBackground(const HomeBackground.defaultTheme());
                          },
                          icon: const Icon(Icons.delete_outline_rounded, size: 20),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    const Icon(Icons.brightness_medium_rounded, size: 18),
                    const SizedBox(width: 8),
                    const Text('Dimming:'),
                    Expanded(
                      child: Slider(
                        value: _background.overlayOpacity,
                        min: 0.0,
                        max: 0.6,
                        divisions: 12,
                        label: '${(_background.overlayOpacity * 100).round()}%',
                        onChanged: (val) {
                          _selectBackground(
                            _background.copyWith(overlayOpacity: val),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ] else ...<Widget>[
                // Button to choose photo
                Semantics(
                  button: true,
                  label: 'Choose photo from gallery',
                  child: InkWell(
                    onTap: () async {
                      await widget.onPickGalleryImage();
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: theme.colorScheme.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.photo_library_rounded,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Choose Photo from Gallery',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),

              // Section: Curated Gradients
              Text(
                'CURATED GRADIENTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: HomeBackground.presetGradients.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final preset = HomeBackground.presetGradients[index];
                    final isSelected =
                        _background.type == HomeBackgroundType.gradient &&
                            _background.gradientId == preset.id;

                    return Semantics(
                      button: true,
                      selected: isSelected,
                      label: '${preset.name} gradient',
                      child: InkWell(
                        onTap: () {
                          _selectBackground(HomeBackground.gradient(preset.id));
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 105,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: preset.colors,
                              begin: preset.begin,
                              end: preset.end,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : Colors.black.withValues(alpha: 0.12),
                              width: isSelected ? 2.5 : 1,
                            ),
                            boxShadow: isSelected
                                ? <BoxShadow>[
                                    BoxShadow(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.3),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          padding: const EdgeInsets.all(8),
                          alignment: Alignment.bottomLeft,
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  preset.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: preset.colors.first.computeLuminance() >
                                            0.5
                                        ? Colors.black87
                                        : Colors.white,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 16,
                                  color: preset.colors.first.computeLuminance() >
                                          0.5
                                      ? Colors.black87
                                      : Colors.white,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),

              // Section: Curated Colors
              Text(
                'PASTEL & SOLID COLORS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: HomeBackground.presetColors.map((colorInfo) {
                  final color = Color(colorInfo.colorValue);
                  final isSelected =
                      _background.type == HomeBackgroundType.color &&
                          _background.colorValue == colorInfo.colorValue;

                  return Semantics(
                    button: true,
                    selected: isSelected,
                    label: '${colorInfo.name} color',
                    child: Tooltip(
                      message: colorInfo.name,
                      child: InkWell(
                        onTap: () {
                          _selectBackground(
                            HomeBackground.color(colorInfo.colorValue),
                          );
                        },
                        borderRadius: BorderRadius.circular(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : Colors.black.withValues(alpha: 0.15),
                                width: isSelected ? 2.5 : 1,
                              ),
                              boxShadow: isSelected
                                  ? <BoxShadow>[
                                      BoxShadow(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.35),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: isSelected
                                ? Icon(
                                    Icons.check,
                                    size: 22,
                                    color: color.computeLuminance() > 0.5
                                        ? Colors.black87
                                        : Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
