import 'package:flutter/material.dart';

/// A horizontal formatting toolbar that inserts Markdown syntax into a [TextEditingController].
class MarkdownToolbar extends StatelessWidget {
  /// Creates a [MarkdownToolbar].
  const MarkdownToolbar({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  /// The active text controller of the Markdown editor.
  final TextEditingController controller;

  /// Focus node associated with the editor text field.
  final FocusNode focusNode;

  void _insertMarkdown({
    required String prefix,
    String suffix = '',
  }) {
    final text = controller.text;
    final selection = controller.selection;

    int start = selection.start;
    int end = selection.end;

    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    } else if (start > end) {
      final temp = start;
      start = end;
      end = temp;
    }

    final selectedText = text.substring(start, end);
    final String replacement;
    final int newSelectionStart;
    final int newSelectionEnd;

    if (selectedText.isNotEmpty) {
      replacement = '$prefix$selectedText$suffix';
      newSelectionStart = start + prefix.length;
      newSelectionEnd = start + prefix.length + selectedText.length;
    } else {
      replacement = '$prefix$suffix';
      newSelectionStart = start + prefix.length;
      newSelectionEnd = start + prefix.length;
    }

    final newText = text.replaceRange(start, end, replacement);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: newSelectionStart,
        extentOffset: newSelectionEnd,
      ),
    );

    focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = theme.colorScheme.onSurfaceVariant;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _ToolbarButton(
              tooltip: 'Heading 1',
              onPressed: () => _insertMarkdown(prefix: '# '),
              child: Text(
                'H1',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: iconColor,
                ),
              ),
            ),
            _ToolbarButton(
              tooltip: 'Heading 2',
              onPressed: () => _insertMarkdown(prefix: '## '),
              child: Text(
                'H2',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: iconColor,
                ),
              ),
            ),
            const _ToolbarDivider(),
            _ToolbarButton(
              tooltip: 'Bold (**text**)',
              onPressed: () => _insertMarkdown(prefix: '**', suffix: '**'),
              child: Icon(Icons.format_bold, size: 20, color: iconColor),
            ),
            _ToolbarButton(
              tooltip: 'Italic (_text_)',
              onPressed: () => _insertMarkdown(prefix: '_', suffix: '_'),
              child: Icon(Icons.format_italic, size: 20, color: iconColor),
            ),
            const _ToolbarDivider(),
            _ToolbarButton(
              tooltip: 'Checklist (- [ ])',
              onPressed: () => _insertMarkdown(prefix: '- [ ] '),
              child: Icon(
                Icons.check_box_outlined,
                size: 20,
                color: iconColor,
              ),
            ),
            _ToolbarButton(
              tooltip: 'Bullet List (- )',
              onPressed: () => _insertMarkdown(prefix: '- '),
              child: Icon(
                Icons.format_list_bulleted,
                size: 20,
                color: iconColor,
              ),
            ),
            const _ToolbarDivider(),
            _ToolbarButton(
              tooltip: 'Code Block (```)',
              onPressed: () => _insertMarkdown(
                prefix: '```\n',
                suffix: '\n```',
              ),
              child: Icon(Icons.code, size: 20, color: iconColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 48,
              minHeight: 48,
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
      ),
    );
  }
}
