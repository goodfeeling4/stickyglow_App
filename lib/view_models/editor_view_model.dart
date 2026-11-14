import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sticky_notes_ssh/models/sticky_note.dart';
import 'package:sticky_notes_ssh/services/local_db_service.dart';
import 'package:sticky_notes_ssh/utils/markdown_checklist_helper.dart';
import 'package:uuid/uuid.dart';

/// Available display modes in the note editor.
enum EditorMode {
  /// Edit mode showing the Markdown input text area.
  edit,

  /// Preview mode rendering formatted Markdown.
  preview,

  /// Split mode displaying editor and preview side by side.
  split,
}

/// ViewModel managing state, auto-saving, debounced sync, formatting,
/// and metadata for a single sticky note editor session.
class EditorViewModel extends ChangeNotifier {
  /// Creates an [EditorViewModel] instance.
  ///
  /// [noteId] is the unique identifier of an existing note to edit, or `null`
  /// when composing a newly created sticky note.
  EditorViewModel({
    LocalDbService? localDbService,
    this.noteId,
  })  : _localDbService = localDbService ?? LocalDbService(),
        contentController = TextEditingController();

  final LocalDbService _localDbService;

  /// The unique note ID if editing an existing note, or `null` for a new note.
  final String? noteId;

  /// Text editing controller for the note content.
  final TextEditingController contentController;

  StickyNote? _note;
  int _colorIndex = 0;
  bool _isPinned = false;
  List<String> _tags = <String>[];
  bool _isDirty = false;
  bool _isSaving = false;
  EditorMode _mode = EditorMode.edit;
  Timer? _autoSaveTimer;

  /// The currently loaded note model, or `null` if creating a new note not yet saved.
  StickyNote? get note => _note;

  /// Pastel card color index (0-5).
  int get colorIndex => _colorIndex;

  /// Whether the note is pinned.
  bool get isPinned => _isPinned;

  /// List of tags attached to this note.
  List<String> get tags => List<String>.unmodifiable(_tags);

  /// Whether there are unsaved local modifications.
  bool get isDirty => _isDirty;

  /// Whether a save operation is actively in flight.
  bool get isSaving => _isSaving;

  /// Current display mode (edit, preview, or split).
  EditorMode get mode => _mode;

  /// Word count of the current content.
  int get wordCount {
    final text = contentController.text.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).length;
  }

  /// Character count of the current content.
  int get charCount => contentController.text.length;

  /// Loads the note from SQLite if [noteId] is non-null, or initializes empty note state.
  Future<void> loadNote() async {
    if (noteId != null) {
      final existing = await _localDbService.getNoteById(noteId!);
      if (existing != null) {
        _note = existing;
        contentController.text = existing.content;
        _colorIndex = existing.colorIndex;
        _isPinned = existing.isPinned;
        _tags = List<String>.from(existing.tags);
        _isDirty = false;
        notifyListeners();
        return;
      }
    }

    _note = null;
    contentController.text = '';
    _colorIndex = 0;
    _isPinned = false;
    _tags = <String>[];
    _isDirty = false;
    notifyListeners();
  }

  /// Persists current content and metadata to SQLite and disk with [SyncStatus.pending].
  Future<void> saveNote() async {
    if (_isSaving) return;
    _isSaving = true;
    notifyListeners();

    try {
      final content = contentController.text;
      final title = MarkdownChecklistHelper.extractTitle(content);
      final now = DateTime.now();

      final StickyNote noteToSave;
      if (_note != null) {
        noteToSave = _note!.copyWith(
          title: title,
          content: content,
          colorIndex: _colorIndex,
          isPinned: _isPinned,
          tags: List<String>.from(_tags),
          updatedAt: now,
          syncStatus: SyncStatus.pending,
        );
        await _localDbService.updateNote(noteToSave);
      } else {
        final id = const Uuid().v4();
        final filename = StickyNote.filenameFromTitle(title);
        noteToSave = StickyNote(
          id: id,
          filename: filename,
          title: title,
          content: content,
          colorIndex: _colorIndex,
          isPinned: _isPinned,
          tags: List<String>.from(_tags),
          createdAt: now,
          updatedAt: now,
          syncStatus: SyncStatus.pending,
        );
        await _localDbService.insertNote(noteToSave);
      }

      await _localDbService.writeLocalFile(
        noteToSave.filename,
        noteToSave.content,
      );

      _note = noteToSave;
      _isDirty = false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Sets the pastel card color palette index (0-5) and marks dirty.
  void setColor(int index) {
    if (_colorIndex == index) return;
    _colorIndex = index;
    _isDirty = true;
    notifyListeners();
  }

  /// Toggles the pin status and marks dirty.
  void togglePin() {
    _isPinned = !_isPinned;
    _isDirty = true;
    notifyListeners();
  }

  /// Updates the list of tags attached to this note and marks dirty.
  void updateTags(List<String> tags) {
    _tags = List<String>.from(tags);
    _isDirty = true;
    notifyListeners();
  }

  /// Changes the editor mode (edit, preview, or split).
  void setMode(EditorMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  /// Starts or resets the 3-second debounced auto-save timer.
  void startAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 3), () {
      if (_isDirty && !_isSaving) {
        saveNote();
      }
    });
  }

  /// Callback when content in [contentController] changes, marking dirty
  /// and resetting the auto-save timer.
  void onContentChanged() {
    _isDirty = true;
    startAutoSave();
    notifyListeners();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    contentController.dispose();
    super.dispose();
  }
}
