import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_notes_ssh/models/ssh_profile.dart';
import 'package:sticky_notes_ssh/models/sticky_note.dart';
import 'package:sticky_notes_ssh/services/local_db_service.dart';
import 'package:sticky_notes_ssh/services/secure_storage_service.dart';
import 'package:sticky_notes_ssh/services/ssh_sync_service.dart';
import 'package:sticky_notes_ssh/view_models/home_view_model.dart';
import 'package:sticky_notes_ssh/view_models/settings_view_model.dart';
import 'package:sticky_notes_ssh/widgets/sync_status_pill.dart';

class MockLocalDbService implements LocalDbService {
  final Map<String, StickyNote> notes = {};
  final Map<String, SshProfile> profiles = {};
  final Map<String, String> localFiles = {};
  final Map<String, String> baseFiles = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<StickyNote>> getAllNotes({String? profileId}) async {
    var list = notes.values.toList();
    if (profileId != null && profileId.isNotEmpty) {
      list = list.where((n) => n.profileId == profileId).toList();
    }
    return list;
  }

  @override
  Future<StickyNote?> getNoteById(String id, {String? profileId}) async => notes[id];

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
  Future<File> writeLocalFile(
    String filename,
    String content, {
    String? profileId,
  }) async {
    final key = profileId != null ? '$profileId/$filename' : filename;
    localFiles[key] = content;
    return File(filename);
  }

  @override
  Future<void> deleteLocalFile(String filename, {String? profileId}) async {
    final key = profileId != null ? '$profileId/$filename' : filename;
    localFiles.remove(key);
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

  @override
  Future<int> deleteNotesByProfile(String profileId) async {
    notes.removeWhere((id, note) => note.profileId == profileId);
    return 1;
  }
}

class MockSecureStorageService implements SecureStorageService {
  String? _activeProfileId;
  bool _autoSync = false;
  final Map<String, String> _keys = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> saveActiveProfileId(String profileId) async {
    _activeProfileId = profileId;
  }

  @override
  Future<String?> getActiveProfileId() async => _activeProfileId;

  @override
  Future<void> deleteActiveProfileId() async {
    _activeProfileId = null;
  }

  @override
  Future<bool> getAutoSyncEnabled() async => _autoSync;

  @override
  Future<void> setAutoSyncEnabled(bool enabled) async {
    _autoSync = enabled;
  }

  @override
  Future<String?> getPrivateKey(String profileId) async => _keys[profileId];

  @override
  Future<void> savePrivateKey(String profileId, String pem) async {
    _keys[profileId] = pem;
  }

  @override
  Future<String?> getHomeBackground() async => null;

  @override
  Future<bool> getGridViewMode() async => true;
}

class MockSshSyncService implements SshSyncService {
  SshProfile? reachableProfile;
  SyncResult syncResult = const SyncResult.empty();
  String? lastProbedProfileId;
  bool isWatching = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<SshProfile?> findReachableProfile({String? profileId}) async {
    lastProbedProfileId = profileId;
    return reachableProfile;
  }

  @override
  Future<SyncResult> syncAll({String? profileId}) async {
    lastProbedProfileId = profileId;
    return syncResult;
  }

  @override
  bool get isWatchingRemote => isWatching;

  @override
  void stopRemoteFileWatcher() {
    isWatching = false;
  }

  @override
  Future<void> startRemoteFileWatcher({required void Function() onRemoteChange}) async {
    isWatching = true;
  }

  @override
  Future<SyncResult> initializeDirectoryAndSync(SshProfile profile) async {
    return const SyncResult.empty();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SSH Profile Multi-Location & Compartment Tests', () {
    test('SshProfile allRemotePaths parses and combines remoteDir and remotePaths', () {
      const profile = SshProfile(
        id: 'laptop-1',
        name: 'Work Laptop',
        host: '192.168.1.50',
        remoteDir: '~/sticky-notes',
        remotePaths: <String>['~/sticky-notes', '~/projects/docs', '~/todo.md'],
        username: 'user',
        privateKeyId: 'k1',
      );

      expect(profile.allRemotePaths, hasLength(3));
      expect(profile.allRemotePaths, contains('~/sticky-notes'));
      expect(profile.allRemotePaths, contains('~/projects/docs'));
      expect(profile.allRemotePaths, contains('~/todo.md'));
    });

    test('SshProfile allRemotePaths defaults to remoteDir if remotePaths is empty', () {
      const profile = SshProfile(
        id: 'laptop-2',
        name: 'Personal Laptop',
        host: '10.0.0.5',
        remoteDir: '/var/notes',
        username: 'user',
        privateKeyId: 'k2',
      );

      expect(profile.allRemotePaths, equals(<String>['/var/notes']));
    });

    test('StickyNote serializes and deserializes profileId and remotePath correctly', () {
      final note = StickyNote(
        id: 'note-100',
        profileId: 'profile-xyz',
        filename: 'meeting.md',
        title: 'Meeting Notes',
        content: '# Meeting\nDiscuss architecture',
        remotePath: '~/projects/docs',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 2),
      );

      final map = note.toMap();
      expect(map['profileId'], 'profile-xyz');
      expect(map['remotePath'], '~/projects/docs');

      final fromMap = StickyNote.fromMap(map);
      expect(fromMap.profileId, 'profile-xyz');
      expect(fromMap.remotePath, '~/projects/docs');
      expect(fromMap.filename, 'meeting.md');
      expect(fromMap.title, 'Meeting Notes');
    });
  });

  group('HomeViewModel Profile Isolation & Offline Access', () {
    late MockLocalDbService db;
    late MockSecureStorageService storage;
    late MockSshSyncService sync;
    late HomeViewModel vm;

    final now = DateTime.now();
    const profileHome = SshProfile(
      id: 'prof-home',
      name: 'Home Desktop',
      host: '192.168.1.10',
      username: 'user',
      privateKeyId: 'k-home',
    );
    const profileWork = SshProfile(
      id: 'prof-work',
      name: 'Work Laptop',
      host: '10.10.10.20',
      username: 'workuser',
      privateKeyId: 'k-work',
    );

    setUp(() {
      db = MockLocalDbService();
      storage = MockSecureStorageService();
      sync = MockSshSyncService();

      db.profiles['prof-home'] = profileHome;
      db.profiles['prof-work'] = profileWork;

      // Add notes belonging to home profile
      db.notes['note-h1'] = StickyNote(
        id: 'note-h1',
        profileId: 'prof-home',
        filename: 'groceries.md',
        title: 'Groceries',
        content: '# Groceries\n- [ ] Milk',
        createdAt: now,
        updatedAt: now,
      );

      // Add notes belonging to work profile
      db.notes['note-w1'] = StickyNote(
        id: 'note-w1',
        profileId: 'prof-work',
        filename: 'sprint.md',
        title: 'Sprint Planning',
        content: '# Sprint\n- [ ] Task 1',
        createdAt: now,
        updatedAt: now,
      );

      vm = HomeViewModel(
        localDbService: db,
        secureStorageService: storage,
        sshSyncService: sync,
      );
    });

    tearDown(() {
      vm.dispose();
    });

    test('loadNotes loads only the active profile compartment notes', () async {
      await storage.saveActiveProfileId('prof-home');
      await vm.loadNotes();

      expect(vm.activeProfileId, 'prof-home');
      expect(vm.activeProfile?.name, 'Home Desktop');
      expect(vm.notes.length, 1);
      expect(vm.notes.first.id, 'note-h1');
      expect(vm.notes.first.title, 'Groceries');
    });

    test('switchActiveProfile switches compartment and loads other notes offline', () async {
      await storage.saveActiveProfileId('prof-home');
      await vm.loadNotes();
      expect(vm.notes.length, 1);
      expect(vm.notes.first.id, 'note-h1');

      // Switch to work profile without network connection
      await vm.switchActiveProfile('prof-work');

      expect(vm.activeProfileId, 'prof-work');
      expect(vm.activeProfile?.name, 'Work Laptop');
      expect(vm.notes.length, 1);
      expect(vm.notes.first.id, 'note-w1');
      expect(vm.notes.first.title, 'Sprint Planning');
      // Home notes must not be deleted or shown in work compartment
      expect(db.notes.containsKey('note-h1'), isTrue);
      expect(db.notes.containsKey('note-w1'), isTrue);
    });

    test('strict single machine probe: does not auto-jump to other profiles when offline', () async {
      await storage.saveActiveProfileId('prof-home');
      await vm.loadNotes();

      // Home profile is unreachable, but work profile would be reachable
      sync.reachableProfile = null;
      storage._autoSync = true;

      final result = await vm.checkAndAutoSync(force: true);
      expect(result, isNull);
      expect(vm.syncState, SyncState.offline);
      // Confirms active profile remains strictly 'prof-home'
      expect(vm.activeProfileId, 'prof-home');
    });

    test('syncNow passes active profileId to syncAll', () async {
      await storage.saveActiveProfileId('prof-work');
      await vm.loadNotes();

      sync.syncResult = const SyncResult(
        pulled: 2,
        pushed: 0,
        autoMerged: 0,
        conflicts: 0,
        deleted: 0,
        errors: <String>[],
        connectedProfile: 'Work Laptop',
      );

      final result = await vm.syncNow();
      expect(result.pulled, 2);
      expect(sync.lastProbedProfileId, 'prof-work');
    });
  });

  group('SettingsViewModel Multi-Location & Compartment Management', () {
    late MockLocalDbService db;
    late MockSecureStorageService storage;
    late MockSshSyncService sync;
    late SettingsViewModel vm;

    const profile = SshProfile(
      id: 'prof-test',
      name: 'Linux Server',
      host: '192.168.1.15',
      remoteDir: '~/sticky-notes',
      remotePaths: <String>['~/sticky-notes'],
      username: 'admin',
      privateKeyId: 'k-server',
    );

    setUp(() {
      db = MockLocalDbService();
      storage = MockSecureStorageService();
      sync = MockSshSyncService();

      db.profiles['prof-test'] = profile;

      final now = DateTime.now();
      db.notes['note-s1'] = StickyNote(
        id: 'note-s1',
        profileId: 'prof-test',
        filename: 'server-log.md',
        title: 'Server Log',
        content: '# Logs',
        createdAt: now,
        updatedAt: now,
      );

      vm = SettingsViewModel(
        localDbService: db,
        secureStorageService: storage,
        sshSyncService: sync,
      );
    });

    tearDown(() {
      vm.dispose();
    });

    test('loadProfiles sets activeProfile and loads syncedNotes for compartment', () async {
      await vm.loadProfiles();

      expect(vm.profiles.length, 1);
      expect(vm.activeProfile?.id, 'prof-test');
      expect(vm.syncedNotes.length, 1);
      expect(vm.syncedNotes.first.filename, 'server-log.md');
    });

    test('addRemotePath adds location to active profile', () async {
      await vm.loadProfiles();
      expect(vm.activeProfile!.allRemotePaths, equals(<String>['~/sticky-notes']));

      await vm.addRemotePath('prof-test', '~/documents/meeting-notes');

      expect(vm.activeProfile!.allRemotePaths, hasLength(2));
      expect(vm.activeProfile!.allRemotePaths, contains('~/sticky-notes'));
      expect(vm.activeProfile!.allRemotePaths, contains('~/documents/meeting-notes'));
    });

    test('removeRemotePath removes location from active profile', () async {
      await vm.loadProfiles();
      await vm.addRemotePath('prof-test', '~/extra-dir');
      expect(vm.activeProfile!.allRemotePaths, hasLength(2));

      await vm.removeRemotePath('prof-test', '~/extra-dir');
      expect(vm.activeProfile!.allRemotePaths, equals(<String>['~/sticky-notes']));
    });
  });
}
