import 'package:flutter/foundation.dart';
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

  /// Initializes the Workmanager plugin and registers periodic auto-sync if supported.
  static Future<void> initialize() async {
    await enableAutoSync();
  }

  /// Enables auto-sync on event triggers (network connection, note save, app open)
  /// without registering any periodic 15-minute background polling timers.
  static Future<void> enableAutoSync() async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        WidgetsFlutterBinding.ensureInitialized();
        await Workmanager().initialize(
          callbackDispatcher,
          isInDebugMode: false,
        );

        // Cancel any lingering periodic timer tasks previously scheduled
        await Workmanager().cancelByUniqueName(taskName);

        await triggerImmediateSync();
      } catch (e) {
        debugPrint('Failed to enable background auto-sync: $e');
      }
    }
  }

  /// Disables auto-sync by canceling all scheduled Workmanager tasks.
  static Future<void> disableAutoSync() async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        WidgetsFlutterBinding.ensureInitialized();
        await cancelAll();
      } catch (e) {
        debugPrint('Failed to cancel background sync tasks: $e');
      }
    }
  }

  /// Schedules a one-off background sync task to execute immediately when network is connected.
  static Future<void> triggerImmediateSync() async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        await Workmanager().registerOneOffTask(
          '${immediateTaskName}_${DateTime.now().millisecondsSinceEpoch}',
          immediateTaskName,
          constraints: Constraints(
            networkType: NetworkType.connected,
          ),
          existingWorkPolicy: ExistingWorkPolicy.replace,
        );
      } catch (e) {
        debugPrint('Failed to schedule immediate background sync: $e');
      }
    }
  }

  /// Cancels all scheduled periodic and one-off background sync tasks.
  static Future<void> cancelAll() async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        await Workmanager().cancelAll();
      } catch (e) {
        debugPrint('Failed to cancel Workmanager tasks: $e');
      }
    }
  }

  /// Executes background synchronization and posts local Android notifications
  /// if changes or conflicts are detected.
  static Future<bool> performBackgroundSync() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final secureStorage = SecureStorageService();
      final isEnabled = await secureStorage.getAutoSyncEnabled();
      if (!isEnabled) {
        return true;
      }

      final localDb = LocalDbService();
      final syncService = SshSyncService(
        localDbService: localDb,
        secureStorageService: secureStorage,
      );

      // Probe reachable profiles. If none respond within 1500ms, abort silently (<2s).
      final reachable = await syncService.findReachableProfile();
      if (reachable == null) {
        return true;
      }

      final notificationService = NotificationService();
      await notificationService.initialize();

      final result = await syncService.syncAll();

      if (result.hasConflicts) {
        final conflictNotes = await localDb.getConflictNotes(profileId: reachable.id);
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
