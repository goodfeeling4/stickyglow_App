import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'package:sticky_notes_ssh/services/local_db_service.dart';
import 'package:sticky_notes_ssh/services/notification_service.dart';
import 'package:sticky_notes_ssh/services/secure_storage_service.dart';
import 'package:sticky_notes_ssh/services/ssh_sync_service.dart';

/// Top-level callback dispatcher entry point required by Workmanager.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? inputData) async {
    return BackgroundSyncManager.performBackgroundSync();
  });
}

/// Manager responsible for scheduling and executing periodic and immediate background sync tasks.
class BackgroundSyncManager {
  BackgroundSyncManager._();

  /// Identifier for periodic background sync task.
  static const String taskName = 'com.sticky.backgroundSync';

  /// Identifier for one-off immediate background sync task.
  static const String immediateTaskName = 'com.sticky.immediateSync';

  /// Workmanager callback dispatcher entry point.
  @pragma('vm:entry-point')
  static void callbackDispatcher() {
    Workmanager().executeTask((String task, Map<String, dynamic>? inputData) async {
      return performBackgroundSync();
    });
  }

  /// Initializes the Workmanager plugin, registers the periodic 15-minute background task,
  /// and schedules a one-off task for immediate synchronization.
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );

    await triggerImmediateSync();
  }

  /// Schedules a one-off background sync task to execute immediately when network is connected.
  static Future<void> triggerImmediateSync() async {
    await Workmanager().registerOneOffTask(
      '${immediateTaskName}_${DateTime.now().millisecondsSinceEpoch}',
      immediateTaskName,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  /// Cancels all scheduled periodic and one-off background sync tasks.
  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }

  /// Executes background synchronization and posts local Android notifications
  /// if changes or conflicts are detected.
  static Future<bool> performBackgroundSync() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final localDb = LocalDbService();
      final secureStorage = SecureStorageService();
      final syncService = SshSyncService(
        localDbService: localDb,
        secureStorageService: secureStorage,
      );
      final notificationService = NotificationService();
      await notificationService.initialize();

      final result = await syncService.syncAll();

      if (result.hasConflicts) {
        final conflictNotes = await localDb.getConflictNotes();
        if (conflictNotes.isNotEmpty) {
          for (final note in conflictNotes) {
            await notificationService.showConflictAlert(note.filename);
          }
        } else {
          await notificationService.showConflictAlert('Sticky note');
        }
      } else if (result.hasChanges) {
        await notificationService.showSyncSummary(result);
      }

      return true;
    } catch (_) {
      return false;
    }
  }
}
