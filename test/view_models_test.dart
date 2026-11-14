import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_notes_ssh/models/ssh_profile.dart';
import 'package:sticky_notes_ssh/models/sticky_note.dart';
import 'package:sticky_notes_ssh/services/local_db_service.dart';
import 'package:sticky_notes_ssh/services/secure_storage_service.dart';
import 'package:sticky_notes_ssh/services/ssh_sync_service.dart';
import 'package:sticky_notes_ssh/view_models/editor_view_model.dart';
import 'package:sticky_notes_ssh/view_models/home_view_model.dart';
import 'package:sticky_notes_ssh/view_models/settings_view_model.dart';
import 'package:sticky_notes_ssh/widgets/sync_status_pill.dart';

class FakeLocalDbService implements LocalDbService {
  final Map<String, StickyNote> notes = <String, StickyNote>{};
  final Map<String, SshProfile> profiles = <String, SshProfile>{};
  final Map<String, String> localFiles = <String, String>{};
  final Map<String, String> baseFiles = <String, String>{};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<StickyNote>> getAllNotes() async {
    final list = notes.values.toList();
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  @override
  Future<StickyNote?> getNoteById(String id) async => notes[id];

  @override
  Future<StickyNote?> getNoteByFilename(String filename) async {
    for (final note in notes.values) {
      if (note.filename == filename) return note;
    }
    return null;
  }

  @override
  Future<int> insertNote(StickyNote note) async {
    notes[note.id] = note;
    return 1;
  }

  @override
  Future<int> updateNote(StickyNote note) async {
    notes[note.id] = note;
    return 1;
  }

  @override
  Future<int> deleteNote(String id) async {
    notes.remove(id);
    return 1;
  }

  @override
  Future<List<StickyNote>> getConflictNotes() async => notes.values
      .where((n) => n.syncStatus == SyncStatus.conflict)
      .toList();

  @override
  Future<File> writeLocalFile(String filename, String content) async {
    localFiles[filename] = content;
    return File(filename);
  }

  @override
  Future<void> deleteLocalFile(String filename) async {
    localFiles.remove(filename);
  }

  @override
  Future<void> deleteBaseFile(String filename) async {
    baseFiles.remove(filename);
  }

  @override
  Future<List<SshProfile>> getAllProfiles() async {
    final list = profiles.values.toList();
    list.sort((a, b) => a.priority.compareTo(b.priority));
    return list;
  }

  @override
  Future<SshProfile?> getProfileById(String id) async => profiles[id];

  @override
  Future<int> insertProfile(SshProfile profile) async {
    profiles[profile.id] = profile;
    return 1;
  }

  @override
  Future<int> updateProfile(SshProfile profile) async {
    profiles[profile.id] = profile;
    return 1;
  }

  @override
  Future<int> deleteProfile(String id) async {
    profiles.remove(id);
    return 1;
  }
}

class FakeSshSyncService implements SshSyncService {
  SyncResult nextSyncResult = const SyncResult(
    pulled: 1,
    pushed: 0,
    autoMerged: 0,
    conflicts: 0,
    deleted: 0,
    errors: <String>[],
    connectedProfile: 'Home LAN',
  );

  String nextTestResult = 'Connection successful!';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<SyncResult> syncAll() async => nextSyncResult;

  @override
  Future<String> testConnection(SshProfile profile) async => nextTestResult;
}

class FakeSecureStorageService implements SecureStorageService {
  final Map<String, String> keys = <String, String>{};
  bool autoSync = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> savePrivateKey(String profileId, String pemContent) async {
    keys[profileId] = pemContent;
  }

  @override
  Future<String?> getPrivateKey(String profileId) async => keys[profileId];

  @override
  Future<void> deletePrivateKey(String profileId) async {
    keys.remove(profileId);
  }

  @override
  Future<void> setAutoSyncEnabled(bool enabled) async {
    autoSync = enabled;
  }

  @override
  Future<bool> getAutoSyncEnabled() async => autoSync;
}

void main() {
  group('HomeViewModel', () {
    late FakeLocalDbService db;
    late FakeSshSyncService sync;
    late HomeViewModel vm;

    setUp(() {
      db = FakeLocalDbService();
      sync = FakeSshSyncService();
      vm = HomeViewModel(localDbService: db, sshSyncService: sync);
    });

    test('loads notes and sorts pinned and unpinned', () async {
      final now = DateTime.now();
      db.notes['1'] = StickyNote(
        id: '1',
        filename: 'note1.md',
        title: 'Work tasks',
        content: '# Work tasks\n- [ ] Task 1',
        tags: const <String>['work'],
        isPinned: true,
        createdAt: now,
        updatedAt: now,
      );
      db.notes['2'] = StickyNote(
        id: '2',
        filename: 'note2.md',
        title: 'Groceries',
        content: '# Groceries\nMilk',
        tags: const <String>['home'],
        isPinned: false,
        createdAt: now,
        updatedAt: now,
      );

      await vm.loadNotes();

      expect(vm.notes.length, 2);
      expect(vm.pinnedNotes.length, 1);
      expect(vm.pinnedNotes.first.id, '1');
      expect(vm.unpinnedNotes.length, 1);
      expect(vm.unpinnedNotes.first.id, '2');
      expect(vm.allTags, <String>['home', 'work']);
      expect(vm.hasConflicts, isFalse);
    });

    test('search and tag filtering', () async {
      final now = DateTime.now();
      db.notes['1'] = StickyNote(
        id: '1',
        filename: 'note1.md',
        title: 'Work tasks',
        content: 'Fix the bug',
        tags: const <String>['dev'],
        createdAt: now,
        updatedAt: now,
      );
      db.notes['2'] = StickyNote(
        id: '2',
        filename: 'note2.md',
        title: 'Personal idea',
        content: 'Buy guitar',
        tags: const <String>['music'],
        createdAt: now,
        updatedAt: now,
      );

      await vm.loadNotes();
      expect(vm.filteredNotes.length, 2);

      vm.setSearchQuery('guitar');
      expect(vm.filteredNotes.length, 1);
      expect(vm.filteredNotes.first.id, '2');

      vm.setSearchQuery('');
      vm.setActiveTag('dev');
      expect(vm.filteredNotes.length, 1);
      expect(vm.filteredNotes.first.id, '1');

      vm.setActiveTag(null);
      expect(vm.filteredNotes.length, 2);
    });

    test('togglePin updates note and reloads', () async {
      final now = DateTime.now();
      db.notes['1'] = StickyNote(
        id: '1',
        filename: 'note1.md',
        title: 'Title',
        content: 'Body',
        isPinned: false,
        createdAt: now,
        updatedAt: now,
      );

      await vm.loadNotes();
      expect(vm.pinnedNotes, isEmpty);

      await vm.togglePin('1');
      expect(vm.pinnedNotes.length, 1);
      expect(db.notes['1']!.isPinned, isTrue);
    });

    test('deleteNote removes from db and file storage', () async {
      final now = DateTime.now();
      db.notes['1'] = StickyNote(
        id: '1',
        filename: 'note1.md',
        title: 'Title',
        content: 'Body',
        createdAt: now,
        updatedAt: now,
      );
      db.localFiles['note1.md'] = 'Body';

      await vm.loadNotes();
      expect(vm.notes.length, 1);

      await vm.deleteNote('1');
      expect(vm.notes, isEmpty);
      expect(db.notes['1'], isNull);
      expect(db.localFiles['note1.md'], isNull);
    });

    test('toggleCheckbox toggles checkbox item', () async {
      final now = DateTime.now();
      db.notes['1'] = StickyNote(
        id: '1',
        filename: 'note1.md',
        title: 'Todo',
        content: '# Todo\n- [ ] Buy milk',
        createdAt: now,
        updatedAt: now,
      );

      await vm.loadNotes();
      await vm.toggleCheckbox('1', 1);

      expect(db.notes['1']!.content, '# Todo\n- [x] Buy milk');
      expect(db.notes['1']!.syncStatus, SyncStatus.pending);
      expect(db.localFiles['note1.md'], '# Todo\n- [x] Buy milk');
    });

    test('syncNow runs sync and updates syncState', () async {
      sync.nextSyncResult = const SyncResult(
        pulled: 1,
        pushed: 0,
        autoMerged: 0,
        conflicts: 0,
        deleted: 0,
        errors: <String>[],
        connectedProfile: 'Home LAN',
      );

      final result = await vm.syncNow();
      expect(result.pulled, 1);
      expect(vm.syncState, SyncState.connected);

      // Offline test
      sync.nextSyncResult = const SyncResult.empty();
      await vm.syncNow();
      expect(vm.syncState, SyncState.offline);
    });
  });

  group('EditorViewModel', () {
    late FakeLocalDbService db;
    late EditorViewModel vm;

    setUp(() {
      db = FakeLocalDbService();
    });

    tearDown(() {
      vm.dispose();
    });

    test('loads existing note', () async {
      final now = DateTime.now();
      db.notes['note-1'] = StickyNote(
        id: 'note-1',
        filename: 'grocery.md',
        title: 'Grocery',
        content: '# Grocery\n- [ ] Apples',
        colorIndex: 2,
        isPinned: true,
        tags: const <String>['shopping'],
        createdAt: now,
        updatedAt: now,
      );

      vm = EditorViewModel(localDbService: db, noteId: 'note-1');
      await vm.loadNote();

      expect(vm.contentController.text, '# Grocery\n- [ ] Apples');
      expect(vm.colorIndex, 2);
      expect(vm.isPinned, isTrue);
      expect(vm.tags, <String>['shopping']);
      expect(vm.wordCount, 6);
      expect(vm.charCount, 22);
      expect(vm.isDirty, isFalse);
    });

    test('initializes new note and saves', () async {
      vm = EditorViewModel(localDbService: db, noteId: null);
      await vm.loadNote();

      expect(vm.note, isNull);
      vm.contentController.text = '# Project Plan\nThis is the plan';
      vm.setColor(3);
      vm.togglePin();
      vm.updateTags(<String>['work', 'plan']);

      expect(vm.isDirty, isTrue);
      await vm.saveNote();

      expect(vm.isDirty, isFalse);
      expect(vm.note, isNotNull);
      expect(vm.note!.title, 'Project Plan');
      expect(vm.note!.filename, 'project-plan.md');
      expect(vm.note!.colorIndex, 3);
      expect(vm.note!.isPinned, isTrue);
      expect(vm.note!.syncStatus, SyncStatus.pending);
      expect(db.notes.containsKey(vm.note!.id), isTrue);
      expect(db.localFiles[vm.note!.filename], '# Project Plan\nThis is the plan');
    });

    test('switch mode', () {
      vm = EditorViewModel(localDbService: db, noteId: null);
      expect(vm.mode, EditorMode.edit);
      vm.setMode(EditorMode.split);
      expect(vm.mode, EditorMode.split);
      vm.setMode(EditorMode.preview);
      expect(vm.mode, EditorMode.preview);
    });
  });

  group('SettingsViewModel', () {
    late FakeLocalDbService db;
    late FakeSecureStorageService storage;
    late FakeSshSyncService sync;
    late SettingsViewModel vm;

    setUp(() {
      db = FakeLocalDbService();
      storage = FakeSecureStorageService();
      sync = FakeSshSyncService();
      vm = SettingsViewModel(
        localDbService: db,
        secureStorageService: storage,
        sshSyncService: sync,
      );
    });

    test('load, add, update, and delete profiles', () async {
      await vm.loadProfiles();
      expect(vm.profiles, isEmpty);

      const profile = SshProfile(
        id: 'p1',
        name: 'Laptop Home',
        host: '192.168.1.50',
        username: 'user',
        priority: 0,
        privateKeyId: 'p1',
      );

      await vm.addProfile(profile, '-----BEGIN PRIVATE KEY-----');
      expect(vm.profiles.length, 1);
      expect(storage.keys['p1'], '-----BEGIN PRIVATE KEY-----');

      final updated = profile.copyWith(name: 'Laptop Work');
      await vm.updateProfile(updated);
      expect(vm.profiles.first.name, 'Laptop Work');

      await vm.deleteProfile('p1');
      expect(vm.profiles, isEmpty);
      expect(storage.keys['p1'], isNull);
    });

    test('reorder profiles updates priority values', () async {
      db.profiles['1'] = const SshProfile(
        id: '1',
        name: 'First',
        host: 'h1',
        username: 'u',
        priority: 0,
        privateKeyId: 'k1',
      );
      db.profiles['2'] = const SshProfile(
        id: '2',
        name: 'Second',
        host: 'h2',
        username: 'u',
        priority: 1,
        privateKeyId: 'k2',
      );

      await vm.loadProfiles();
      expect(vm.profiles[0].id, '1');
      expect(vm.profiles[1].id, '2');

      await vm.reorderProfiles(0, 2);
      expect(vm.profiles[0].id, '2');
      expect(vm.profiles[1].id, '1');
      expect(db.profiles['2']!.priority, 0);
      expect(db.profiles['1']!.priority, 1);
    });

    test('testConnection and toggleAutoSync', () async {
      const profile = SshProfile(
        id: '1',
        name: 'Test',
        host: 'h',
        username: 'u',
        privateKeyId: 'k',
      );

      await vm.testConnection(profile);
      expect(vm.testResult, 'Connection successful!');
      expect(vm.isTesting, isFalse);

      await vm.toggleAutoSync(true);
      expect(vm.autoSyncEnabled, isTrue);
      expect(await storage.getAutoSyncEnabled(), isTrue);
    });
  });
}
