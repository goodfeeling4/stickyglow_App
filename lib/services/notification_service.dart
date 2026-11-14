import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sticky_notes_ssh/services/ssh_sync_service.dart';

/// Service managing local Android notifications for sync summaries,
/// conflict warnings, and background sync errors.
class NotificationService {
  NotificationService._internal();

  static final NotificationService _instance = NotificationService._internal();

  /// Returns the singleton instance of [NotificationService].
  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// Android channel for general laptop sync status updates.
  static const AndroidNotificationChannel _syncChannel =
      AndroidNotificationChannel(
    'sync_channel',
    'Laptop Sync',
    description: 'Notifications for background sync with laptop',
    importance: Importance.defaultImportance,
  );

  /// Android channel for high-priority merge conflict alerts.
  static const AndroidNotificationChannel _conflictChannel =
      AndroidNotificationChannel(
    'conflict_channel',
    'Merge Conflicts',
    description: 'Alerts when merge conflicts require attention',
    importance: Importance.high,
    playSound: true,
  );

  /// Sets up notification channels and requests Android 13+ permissions.
  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(initSettings);

    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(_syncChannel);
      await androidImplementation.createNotificationChannel(_conflictChannel);
      await androidImplementation.requestNotificationsPermission();
    }

    _isInitialized = true;
  }

  /// Displays a normal-priority notification summarizing completed sync changes.
  Future<void> showSyncSummary(SyncResult result) async {
    await initialize();
    final notificationId = _generateId('sync_summary');
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'sync_channel',
        'Laptop Sync',
        channelDescription: 'Notifications for background sync with laptop',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
      ),
    );

    await _notificationsPlugin.show(
      notificationId,
      'Laptop Sync Complete',
      result.summary,
      details,
    );
  }

  /// Displays a high-priority sound alert warning the user of a merge conflict.
  Future<void> showConflictAlert(String filename) async {
    await initialize();
    final notificationId = _generateId('conflict_$filename');
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'conflict_channel',
        'Merge Conflicts',
        channelDescription: 'Alerts when merge conflicts require attention',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        icon: '@mipmap/ic_launcher',
      ),
    );

    await _notificationsPlugin.show(
      notificationId,
      'Merge Conflict Detected',
      '$filename has conflicting changes',
      details,
    );
  }

  /// Displays a normal-priority error notification.
  Future<void> showError(String message) async {
    await initialize();
    final notificationId = _generateId('sync_error_$message');
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'sync_channel',
        'Laptop Sync',
        channelDescription: 'Notifications for background sync with laptop',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
      ),
    );

    await _notificationsPlugin.show(
      notificationId,
      'Sync Error',
      message,
      details,
    );
  }

  /// Generates a positive 31-bit integer hash for notification deduplication.
  int _generateId(String key) => key.hashCode.abs() % 0x7FFFFFFF;
}
