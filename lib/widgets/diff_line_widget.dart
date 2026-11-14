import 'package:flutter/material.dart';

/// Type of line representation in a diff comparison.
enum DiffLineType {
  /// Line added in the new version (+).
  added,

  /// Line removed from the old version (-).
  removed,

  /// Line unchanged between both versions.
  unchanged,

  /// Diff hunk header line (e.g. @@ -1,4 +1,5 @@).
  header,
}

/// A single rendered line inside a unified or side-by-side diff view.
class DiffLineWidget extends StatelessWidget {
  /// Creates a [DiffLineWidget].
  const DiffLineWidget({
    super.key,
    required this.text,
    required this.type,
  });

  /// The text content of this diff line.
  final String text;

  /// The classification of this diff line.
  final DiffLineType type;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (Color? backgroundColor, Color textColor) = switch (type) {
      DiffLineType.added => isDark
          ? (const Color(0xFF14381C), const Color(0xFF81C784))
          : (const Color(0xFFE6FFEC), const Color(0xFF1B5E20)),
      DiffLineType.removed => isDark
          ? (const Color(0xFF3F1719), const Color(0xFFE57373))
          : (const Color(0xFFFFEBE9), const Color(0xFFB71C1C)),
      DiffLineType.header => isDark
          ? (const Color(0xFF263238), const Color(0xFF90A4AE))
          : (const Color(0xFFECEFF1), const Color(0xFF455A64)),
      DiffLineType.unchanged => (
          null,
          Theme.of(context).colorScheme.onSurface,
        ),
    };

    final displayText = _formatDisplayText();

    return Container(
      width: double.infinity,
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Text(
        displayText,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.4,
          color: textColor,
          fontWeight: type == DiffLineType.header
              ? FontWeight.w600
              : FontWeight.normal,
        ),
      ),
    );
  }

  String _formatDisplayText() {
    return switch (type) {
      DiffLineType.added =>
        text.startsWith('+') ? text : '+ $text',
      DiffLineType.removed =>
        text.startsWith('-') ? text : '- $text',
      DiffLineType.unchanged =>
        text.startsWith(' ') ? text : '  $text',
      DiffLineType.header =>
        text.startsWith('@') ? text : '@@ $text @@',
    };
  }
}
