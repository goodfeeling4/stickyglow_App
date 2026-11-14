/// Helper class for parsing, querying, and manipulating Markdown checklist items
/// and extracting titles and previews from raw Markdown strings.
class MarkdownChecklistHelper {
  MarkdownChecklistHelper._();

  /// Regex pattern matching Markdown checkbox lines:
  /// optional whitespace + `- [ ]` or `- [x]` (case-insensitive for 'x' / 'X').
  ///
  /// Group 1: Leading whitespace and `- [`
  /// Group 2: The checkbox mark (`' '`, `'x'`, or `'X'`)
  /// Group 3: The closing bracket `]`
  /// Group 4: The remainder of the line
  static final RegExp _checkboxToggleRegex =
      RegExp(r'^(\s*-\s*\[)([ xX])(\])(.*)$');

  /// Regex pattern matching checklist items and capturing their checked state and text.
  ///
  /// Group 1: `' '`, `'x'`, or `'X'`
  /// Group 2: The checklist item text (following optional single space after `]`)
  static final RegExp _checklistLineRegex =
      RegExp(r'^\s*-\s*\[([ xX])\]\s?(.*)$');

  /// Toggles `- [ ]` ↔ `- [x]` in [markdown] at the specified 0-based [lineIndex].
  ///
  /// Returns the modified Markdown string. If [lineIndex] is out of range or
  /// if the line at [lineIndex] is not a checkbox line, returns [markdown] unchanged.
  static String toggleCheckbox(String markdown, int lineIndex) {
    if (lineIndex < 0) return markdown;

    final isCrlf = markdown.contains('\r\n');
    final lines = markdown.split(RegExp(r'\r?\n'));

    if (lineIndex >= lines.length) return markdown;

    final line = lines[lineIndex];
    final match = _checkboxToggleRegex.firstMatch(line);
    if (match == null) {
      return markdown;
    }

    final prefix = match.group(1)!;
    final check = match.group(2)!;
    final closeBracket = match.group(3)!;
    final rest = match.group(4)!;

    final toggledCheck = (check == ' ') ? 'x' : ' ';
    lines[lineIndex] = '$prefix$toggledCheck$closeBracket$rest';

    return lines.join(isCrlf ? '\r\n' : '\n');
  }

  /// Counts lines matching `- [ ]` and `- [x]` (case-insensitive) patterns in [markdown].
  ///
  /// Returns a record with the [total] checklist count and [checked] count.
  static ({int total, int checked}) countChecklistItems(String markdown) {
    final lines = markdown.split(RegExp(r'\r?\n'));
    var total = 0;
    var checked = 0;

    for (final line in lines) {
      final match = _checklistLineRegex.firstMatch(line);
      if (match != null) {
        total++;
        if (match.group(1)!.toLowerCase() == 'x') {
          checked++;
        }
      }
    }

    return (total: total, checked: checked);
  }

  /// Extracts the title from [markdown].
  ///
  /// Returns the text of the first `# Heading` line (without the `# `).
  /// If no heading line is present, returns the first non-empty line trimmed.
  /// If the content is empty or contains only whitespace, returns `'Untitled'`.
  static String extractTitle(String markdown) {
    final lines = markdown.split(RegExp(r'\r?\n'));

    // First search for any markdown heading starting with #
    for (final rawLine in lines) {
      final trimmed = rawLine.trim();
      final match = RegExp(r'^#+\s+(.+)$').firstMatch(trimmed);
      if (match != null) {
        final heading = match.group(1)!.trim();
        if (heading.isNotEmpty) {
          return heading;
        }
      }
    }

    // If no heading, return the first non-empty line trimmed
    for (final rawLine in lines) {
      final trimmed = rawLine.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }

    return 'Untitled';
  }

  /// Extracts all checklist items from [markdown].
  ///
  /// Returns a list of records containing the 0-based [lineIndex], the [text]
  /// content (without the `- [ ] ` or `- [x] ` prefix), and the [isChecked] state.
  static List<({int lineIndex, String text, bool isChecked})> getChecklistLines(
    String markdown,
  ) {
    final result = <({int lineIndex, String text, bool isChecked})>[];
    final lines = markdown.split(RegExp(r'\r?\n'));

    for (var i = 0; i < lines.length; i++) {
      final match = _checklistLineRegex.firstMatch(lines[i]);
      if (match != null) {
        final isChecked = match.group(1)!.toLowerCase() == 'x';
        final text = match.group(2) ?? '';
        result.add((lineIndex: i, text: text, isChecked: isChecked));
      }
    }

    return result;
  }

  /// Returns a plain text preview of [markdown].
  ///
  /// Strips `#`, `*`, `-`, `[x]`, `[ ]` markers, collapses whitespace,
  /// and truncates to [maxLength] with `'...'` if needed.
  static String extractPreview(String markdown, {int maxLength = 150}) {
    var text = markdown;

    // Strip checkbox markers [x], [X], [ ]
    text = text.replaceAll(RegExp(r'\[[ xX]\]'), '');

    // Strip #, *, - markers
    text = text.replaceAll(RegExp(r'[#*-]'), '');

    // Collapse whitespace (including newlines and tabs) and trim
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (text.length > maxLength) {
      if (maxLength <= 0) {
        return '...';
      }
      return '${text.substring(0, maxLength)}...';
    }

    return text;
  }
}
