import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_notes_ssh/services/background_sync_manager.dart';
import 'package:sticky_notes_ssh/services/ssh_sync_service.dart';
import 'package:sticky_notes_ssh/services/udp_sync_service.dart';

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

  group('UdpSyncService Tests', () {
    test('lifecycle: start, deduplicate bind, receive packet, and stop', () async {
      final udp = UdpSyncService();
      bool triggered = false;

      await udp.startListening(
        onSyncTrigger: () {
          triggered = true;
        },
      );
      expect(udp.isListening, isTrue);

      // Duplicate startListening should not throw or duplicate bind
      await udp.startListening(
        onSyncTrigger: () {
          triggered = true;
        },
      );
      expect(udp.isListening, isTrue);

      // Send a test packet to 127.0.0.1:41234
      final sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      sender.send(utf8.encode('sync'), InternetAddress.loopbackIPv4, 41234);
      sender.close();

      // Wait for debounce (500ms debounce interval)
      await Future<void>.delayed(const Duration(milliseconds: 650));
      expect(triggered, isTrue);

      udp.stopListening();
      expect(udp.isListening, isFalse);

      // Duplicate stopListening is idempotent
      udp.stopListening();
      expect(udp.isListening, isFalse);
    });
  });
}
