import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_notes_ssh/models/ssh_profile.dart';
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

  group('GitLogEntry Tests', () {
    test('creates GitLogEntry with required properties', () {
      final now = DateTime.now();
      final entry = GitLogEntry(
        hash: 'c3f4e5a',
        date: now,
        message: 'Updated shopping list',
      );

      expect(entry.hash, 'c3f4e5a');
      expect(entry.date, now);
      expect(entry.message, 'Updated shopping list');
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

  group('SshProfile Pairing Tests', () {
    test('parses valid stickyglow URI from sticky pair', () {
      const code =
          'stickyglow://pair?name=LinuxLaptop&host=192.168.1.20&port=22&username=shahnebaj&remoteDir=/home/shahnebaj/Desktop/Sticky';
      final profile = SshProfile.parsePairingCode(code);
      expect(profile, isNotNull);
      expect(profile!.name, 'LinuxLaptop');
      expect(profile.host, '192.168.1.20');
      expect(profile.port, 22);
      expect(profile.username, 'shahnebaj');
      expect(profile.remoteDir, '/home/shahnebaj/Desktop/Sticky');
    });

    test('returns null for empty or invalid codes', () {
      expect(SshProfile.parsePairingCode(''), isNull);
      expect(SshProfile.parsePairingCode('not-a-valid-pairing-code'), isNull);
    });
  });
}
