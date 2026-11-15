import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sticky_notes_ssh/models/sticky_note.dart';
import 'package:sticky_notes_ssh/services/local_db_service.dart';
import 'package:sticky_notes_ssh/theme/app_theme.dart';
import 'package:sticky_notes_ssh/utils/markdown_checklist_helper.dart';
import 'package:sticky_notes_ssh/view_models/editor_view_model.dart';
import 'package:sticky_notes_ssh/widgets/color_picker_bar.dart';
import 'package:sticky_notes_ssh/widgets/markdown_toolbar.dart';
import 'package:sticky_notes_ssh/widgets/markdown_viewer.dart';
import 'package:sticky_notes_ssh/widgets/tag_editor.dart';

/// Screen for composing, previewing, and formatting Markdown sticky notes.
class NoteEditorScreen extends StatefulWidget {
  /// Creates a [NoteEditorScreen].
  const NoteEditorScreen({
    super.key,
    this.noteId,
    this.profileId,
  });

  /// The unique ID of an existing note, or `null` to create a new note.
  final String? noteId;

  /// The profile ID compartment this note belongs to.
  final String? profileId;

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
    _viewModel = EditorViewModel(
      noteId: widget.noteId,
      profileId: widget.profileId,
    );

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
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_viewModel.note != null &&
                  p.dirname(_viewModel.note!.filename) != '.' &&
                  p.dirname(_viewModel.note!.filename).isNotEmpty)
                Text(
                  '📁 ${p.dirname(_viewModel.note!.filename)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              Text(
                derivedTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ],
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

    return MarkdownViewer(
      markdown: markdown,
      shrinkWrap: false,
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
