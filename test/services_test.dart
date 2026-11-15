import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_notes_ssh/models/ssh_profile.dart';
import 'package:sticky_notes_ssh/models/sticky_note.dart';
import 'package:sticky_notes_ssh/services/background_sync_manager.dart';
import 'package:sticky_notes_ssh/services/ssh_sync_service.dart';

void main() {
  group('SyncResult Tests', () {
    test('empty constructor has default zeros and no changes', () {
      const result = SyncResult.empty();
      expect(result.pulled, 0);
      expect(result.pushed, 0);
      expect(result.autoMerged, 0);
      expect(result.conflicts, 0);
      expect(result.deleted, 0);
      expect(result.errors, isEmpty);
      expect(result.connectedProfile, isNull);
      expect(result.hasChanges, isFalse);
      expect(result.hasConflicts, isFalse);
      expect(result.hasErrors, isFalse);
      expect(result.summary, 'All notes up to date');
    });

    test('summary reflects pulled and pushed counts', () {
      const result = SyncResult(
        pulled: 1,
        pushed: 2,
        autoMerged: 0,
        conflicts: 0,
        deleted: 0,
        errors: <String>[],
        connectedProfile: 'Home LAN',
      );
      expect(result.hasChanges, isTrue);
      expect(result.hasConflicts, isFalse);
      expect(result.summary, 'Pulled 1, Pushed 2');
      expect(result.connectedProfile, 'Home LAN');
    });

    test('summary reflects conflicts and singular/plural formatting', () {
      const singleConflict = SyncResult(
        pulled: 0,
        pushed: 0,
        autoMerged: 1,
        conflicts: 1,
        deleted: 0,
        errors: <String>[],
      );
      expect(singleConflict.hasConflicts, isTrue);
      expect(singleConflict.summary, 'Auto-merged 1, 1 conflict');

      const multiConflict = SyncResult(
        pulled: 0,
        pushed: 0,
        autoMerged: 0,
        conflicts: 3,
        deleted: 1,
        errors: <String>[],
      );
      expect(multiConflict.hasConflicts, isTrue);
      expect(multiConflict.summary, 'Deleted 1, 3 conflicts');
    });

    test('summary shows error message when errors exist without changes', () {
      const errorResult = SyncResult(
        pulled: 0,
        pushed: 0,
        autoMerged: 0,
        conflicts: 0,
        deleted: 0,
        errors: <String>['Connection timeout'],
      );
      expect(errorResult.hasErrors, isTrue);
      expect(errorResult.summary, 'Sync completed with errors');
    });
  });

  group('BackgroundSyncManager Tests', () {
    test('has correct static task identifiers', () {
      expect(BackgroundSyncManager.taskName, 'com.sticky.backgroundSync');
      expect(BackgroundSyncManager.immediateTaskName, 'com.sticky.immediateSync');
    });

    test('enableAutoSync and disableAutoSync execute safely on non-mobile test runner', () async {
      await expectLater(BackgroundSyncManager.enableAutoSync(), completes);
      await expectLater(BackgroundSyncManager.disableAutoSync(), completes);
    });
  });

  group('SyncWorker Model Tests', () {
    test('SyncWorkerParams initializes with correct paths and profile', () {
      const profile = SshProfile(
        id: 'p1',
        name: 'Home LAN',
        host: '192.168.1.10',
        username: 'testuser',
        privateKeyId: 'k1',
      );
      const params = SyncWorkerParams(
        profile: profile,
        privateKeyPem: 'PEM_CONTENT',
        notesDirPath: '/notes',
        syncBaseDirPath: '/base',
        localNotes: <StickyNote>[],
      );

      expect(params.profile.name, 'Home LAN');
      expect(params.privateKeyPem, 'PEM_CONTENT');
      expect(params.notesDirPath, '/notes');
      expect(params.syncBaseDirPath, '/base');
      expect(params.localNotes, isEmpty);
    });

    test('SyncWorkerResult preserves syncResult and database operations', () {
      const syncResult = SyncResult(
        pulled: 2,
        pushed: 1,
        autoMerged: 0,
        conflicts: 0,
        deleted: 0,
        errors: <String>[],
        connectedProfile: 'Home LAN',
      );
      const workerResult = SyncWorkerResult(
        syncResult: syncResult,
        notesToInsert: <StickyNote>[],
        notesToUpdate: <StickyNote>[],
        noteIdsToDelete: <String>['id-1'],
        recentlyWrittenFiles: <String>['note1.md'],
      );

      expect(workerResult.syncResult.pulled, 2);
      expect(workerResult.syncResult.pushed, 1);
      expect(workerResult.noteIdsToDelete, contains('id-1'));
      expect(workerResult.recentlyWrittenFiles, contains('note1.md'));
    });
  });
}

