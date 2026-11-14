import 'package:flutter/material.dart';
import 'package:sticky_notes_ssh/models/sticky_note.dart';
import 'package:sticky_notes_ssh/services/local_db_service.dart';
import 'package:sticky_notes_ssh/theme/app_theme.dart';
import 'package:sticky_notes_ssh/utils/markdown_checklist_helper.dart';
import 'package:sticky_notes_ssh/view_models/editor_view_model.dart';
import 'package:sticky_notes_ssh/widgets/color_picker_bar.dart';
import 'package:sticky_notes_ssh/widgets/markdown_toolbar.dart';
import 'package:sticky_notes_ssh/widgets/tag_editor.dart';

/// Screen for composing, previewing, and formatting Markdown sticky notes.
class NoteEditorScreen extends StatefulWidget {
  /// Creates a [NoteEditorScreen].
  const NoteEditorScreen({
    super.key,
    this.noteId,
  });

  /// The unique ID of an existing note, or `null` to create a new note.
  final String? noteId;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final EditorViewModel _viewModel;
  late final FocusNode _focusNode;
  bool _didSave = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _viewModel = EditorViewModel(noteId: widget.noteId);

    _viewModel.loadNote().then((_) {
      if (mounted) {
        setState(() {});
      }
    });

    _viewModel.contentController.addListener(_onContentChanged);
  }

  void _onContentChanged() {
    _viewModel.onContentChanged();
    setState(() {});
  }

  @override
  void dispose() {
    _viewModel.contentController.removeListener(_onContentChanged);
    _focusNode.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _handleBack() async {
    if (_viewModel.isDirty) {
      await _viewModel.saveNote();
      _didSave = true;
    }
    if (mounted) {
      Navigator.pop(context, _didSave);
    }
  }

  void _showTagEditorBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        const Text(
                          'Tags',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Done',
                          icon: const Icon(Icons.check),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TagEditor(
                      tags: _viewModel.tags,
                      onTagsChanged: (List<String> newTags) {
                        _viewModel.updateTags(newTags);
                        setSheetState(() {});
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDelete() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete this note?'),
          content: const Text(
            'This note will be deleted permanently from your phone and your laptop.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () async {
                Navigator.pop(dialogContext);
                final note = _viewModel.note;
                if (note != null) {
                  await LocalDbService().deleteNote(note.id);
                  await LocalDbService().deleteLocalFile(note.filename);
                }
                if (mounted) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBgColor =
        AppTheme.cardColor(_viewModel.colorIndex, theme.brightness);

    final rawContent = _viewModel.contentController.text;
    final derivedTitle = rawContent.trim().isEmpty
        ? 'New Note'
        : MarkdownChecklistHelper.extractTitle(rawContent);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (!didPop) {
          await _handleBack();
        }
      },
      child: Scaffold(
        backgroundColor: isDark
            ? Color.alphaBlend(
                cardBgColor.withValues(alpha: 0.25),
                theme.scaffoldBackgroundColor,
              )
            : Color.alphaBlend(
                cardBgColor.withValues(alpha: 0.35),
                theme.scaffoldBackgroundColor,
              ),
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Save and go back',
            onPressed: _handleBack,
          ),
          title: Text(
            derivedTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          actions: <Widget>[
            // Mode toggle buttons
            SegmentedButton<EditorMode>(
              segments: const <ButtonSegment<EditorMode>>[
                ButtonSegment<EditorMode>(
                  value: EditorMode.edit,
                  icon: Icon(Icons.edit_outlined, size: 16),
                  tooltip: 'Edit',
                ),
                ButtonSegment<EditorMode>(
                  value: EditorMode.preview,
                  icon: Icon(Icons.visibility_outlined, size: 16),
                  tooltip: 'Preview',
                ),
                ButtonSegment<EditorMode>(
                  value: EditorMode.split,
                  icon: Icon(Icons.vertical_split_outlined, size: 16),
                  tooltip: 'Split',
                ),
              ],
              selected: <EditorMode>{_viewModel.mode},
              onSelectionChanged: (Set<EditorMode> selected) {
                _viewModel.setMode(selected.first);
                setState(() {});
              },
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (String value) {
                if (value == 'delete') {
                  _confirmDelete();
                } else if (value == 'save') {
                  _viewModel.saveNote();
                }
              },
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'save',
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.save_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Save now'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Delete note',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              if (_viewModel.isSaving) const LinearProgressIndicator(),
              Expanded(
                child: _buildBody(context),
              ),
              _buildBottomBar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;

    return switch (_viewModel.mode) {
      EditorMode.edit => _buildEditArea(),
      EditorMode.preview => _buildPreviewArea(),
      EditorMode.split => orientation == Orientation.landscape
          ? Row(
              children: <Widget>[
                Expanded(child: _buildEditArea()),
                const VerticalDivider(width: 1),
                Expanded(child: _buildPreviewArea()),
              ],
            )
          : Column(
              children: <Widget>[
                Expanded(child: _buildEditArea()),
                const Divider(height: 1),
                Expanded(child: _buildPreviewArea()),
              ],
            ),
    };
  }

  Widget _buildEditArea() {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: MarkdownToolbar(
            controller: _viewModel.contentController,
            focusNode: _focusNode,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _viewModel.contentController,
              focusNode: _focusNode,
              maxLines: null,
              expands: true,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14.5,
                height: 1.45,
              ),
              decoration: const InputDecoration(
                hintText: 'Start writing Markdown...',
                border: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewArea() {
    final markdown = _viewModel.contentController.text;
    if (markdown.trim().isEmpty) {
      return const Center(
        child: Text(
          'Nothing to preview.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return _SimpleMarkdownRenderer(
      markdown: markdown,
      onCheckboxToggled: (int lineIndex) {
        final toggled =
            MarkdownChecklistHelper.toggleCheckbox(markdown, lineIndex);
        _viewModel.contentController.text = toggled;
      },
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final theme = Theme.of(context);

    final syncText = _viewModel.isSaving
        ? 'Saving...'
        : _viewModel.isDirty
            ? 'Unsaved changes'
            : _viewModel.note?.syncStatus == SyncStatus.synced
                ? 'Synced'
                : 'Saved locally';

    final isDark = theme.brightness == Brightness.dark;
    final unsavedColor = isDark ? const Color(0xFFFFB74D) : const Color(0xFFB25E00);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            // Note color picker bar
            ColorPickerBar(
              selectedIndex: _viewModel.colorIndex,
              onColorSelected: (int index) {
                _viewModel.setColor(index);
                setState(() {});
              },
            ),
            const SizedBox(width: 4),

            // Pin toggle button
            IconButton(
              tooltip: _viewModel.isPinned ? 'Unpin' : 'Pin',
              icon: Icon(
                _viewModel.isPinned
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
                color: _viewModel.isPinned ? theme.colorScheme.primary : null,
                size: 20,
              ),
              onPressed: () {
                _viewModel.togglePin();
                setState(() {});
              },
            ),

            // Tag editor button
            IconButton(
              tooltip: 'Edit tags',
              icon: Badge(
                isLabelVisible: _viewModel.tags.isNotEmpty,
                label: Text('${_viewModel.tags.length}'),
                child: const Icon(Icons.label_outline, size: 20),
              ),
              onPressed: _showTagEditorBottomSheet,
            ),

            const SizedBox(width: 16),

            // Word / char count & Sync status
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  '${_viewModel.wordCount} words, ${_viewModel.charCount} chars',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  syncText,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: _viewModel.isDirty
                        ? unsavedColor
                        : theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// A custom, lightweight Markdown preview renderer widget that parses
/// headings, bold, italic, code blocks, checklists, and bullet items without external packages.
class _SimpleMarkdownRenderer extends StatelessWidget {
  const _SimpleMarkdownRenderer({
    required this.markdown,
    required this.onCheckboxToggled,
  });

  final String markdown;
  final ValueChanged<int> onCheckboxToggled;

  @override
  Widget build(BuildContext context) {
    final lines = markdown.split(RegExp(r'\r?\n'));
    final widgets = <Widget>[];

    var inCodeBlock = false;
    final codeBlockLines = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Code block start / end
      if (line.trim().startsWith('```')) {
        if (inCodeBlock) {
          // Finish code block
          widgets.add(_buildCodeBlock(context, codeBlockLines.join('\n')));
          codeBlockLines.clear();
          inCodeBlock = false;
        } else {
          inCodeBlock = true;
        }
        continue;
      }

      if (inCodeBlock) {
        codeBlockLines.add(line);
        continue;
      }

      final trimmed = line.trim();

      // Horizontal rule
      if (trimmed == '---' || trimmed == '***' || trimmed == '___') {
        widgets.add(const Divider(height: 16));
        continue;
      }

      // Checklists: - [ ] or - [x]
      final checklistMatch = RegExp(r'^\s*-\s*\[([ xX])\]\s?(.*)$').firstMatch(line);
      if (checklistMatch != null) {
        final isChecked = checklistMatch.group(1)!.toLowerCase() == 'x';
        final text = checklistMatch.group(2) ?? '';
        final lineIndex = i;

        widgets.add(
          Semantics(
            button: true,
            toggled: isChecked,
            label: '$text, ${isChecked ? "completed" : "not completed"}',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: InkWell(
                onTap: () => onCheckboxToggled(lineIndex),
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      isChecked
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank,
                      size: 19,
                      color: isChecked
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        _buildInlineSpans(
                          context,
                          text,
                          TextStyle(
                            fontSize: 14,
                            decoration: isChecked
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                            color: isChecked
                                ? Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.6)
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        continue;
      }

      // Headings
      if (trimmed.startsWith('# ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Text(
              trimmed.substring(2),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                height: 1.25,
              ),
            ),
          ),
        );
        continue;
      }

      if (trimmed.startsWith('## ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Text(
              trimmed.substring(3),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                height: 1.25,
              ),
            ),
          ),
        );
        continue;
      }

      if (trimmed.startsWith('### ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Text(
              trimmed.substring(4),
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.bold,
                height: 1.25,
              ),
            ),
          ),
        );
        continue;
      }

      // Bullet list item
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('• ', style: TextStyle(fontSize: 16)),
                Expanded(
                  child: Text.rich(
                    _buildInlineSpans(
                      context,
                      trimmed.substring(2),
                      const TextStyle(fontSize: 14, height: 1.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // Empty line
      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      // Regular paragraph
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text.rich(
            _buildInlineSpans(
              context,
              line,
              const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
        ),
      );
    }

    if (inCodeBlock && codeBlockLines.isNotEmpty) {
      widgets.add(_buildCodeBlock(context, codeBlockLines.join('\n')));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: widgets,
    );
  }

  Widget _buildCodeBlock(BuildContext context, String code) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          code,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
      ),
    );
  }

  TextSpan _buildInlineSpans(
    BuildContext context,
    String text,
    TextStyle baseStyle,
  ) {
    final spans = <InlineSpan>[];
    // Regex matching **bold**, _italic_, and `inline code`
    final regex = RegExp(r'(\*\*([^*]+)\*\*|_([^_]+)_|`([^`]+)`)');
    var lastIndex = 0;

    for (final match in regex.allMatches(text)) {
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
        // Italic: _text_
        spans.add(
          TextSpan(
            text: match.group(3),
            style: baseStyle.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      } else if (match.group(4) != null) {
        // Inline code: `code`
        spans.add(
          TextSpan(
            text: match.group(4),
            style: baseStyle.copyWith(
              fontFamily: 'monospace',
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF333333)
                  : const Color(0xFFE0E0E0),
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
