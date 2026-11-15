import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sticky_notes_ssh/models/home_background.dart';
import 'package:sticky_notes_ssh/models/ssh_profile.dart';
import 'package:sticky_notes_ssh/models/sticky_note.dart';
import 'package:sticky_notes_ssh/services/local_db_service.dart';
import 'package:sticky_notes_ssh/services/secure_storage_service.dart';
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
    SecureStorageService? secureStorageService,
    Connectivity? connectivity,
  })  : _localDbService = localDbService ?? LocalDbService(),
        _sshSyncService = sshSyncService ?? SshSyncService(),
        _secureStorageService = secureStorageService ?? SecureStorageService(),
        _connectivity = connectivity ?? Connectivity();

  final LocalDbService _localDbService;
  final SshSyncService _sshSyncService;
  final SecureStorageService _secureStorageService;
  final Connectivity _connectivity;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _connectivityDebounceTimer;

  List<StickyNote> _notes = const <StickyNote>[];
  List<StickyNote> _filteredNotes = const <StickyNote>[];
  String _searchQuery = '';
  String? _activeTag;
  SyncState _syncState = SyncState.offline;
  bool _isLoading = false;
  HomeBackground _background = const HomeBackground.defaultTheme();
  bool _isGridView = true;
  String? _activeProfileId;
  String? _activeRemotePath;
  Set<String> _selectedLocationKeys = <String>{};
  SshProfile? _activeProfile;
  List<SshProfile> _availableProfiles = const <SshProfile>[];

  /// The active home screen background configuration.
  HomeBackground get background => _background;

  /// Whether the notes are displayed in 2-column grid or 1-column markdown reader.
  bool get isGridView => _isGridView;

  /// All sticky notes loaded from the local database for the active profile.
  List<StickyNote> get notes => _notes;

  /// Currently active profile ID.
  String? get activeProfileId => _activeProfileId;

  /// Currently active remote directory or file location filter.
  String? get activeRemotePath => _activeRemotePath;

  /// Set of currently selected location keys formatted as '$profileId::$locationPath'.
  Set<String> get selectedLocationKeys => Set.unmodifiable(_selectedLocationKeys);

  /// Number of currently selected directory/file compartments.
  int get selectedLocationsCount => _selectedLocationKeys.length;

  /// Whether the directory or file at [locationPath] for [profileId] is currently selected.
  bool isLocationSelected(String profileId, String locationPath) =>
      _selectedLocationKeys.contains('$profileId::$locationPath');

  /// The currently active SSH machine profile, or `null` if none configured.
  SshProfile? get activeProfile => _activeProfile;

  /// List of all configured SSH machine profiles.
  List<SshProfile> get availableProfiles => _availableProfiles;

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

  /// Loads all notes from SQLite for the active profile, applies active filters, and updates listeners.
  Future<void> loadNotes() async {
    _isLoading = true;
    notifyListeners();

    try {
      _availableProfiles = await _localDbService.getAllProfiles();
      _activeProfileId = await _secureStorageService.getActiveProfileId();

      if (_activeProfileId == null ||
          !_availableProfiles.any((p) => p.id == _activeProfileId)) {
        if (_availableProfiles.isNotEmpty) {
          _activeProfileId = _availableProfiles.first.id;
          await _secureStorageService.saveActiveProfileId(_activeProfileId!);
        } else {
          _activeProfileId = null;
        }
      }

      _activeProfile = _availableProfiles
          .where((p) => p.id == _activeProfileId)
          .firstOrNull;

      _activeRemotePath = await _secureStorageService.getActiveLocation();
      final savedKeys = await _secureStorageService.getSelectedLocationKeys();

      if (_activeProfile != null) {
        final paths = _activeProfile!.allRemotePaths;
        if (_activeRemotePath == null || !paths.contains(_activeRemotePath)) {
          _activeRemotePath = paths.firstOrNull;
          await _secureStorageService.saveActiveLocation(_activeRemotePath);
        }
      } else {
        _activeRemotePath = null;
      }

      if (savedKeys != null) {
        _selectedLocationKeys = savedKeys;
      } else if (_activeProfileId != null && _activeRemotePath != null) {
        _selectedLocationKeys = {'$_activeProfileId::$_activeRemotePath'};
        await _secureStorageService.saveSelectedLocationKeys(_selectedLocationKeys);
      } else {
        _selectedLocationKeys = <String>{};
      }

      final selectedProfileIds = <String>{};
      for (final key in _selectedLocationKeys) {
        final parts = key.split('::');
        if (parts.isNotEmpty && parts[0].isNotEmpty) {
          selectedProfileIds.add(parts[0]);
        }
      }

      final loadedNotes = <StickyNote>[];
      if (_availableProfiles.isEmpty) {
        loadedNotes.addAll(await _localDbService.getAllNotes());
      } else {
        for (final pid in selectedProfileIds) {
          loadedNotes.addAll(await _localDbService.getAllNotes(profileId: pid));
        }
      }
      _notes = loadedNotes;
      _applyFilters();
      await loadPreferences();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Switches the active machine profile and immediately loads its isolated compartment notes offline.
  Future<void> switchActiveProfile(String profileId) async {
    final profile = _availableProfiles.where((p) => p.id == profileId).firstOrNull;
    final defaultPath = profile?.allRemotePaths.firstOrNull;
    await switchActiveProfileAndLocation(profileId, defaultPath);
  }

  /// Switches the active machine profile and directory location, immediately loading
  /// that isolated compartment's offline notes without requiring connection to other profiles.
  Future<void> switchActiveProfileAndLocation(String profileId, String? remotePath) async {
    _activeProfileId = profileId;
    _activeRemotePath = remotePath;
    if (remotePath != null) {
      _selectedLocationKeys = {'$profileId::$remotePath'};
      await _secureStorageService.saveSelectedLocationKeys(_selectedLocationKeys);
    }
    await _secureStorageService.saveActiveProfileId(profileId);
    await _secureStorageService.saveActiveLocation(remotePath);

    _activeProfile = _availableProfiles.where((p) => p.id == profileId).firstOrNull;
    _sshSyncService.stopRemoteFileWatcher();
    _syncState = SyncState.offline;
    notifyListeners();
    await loadNotes();
    unawaited(checkAndAutoSync());
  }

  /// Toggles selection of a specific directory or file compartment for [profileId].
  Future<void> toggleLocationSelection(String profileId, String locationPath) async {
    final key = '$profileId::$locationPath';
    final updated = Set<String>.from(_selectedLocationKeys);
    if (updated.contains(key)) {
      updated.remove(key);
      if (updated.isEmpty) {
        _activeProfileId = profileId;
        _activeRemotePath = locationPath;
      } else {
        final firstKey = updated.first;
        final parts = firstKey.split('::');
        if (parts.length >= 2) {
          _activeProfileId = parts[0];
          _activeRemotePath = parts[1];
        }
      }
    } else {
      updated.add(key);
      _activeProfileId = profileId;
      _activeRemotePath = locationPath;
    }

    _selectedLocationKeys = updated;
    await _secureStorageService.saveSelectedLocationKeys(_selectedLocationKeys);
    if (_activeProfileId != null) {
      await _secureStorageService.saveActiveProfileId(_activeProfileId!);
    }
    await _secureStorageService.saveActiveLocation(_activeRemotePath);
    await loadNotes();
  }

  /// Selects all available directories and files across all configured machine profiles.
  Future<void> selectAllLocations() async {
    final allKeys = <String>{};
    for (final p in _availableProfiles) {
      for (final loc in p.allRemotePaths) {
        allKeys.add('${p.id}::$loc');
      }
    }
    _selectedLocationKeys = allKeys;
    await _secureStorageService.saveSelectedLocationKeys(_selectedLocationKeys);
    await loadNotes();
  }

  /// Clears all location selections.
  Future<void> clearLocationSelection() async {
    _selectedLocationKeys = <String>{};
    await _secureStorageService.saveSelectedLocationKeys(_selectedLocationKeys);
    await loadNotes();
  }

  /// Loads saved background and view mode preferences from storage.
  Future<void> loadPreferences() async {
    try {
      final bgJson = await _secureStorageService.getHomeBackground();
      if (bgJson != null && bgJson.isNotEmpty) {
        _background = HomeBackground.fromJson(bgJson);
      }
      _isGridView = await _secureStorageService.getGridViewMode();
      notifyListeners();
    } catch (_) {}
  }

  /// Sets a new [HomeBackground] and persists it to storage.
  Future<void> setBackground(HomeBackground newBg) async {
    _background = newBg;
    notifyListeners();
    await _secureStorageService.saveHomeBackground(newBg.toJson());
  }

  /// Resets the background back to default theme.
  Future<void> resetBackground() async {
    _background = const HomeBackground.defaultTheme();
    notifyListeners();
    await _secureStorageService.deleteHomeBackground();
  }

  /// Launches the gallery picker, saves the chosen image locally, and updates [background].
  Future<void> pickAndSetGalleryImage({ImagePicker? picker}) async {
    final imagePicker = picker ?? ImagePicker();
    final pickedFile = await imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (pickedFile == null) return;

    final appDocDir = await getApplicationDocumentsDirectory();
    final bgDir = Directory(p.join(appDocDir.path, 'backgrounds'));
    if (!await bgDir.exists()) {
      await bgDir.create(recursive: true);
    }

    final ext = p.extension(pickedFile.path).isNotEmpty
        ? p.extension(pickedFile.path)
        : '.jpg';
    final savedPath = p.join(
      bgDir.path,
      'home_bg_${DateTime.now().millisecondsSinceEpoch}$ext',
    );

    final savedFile = await File(pickedFile.path).copy(savedPath);
    await setBackground(
      HomeBackground.image(savedFile.path, overlayOpacity: 0.15),
    );
  }

  /// Toggles between 2-column Grid View and 1-column Full Markdown Reader view.
  Future<void> toggleViewMode() async {
    _isGridView = !_isGridView;
    notifyListeners();
    await _secureStorageService.setGridViewMode(_isGridView);
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
  ///
  /// Preserves the base snapshot file until the next sync so the deletion
  /// propagates cleanly to the remote laptop instead of re-downloading.
  Future<void> deleteNote(String noteId) async {
    final note = await _localDbService.getNoteById(noteId);
    if (note != null) {
      await _localDbService.deleteLocalFile(
        note.filename,
        profileId: note.profileId,
      );
      await _localDbService.deleteNote(noteId);
    } else {
      await _localDbService.deleteNote(noteId);
    }
    await loadNotes();
    checkAndAutoSync();
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
    await _localDbService.writeLocalFile(
      note.filename,
      updatedContent,
      profileId: note.profileId,
    );
    await loadNotes();
    checkAndAutoSync();
  }

  /// Starts listening to network connectivity events and auto-syncs when online.
  void initConnectivityListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((results) {
      final isConnected = results.any((r) => r != ConnectivityResult.none);
      if (isConnected) {
        _connectivityDebounceTimer?.cancel();
        _connectivityDebounceTimer =
            Timer(const Duration(milliseconds: 1500), () {
          checkAndAutoSync();
        });
      }
    });
  }

  /// Performs an automatic background probe and sync if auto-sync is enabled.
  ///
  /// Operates event-driven upon editor close, checkbox toggling, note deletion,
  /// or network connectivity change (like inotifywait).
  Future<SyncResult?> checkAndAutoSync({bool force = false}) async {
    final isAutoSync =
        force || await _secureStorageService.getAutoSyncEnabled();
    if (!isAutoSync) {
      return null;
    }

    if (_syncState == SyncState.syncing) {
      return null;
    }

    try {
      final reachable = await _sshSyncService.findReachableProfile();
      if (reachable == null) {
        if (_syncState != SyncState.offline) {
          _syncState = SyncState.offline;
          notifyListeners();
        }
        _sshSyncService.stopRemoteFileWatcher();
        return null;
      }

      final result = await syncNow();

      if (!_sshSyncService.isWatchingRemote) {
        _sshSyncService.startRemoteFileWatcher(
          onRemoteChange: () => syncNow(),
        );
      }

      return result;
    } catch (_) {
      return null;
    }
  }

  bool _pendingRemoteSync = false;

  /// Triggers an immediate bidirectional SSH sync transaction with the laptop.
  ///
  /// Updates [syncState] during and after sync, reloads notes, and returns [SyncResult].
  Future<SyncResult> syncNow({String? profileId}) async {
    if (_syncState == SyncState.syncing) {
      _pendingRemoteSync = true;
      return const SyncResult.empty();
    }

    _syncState = SyncState.syncing;
    notifyListeners();

    final result = await _sshSyncService.syncAll(
      profileId: profileId ?? _activeProfileId,
    );

    if (result.connectedProfile == null) {
      _syncState = SyncState.offline;
      _sshSyncService.stopRemoteFileWatcher();
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

    // Keep live remote inotifywait watcher active while connected
    if (_syncState != SyncState.offline && !_sshSyncService.isWatchingRemote) {
      _sshSyncService.startRemoteFileWatcher(
        onRemoteChange: () => syncNow(),
      );
    }

    if (_pendingRemoteSync && _syncState != SyncState.offline) {
      _pendingRemoteSync = false;
      unawaited(syncNow());
    }

    return result;
  }

  /// Filters notes matching the current search query, tag selection, and active directory location.
  void _applyFilters() {
    final query = _searchQuery.trim().toLowerCase();

    _filteredNotes = _notes.where((StickyNote note) {
      final matchesQuery = query.isEmpty ||
          note.title.toLowerCase().contains(query) ||
          note.content.toLowerCase().contains(query);

      final matchesTag = _activeTag == null ||
          _activeTag!.isEmpty ||
          note.tags.contains(_activeTag);

      final matchesLocation = _noteMatchesLocationFilters(note);

      return matchesQuery && matchesTag && matchesLocation;
    }).toList();
  }

  /// Verifies whether [note] matches the selected machine and directory filters.
  bool _noteMatchesLocationFilters(StickyNote note) {
    if (_availableProfiles.isEmpty) {
      return true;
    }

    if (_selectedLocationKeys.isEmpty) {
      return false;
    }

    for (final key in _selectedLocationKeys) {
      final sepIndex = key.indexOf('::');
      if (sepIndex == -1) continue;
      final profileId = key.substring(0, sepIndex);
      final locationPath = key.substring(sepIndex + 2);

      if (_noteMatchesPath(note, profileId, locationPath)) {
        return true;
      }
    }

    return false;
  }

  /// Verifies whether [note] matches [locationPath] on [profileId].
  bool _noteMatchesPath(StickyNote note, String? profileId, String locationPath) {
    final noteProfileId = note.profileId.isNotEmpty ? note.profileId : _activeProfileId;
    if (profileId != null &&
        profileId.isNotEmpty &&
        noteProfileId != null &&
        noteProfileId.isNotEmpty &&
        noteProfileId != profileId) {
      return false;
    }

    final loc = locationPath.trim();
    if (note.remotePath == null || note.remotePath!.isEmpty) {
      final profile = _availableProfiles.where((p) => p.id == profileId).firstOrNull;
      if (profile != null && profile.allRemotePaths.isNotEmpty) {
        return loc == profile.allRemotePaths.first;
      }
      return true;
    }

    final notePath = note.remotePath!.trim();
    if (notePath == loc) return true;

    final normLoc = loc.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
    final normNote = notePath.replaceAll('\\', '/');

    if (normNote == normLoc) return true;
    if (normNote.startsWith('$normLoc/')) return true;

    final locBase = p.basename(normLoc);
    final noteDir = p.dirname(normNote);
    final noteDirBase = p.basename(noteDir);
    if (locBase.isNotEmpty && noteDirBase == locBase) return true;

    if (p.basename(normNote) == p.basename(normLoc)) return true;

    return false;
  }

  /// Stops the active remote SSH inotifywait watcher.
  void stopRemoteWatcher() {
    _sshSyncService.stopRemoteFileWatcher();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivityDebounceTimer?.cancel();
    _sshSyncService.stopRemoteFileWatcher();
    super.dispose();
  }
}
