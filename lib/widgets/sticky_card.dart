import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sticky_notes_ssh/models/sticky_note.dart';
import 'package:sticky_notes_ssh/theme/app_theme.dart';
import 'package:sticky_notes_ssh/utils/markdown_checklist_helper.dart';
import 'package:sticky_notes_ssh/widgets/markdown_viewer.dart';

/// A sticky note card widget displaying title, preview, checklist items,
/// tags, pin indicator, and sync conflict badge.
class StickyCard extends StatelessWidget {
  /// Creates a [StickyCard].
  const StickyCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.onCheckboxToggle,
    this.isCompact = true,
    this.onLongPress,
  });

  /// The sticky note data model.
  final StickyNote note;

  /// Callback when the card is tapped.
  final VoidCallback onTap;

  /// Callback when a checklist item checkbox is toggled.
  final void Function(int lineIndex) onCheckboxToggle;

  /// Whether to render a compact clamped preview or full markdown viewer.
  final bool isCompact;

  /// Callback when the card is long-pressed.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = AppTheme.cardColor(note.colorIndex, theme.brightness);
    final isConflict = note.syncStatus == SyncStatus.conflict;

    final extractedTitle = MarkdownChecklistHelper.extractTitle(note.content);
    final displayTitle =
        note.title.trim().isNotEmpty ? note.title.trim() : extractedTitle;

    return Card(
      elevation: 1.5,
      margin: EdgeInsets.zero,
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isConflict
            ? const BorderSide(color: Color(0xFFE53935), width: 1.5)
            : BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.14)
                    : Colors.black.withValues(alpha: 0.06),
                width: 1,
              ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Nested folder indicator if present
              if (p.dirname(note.filename) != '.' &&
                  p.dirname(note.filename).isNotEmpty) ...<Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.folder_outlined,
                      size: 13,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        p.dirname(note.filename),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.8),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],

              // Header: Title & Pin icon
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      displayTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        height: 1.25,
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (note.isPinned) ...<Widget>[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.push_pin_rounded,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),

              // Markdown Content Viewer
              if (note.content.trim().isNotEmpty) ...<Widget>[
                MarkdownViewer(
                  markdown: note.content,
                  isCompact: isCompact,
                  maxCompactLines: 6,
                  skipFirstHeader: true,
                  filterTitle: displayTitle,
                  onCheckboxToggled: onCheckboxToggle,
                ),
              ],

              // Footer: Conflict badge (bottom-left) & Tags
              if (isConflict || note.tags.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    if (isConflict) ...<Widget>[
                      const _ConflictBadge(),
                      const SizedBox(width: 6),
                    ],
                    if (note.tags.isNotEmpty)
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: note.tags
                              .map((String tag) => _TagBadge(tag: tag))
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ConflictBadge extends StatelessWidget {
  const _ConflictBadge();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3F1719) : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? const Color(0xFFC62828) : const Color(0xFFEF9A9A),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.warning_amber_rounded,
            size: 12,
            color: isDark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828),
          ),
          const SizedBox(width: 3),
          Text(
            'Conflict',
            style: TextStyle(
              color: isDark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828),
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagBadge extends StatelessWidget {
  const _TagBadge({required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '#$tag',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
