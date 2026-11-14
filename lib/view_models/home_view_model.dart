import 'package:flutter/foundation.dart';
import 'package:sticky_notes_ssh/models/sticky_note.dart';
import 'package:sticky_notes_ssh/services/local_db_service.dart';
import 'package:sticky_notes_ssh/services/ssh_sync_service.dart';
import 'package:sticky_notes_ssh/utils/markdown_checklist_helper.dart';
import 'package:sticky_notes_ssh/widgets/sync_status_pill.dart';

/// ViewModel managing the main home screen state, note collection,
/// filtering, search, note mutations, and remote SSH sync execution.
class HomeViewModel extends ChangeNotifier {
  /// Creates a [HomeViewModel] with optional service dependencies for testing.
  HomeViewModel({
    LocalDbService? localDbService,
    SshSyncService? sshSyncService,
  })  : _localDbService = localDbService ?? LocalDbService(),
        _sshSyncService = sshSyncService ?? SshSyncService();

  final LocalDbService _localDbService;
  final SshSyncService _sshSyncService;

  List<StickyNote> _notes = const <StickyNote>[];
  List<StickyNote> _filteredNotes = const <StickyNote>[];
  String _searchQuery = '';
  String? _activeTag;
  SyncState _syncState = SyncState.offline;
  bool _isLoading = false;

  /// All sticky notes loaded from the local database.
  List<StickyNote> get notes => _notes;

  /// Notes matching the current search query and active tag filter.
  List<StickyNote> get filteredNotes => _filteredNotes;

  /// The active text search query filter.
  String get searchQuery => _searchQuery;

  /// The active tag filter, or `null` if all tags are shown.
  String? get activeTag => _activeTag;

  /// The current SSH sync state for the status indicator pill.
  SyncState get syncState => _syncState;

  /// Whether a database or sync operation is actively loading.
  bool get isLoading => _isLoading;

  /// Filtered notes that have been pinned by the user.
  List<StickyNote> get pinnedNotes =>
      _filteredNotes.where((StickyNote note) => note.isPinned).toList();

  /// Filtered notes that are not pinned.
  List<StickyNote> get unpinnedNotes =>
      _filteredNotes.where((StickyNote note) => !note.isPinned).toList();

  /// Unique, sorted list of all tags present across all notes.
  List<String> get allTags {
    final tags = <String>{};
    for (final note in _notes) {
      tags.addAll(note.tags);
    }
    final sorted = tags.toList()..sort();
    return sorted;
  }

  /// Whether any loaded note currently has a merge conflict requiring resolution.
  bool get hasConflicts => _notes.any(
        (StickyNote note) => note.syncStatus == SyncStatus.conflict,
      );

  /// Loads all notes from SQLite, applies active filters, and updates listeners.
  Future<void> loadNotes() async {
    _isLoading = true;
    notifyListeners();

    try {
      _notes = await _localDbService.getAllNotes();
      _applyFilters();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Updates the search filter query and recalculates filtered notes.
  void setSearchQuery(String query) {
    _searchQuery = query;
    _applyFilters();
    notifyListeners();
  }

  /// Sets the active tag filter and recalculates filtered notes.
  void setActiveTag(String? tag) {
    _activeTag = tag;
    _applyFilters();
    notifyListeners();
  }

  /// Toggles the pinned status of the note identified by [noteId].
  Future<void> togglePin(String noteId) async {
    final note = await _localDbService.getNoteById(noteId);
    if (note == null) return;

    final updated = note.copyWith(
      isPinned: !note.isPinned,
      updatedAt: DateTime.now(),
    );
    await _localDbService.updateNote(updated);
    await loadNotes();
  }

  /// Deletes a note by its [noteId] from both the database and local filesystem.
  Future<void> deleteNote(String noteId) async {
    final note = await _localDbService.getNoteById(noteId);
    if (note != null) {
      await _localDbService.deleteLocalFile(note.filename);
      await _localDbService.deleteBaseFile(note.filename);
      await _localDbService.deleteNote(noteId);
    } else {
      await _localDbService.deleteNote(noteId);
    }
    await loadNotes();
  }

  /// Toggles the checkbox at [lineIndex] within the note's Markdown content,
  /// saves the updated content to SQLite and local disk, and marks it pending sync.
  Future<void> toggleCheckbox(String noteId, int lineIndex) async {
    final note = await _localDbService.getNoteById(noteId);
    if (note == null) return;

    final updatedContent =
        MarkdownChecklistHelper.toggleCheckbox(note.content, lineIndex);
    if (updatedContent == note.content) return;

    final updatedNote = note.copyWith(
      content: updatedContent,
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pending,
    );

    await _localDbService.updateNote(updatedNote);
    await _localDbService.writeLocalFile(note.filename, updatedContent);
    await loadNotes();
  }

  /// Triggers an immediate bidirectional SSH sync transaction with the laptop.
  ///
  /// Updates [syncState] during and after sync, reloads notes, and returns [SyncResult].
  Future<SyncResult> syncNow() async {
    _syncState = SyncState.syncing;
    notifyListeners();

    final result = await _sshSyncService.syncAll();

    if (result.connectedProfile == null) {
      _syncState = SyncState.offline;
    } else if (result.hasConflicts) {
      _syncState = SyncState.conflict;
    } else {
      _syncState = SyncState.connected;
    }

    await loadNotes();

    // If any notes remain in conflict status, reflect in sync status pill
    if (hasConflicts && _syncState != SyncState.offline) {
      _syncState = SyncState.conflict;
      notifyListeners();
    }

    return result;
  }

  /// Filters notes matching the current search query and tag selection.
  void _applyFilters() {
    final query = _searchQuery.trim().toLowerCase();

    _filteredNotes = _notes.where((StickyNote note) {
      final matchesQuery = query.isEmpty ||
          note.title.toLowerCase().contains(query) ||
          note.content.toLowerCase().contains(query);

      final matchesTag = _activeTag == null ||
          _activeTag!.isEmpty ||
          note.tags.contains(_activeTag);

      return matchesQuery && matchesTag;
    }).toList();
  }
}
