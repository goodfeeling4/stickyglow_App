import 'package:flutter/material.dart';
import 'package:sticky_notes_ssh/theme/app_theme.dart';

/// A horizontal selector bar with 6 pastel color circles for sticky notes.
class ColorPickerBar extends StatelessWidget {
  /// Creates a [ColorPickerBar].
  const ColorPickerBar({
    super.key,
    required this.selectedIndex,
    required this.onColorSelected,
  });

  /// The currently selected color index (0-5).
  final int selectedIndex;

  /// Callback triggered when a new color circle is tapped.
  final ValueChanged<int> onColorSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final stickyColors = AppTheme.stickyColors;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List<Widget>.generate(stickyColors.length, (int index) {
          final isSelected = selectedIndex == index;
          final stickyColor = stickyColors[index];
          final circleColor = isDark ? stickyColor.dark : stickyColor.light;
          final checkColor = isDark ? Colors.white : Colors.black87;

          return Semantics(
            button: true,
            selected: isSelected,
            label: '${stickyColor.name} note color',
            child: Tooltip(
              message: stickyColor.name,
              child: InkWell(
                onTap: () => onColorSelected(index),
                customBorder: const CircleBorder(),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: circleColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.25)
                                  : Colors.black.withValues(alpha: 0.15)),
                          width: isSelected ? 2.5 : 1.0,
                        ),
                        boxShadow: isSelected
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? Center(
                              child: Icon(
                                Icons.check,
                                size: 18,
                                color: checkColor,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
