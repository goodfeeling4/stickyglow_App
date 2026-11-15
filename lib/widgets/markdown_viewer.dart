import 'package:flutter/material.dart';

/// A lightweight, accessible, pure Flutter Markdown viewer widget.
///
/// Renders headers, checklists with interactive tap callbacks and accessibility
/// semantics, bullet lists, numbered lists, blockquotes, code blocks, horizontal
/// rules, and inline styling (**bold**, *italic*, ~~strikethrough~~, `code`).
class MarkdownViewer extends StatelessWidget {
  /// Creates a [MarkdownViewer].
  const MarkdownViewer({
    super.key,
    required this.markdown,
    this.onCheckboxToggled,
    this.isCompact = false,
    this.maxCompactLines,
    this.skipFirstHeader = false,
    this.filterTitle,
    this.baseTextStyle,
    this.shrinkWrap = true,
  });

  /// The raw markdown content.
  final String markdown;

  /// Callback invoked with the 0-based line index when a checklist item is tapped.
  final ValueChanged<int>? onCheckboxToggled;

  /// When true, renders with scaled padding and fonts for grid cards.
  final bool isCompact;

  /// Optional maximum items or lines to display before showing more items indicator.
  final int? maxCompactLines;

  /// If true, skips the first `# Header` line if it matches [filterTitle].
  final bool skipFirstHeader;

  /// The title used to compare against the first header to prevent duplicate titles.
  final String? filterTitle;

  /// Optional base style for body text.
  final TextStyle? baseTextStyle;

  /// Whether to shrink-wrap the content in a [Column] instead of a scrollable [ListView].
  final bool shrinkWrap;

  static final RegExp _checklistRegex =
      RegExp(r'^\s*-\s*\[([ xX])\]\s?(.*)$');
  static final RegExp _numberedListRegex =
      RegExp(r'^\s*(\d+)\.\s+(.*)$');
  static final RegExp _inlineSpanRegex = RegExp(
    r'(\*\*([^*]+)\*\*|__([^_]+)__|~~([^~]+)~~|_([^_]+)_|\*([^*]+)\*|`([^`]+)`|\[([^\]]+)\]\(([^)]+)\))',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final defaultBodyStyle = baseTextStyle ??
        TextStyle(
          fontSize: isCompact ? 13.5 : 14.5,
          height: 1.5,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.88),
        );

    final rawLines = markdown.split(RegExp(r'\r?\n'));
    final widgets = <Widget>[];

    var inCodeBlock = false;
    final codeBlockLines = <String>[];
    var skippedFirstHeader = false;
    var renderedItemsCount = 0;
    var totalRemainingItems = 0;

    for (var i = 0; i < rawLines.length; i++) {
      final line = rawLines[i];
      final trimmed = line.trim();

      // Skip first header if requested and matches filterTitle
      if (!skippedFirstHeader && skipFirstHeader && trimmed.startsWith('#')) {
        final match = RegExp(r'^#+\s*(.*)$').firstMatch(trimmed);
        if (match != null) {
          final headerText = match.group(1)?.trim() ?? '';
          if (filterTitle == null ||
              filterTitle!.trim().isEmpty ||
              filterTitle!.trim().toLowerCase() == headerText.toLowerCase()) {
            skippedFirstHeader = true;
            continue;
          }
        }
      }

      // Code block start / end
      if (trimmed.startsWith('```')) {
        if (inCodeBlock) {
          inCodeBlock = false;
          if (maxCompactLines != null && renderedItemsCount >= maxCompactLines!) {
            totalRemainingItems++;
            continue;
          }
          widgets.add(_buildCodeBlock(context, codeBlockLines.join('\n'), isDark));
          codeBlockLines.clear();
          renderedItemsCount++;
        } else {
          inCodeBlock = true;
        }
        continue;
      }

      if (inCodeBlock) {
        codeBlockLines.add(line);
        continue;
      }

      // Check compact limit if maxCompactLines is specified
      if (maxCompactLines != null && renderedItemsCount >= maxCompactLines!) {
        if (trimmed.isNotEmpty) {
          totalRemainingItems++;
        }
        continue;
      }

      // Horizontal rule
      if (trimmed == '---' || trimmed == '***' || trimmed == '___') {
        widgets.add(const Divider(height: 12, thickness: 0.8));
        renderedItemsCount++;
        continue;
      }

      // Checklist item: - [ ] or - [x]
      final checklistMatch = _checklistRegex.firstMatch(line);
      if (checklistMatch != null) {
        final isChecked = checklistMatch.group(1)!.toLowerCase() == 'x';
        final text = checklistMatch.group(2) ?? '';
        final lineIndex = i;

        widgets.add(
          _buildChecklistItem(
            context,
            text: text,
            isChecked: isChecked,
            lineIndex: lineIndex,
            baseStyle: defaultBodyStyle,
          ),
        );
        renderedItemsCount++;
        continue;
      }

      // Headings (H1 to H6)
      if (trimmed.startsWith('#')) {
        final headingMatch = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
        if (headingMatch != null) {
          final level = headingMatch.group(1)!.length;
          final headingText = headingMatch.group(2)!;
          widgets.add(_buildHeading(context, level, headingText));
          renderedItemsCount++;
          continue;
        }
      }

      // Blockquote
      if (trimmed.startsWith('> ') || trimmed == '>') {
        final quoteText = trimmed.length > 2 ? trimmed.substring(2) : '';
        widgets.add(_buildBlockquote(context, quoteText, defaultBodyStyle));
        renderedItemsCount++;
        continue;
      }

      // Bullet list item
      if (trimmed.startsWith('- ') ||
          trimmed.startsWith('* ') ||
          trimmed.startsWith('+ ')) {
        final bulletText = trimmed.substring(2);
        widgets.add(_buildBulletItem(context, bulletText, defaultBodyStyle));
        renderedItemsCount++;
        continue;
      }

      // Numbered list item
      final numberedMatch = _numberedListRegex.firstMatch(trimmed);
      if (numberedMatch != null) {
        final number = numberedMatch.group(1)!;
        final listText = numberedMatch.group(2)!;
        widgets.add(
          _buildNumberedItem(context, number, listText, defaultBodyStyle),
        );
        renderedItemsCount++;
        continue;
      }

      // Empty line
      if (trimmed.isEmpty) {
        if (widgets.isNotEmpty && widgets.last is! SizedBox) {
          widgets.add(SizedBox(height: isCompact ? 4 : 8));
        }
        continue;
      }

      // Regular paragraph
      widgets.add(
        Padding(
          padding: EdgeInsets.symmetric(vertical: isCompact ? 1.5 : 2.5),
          child: _buildFormattedText(context, line, defaultBodyStyle),
        ),
      );
      renderedItemsCount++;
    }

    if (inCodeBlock && codeBlockLines.isNotEmpty) {
      widgets.add(_buildCodeBlock(context, codeBlockLines.join('\n'), isDark));
    }

    if (maxCompactLines != null && totalRemainingItems > 0) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 2),
          child: Text(
            '+$totalRemainingItems more items',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    if (shrinkWrap) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: widgets,
      );
    }

    return ListView(
      padding: EdgeInsets.all(isCompact ? 8 : 16),
      children: widgets,
    );
  }

  Widget _buildChecklistItem(
    BuildContext context, {
    required String text,
    required bool isChecked,
    required int lineIndex,
    required TextStyle baseStyle,
  }) {
    final theme = Theme.of(context);
    final itemStyle = baseStyle.copyWith(
      decoration: isChecked ? TextDecoration.lineThrough : TextDecoration.none,
      color: isChecked
          ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
          : theme.colorScheme.onSurface,
    );

    return Semantics(
      button: true,
      toggled: isChecked,
      label: '$text, ${isChecked ? "completed" : "not completed"}',
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: isCompact ? 1.5 : 3),
        child: InkWell(
          onTap: () => onCheckboxToggled?.call(lineIndex),
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: isCompact ? 28 : 36),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    isChecked
                        ? Icons.check_box_outlined
                        : Icons.check_box_outline_blank,
                    size: isCompact ? 17 : 20,
                    color: isChecked
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildFormattedText(
                    context,
                    text,
                    itemStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeading(BuildContext context, int level, String text) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dividerColor =
        isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE);

    double fontSize;
    FontWeight fontWeight = FontWeight.w600;
    bool hasDivider = false;
    Color? color = theme.colorScheme.onSurface;

    switch (level) {
      case 1:
        fontSize = isCompact ? 20 : 25;
        fontWeight = FontWeight.bold;
        hasDivider = true;
        break;
      case 2:
        fontSize = isCompact ? 17 : 20;
        fontWeight = FontWeight.w600;
        hasDivider = true;
        break;
      case 3:
        fontSize = isCompact ? 15 : 17;
        fontWeight = FontWeight.w600;
        break;
      case 4:
        fontSize = isCompact ? 13.5 : 15;
        fontWeight = FontWeight.w600;
        break;
      case 5:
        fontSize = isCompact ? 12.5 : 13.5;
        fontWeight = FontWeight.w600;
        break;
      case 6:
      default:
        fontSize = isCompact ? 11.5 : 12.5;
        fontWeight = FontWeight.w600;
        color = theme.colorScheme.onSurfaceVariant;
        break;
    }

    final headingWidget = Padding(
      padding: EdgeInsets.only(
        top: isCompact ? (level <= 2 ? 6.0 : 4.0) : (level <= 2 ? 10.0 : 6.0),
        bottom: hasDivider ? 4.0 : (isCompact ? 2.0 : 4.0),
      ),
      child: _buildFormattedText(
        context,
        text,
        TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: 1.25,
          color: color,
        ),
      ),
    );

    if (hasDivider) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          headingWidget,
          Divider(
            height: 6,
            thickness: 0.8,
            color: dividerColor,
          ),
          SizedBox(height: isCompact ? 2 : 4),
        ],
      );
    }

    return headingWidget;
  }

  Widget _buildBulletItem(
    BuildContext context,
    String text,
    TextStyle baseStyle,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isCompact ? 1 : 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '• ',
            style: TextStyle(
              fontSize: isCompact ? 14 : 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildFormattedText(
              context,
              text,
              baseStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberedItem(
    BuildContext context,
    String number,
    String text,
    TextStyle baseStyle,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isCompact ? 1 : 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$number. ',
            style: TextStyle(
              fontSize: isCompact ? 12.5 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildFormattedText(
              context,
              text,
              baseStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockquote(
    BuildContext context,
    String text,
    TextStyle baseStyle,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: EdgeInsets.symmetric(vertical: isCompact ? 2 : 4),
      padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: isDark
                ? const Color(0xFF3B82F6)
                : theme.colorScheme.primary.withValues(alpha: 0.7),
            width: 3.5,
          ),
        ),
      ),
      child: _buildFormattedText(
        context,
        text,
        baseStyle.copyWith(
          fontStyle: FontStyle.italic,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
        ),
      ),
    );
  }

  Widget _buildCodeBlock(BuildContext context, String code, bool isDark) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: isCompact ? 4 : 8),
      padding: EdgeInsets.all(isCompact ? 8 : 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE),
          width: 0.8,
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          code,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: isCompact ? 11.5 : 13,
            height: 1.45,
            color: isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328),
          ),
        ),
      ),
    );
  }

  Widget _buildFormattedText(
    BuildContext context,
    String text,
    TextStyle baseStyle, {
    int? maxLines,
  }) {
    // If text has no inline markdown tokens, return a plain Text widget
    if (!_inlineSpanRegex.hasMatch(text)) {
      return Text(
        text,
        style: baseStyle,
        maxLines: maxLines,
        overflow: maxLines != null ? TextOverflow.ellipsis : null,
      );
    }

    return Text.rich(
      _buildInlineSpans(context, text, baseStyle),
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : null,
    );
  }

  TextSpan _buildInlineSpans(
    BuildContext context,
    String text,
    TextStyle baseStyle,
  ) {
    final spans = <InlineSpan>[];
    var lastIndex = 0;

    for (final match in _inlineSpanRegex.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(
          TextSpan(
            text: text.substring(lastIndex, match.start),
            style: baseStyle,
          ),
        );
      }

      if (match.group(2) != null) {
        // Bold: **text**
        spans.add(
          TextSpan(
            text: match.group(2),
            style: baseStyle.copyWith(fontWeight: FontWeight.bold),
          ),
        );
      } else if (match.group(3) != null) {
        // Bold: __text__
        spans.add(
          TextSpan(
            text: match.group(3),
            style: baseStyle.copyWith(fontWeight: FontWeight.bold),
          ),
        );
      } else if (match.group(4) != null) {
        // Strikethrough: ~~text~~
        spans.add(
          TextSpan(
            text: match.group(4),
            style: baseStyle.copyWith(decoration: TextDecoration.lineThrough),
          ),
        );
      } else if (match.group(5) != null) {
        // Italic: _text_
        spans.add(
          TextSpan(
            text: match.group(5),
            style: baseStyle.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      } else if (match.group(6) != null) {
        // Italic: *text*
        spans.add(
          TextSpan(
            text: match.group(6),
            style: baseStyle.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      } else if (match.group(7) != null) {
        // Inline code: `code`
        final isDark = Theme.of(context).brightness == Brightness.dark;
        spans.add(
          TextSpan(
            text: ' ${match.group(7)} ',
            style: baseStyle.copyWith(
              fontFamily: 'monospace',
              fontSize: (baseStyle.fontSize ?? 14) * 0.9,
              backgroundColor: isDark
                  ? const Color(0xFF333333)
                  : const Color(0xFFE4E4E4),
            ),
          ),
        );
      } else if (match.group(8) != null) {
        // Link: [text](url)
        spans.add(
          TextSpan(
            text: match.group(8),
            style: baseStyle.copyWith(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        );
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(lastIndex),
          style: baseStyle,
        ),
      );
    }

    return TextSpan(children: spans);
  }
}
