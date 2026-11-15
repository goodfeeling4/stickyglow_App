import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sticky_notes_ssh/screens/home_screen.dart';
import 'package:sticky_notes_ssh/services/background_sync_manager.dart';
import 'package:sticky_notes_ssh/services/local_db_service.dart';
import 'package:sticky_notes_ssh/services/notification_service.dart';
import 'package:sticky_notes_ssh/services/secure_storage_service.dart';
import 'package:sticky_notes_ssh/services/ssh_sync_service.dart';
import 'package:sticky_notes_ssh/services/udp_sync_service.dart';
import 'package:sticky_notes_ssh/theme/app_theme.dart';
import 'package:sticky_notes_ssh/view_models/home_view_model.dart';
import 'package:sticky_notes_ssh/view_models/settings_view_model.dart';

/// Entry point of the Sticky Notes SSH application.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notifications
  try {
    await NotificationService().initialize();
  } catch (e, stack) {
    debugPrint('Failed to initialize NotificationService: $e\n$stack');
  }

  final localDbService = LocalDbService();
  final secureStorageService = SecureStorageService();
  final sshSyncService = SshSyncService(
    localDbService: localDbService,
    secureStorageService: secureStorageService,
  );
  final udpSyncService = UdpSyncService();

  // Initialize background sync manager (Workmanager) if auto-sync is enabled
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      final isAutoSync = await secureStorageService.getAutoSyncEnabled();
      if (isAutoSync) {
        await BackgroundSyncManager.enableAutoSync();
      }
    } catch (e, stack) {
      debugPrint('Failed to initialize BackgroundSyncManager: $e\n$stack');
    }
  }

  runApp(
    MultiProvider(
      providers: [
        Provider<LocalDbService>.value(value: localDbService),
        Provider<SecureStorageService>.value(value: secureStorageService),
        Provider<SshSyncService>.value(value: sshSyncService),
        Provider<UdpSyncService>.value(value: udpSyncService),
        ChangeNotifierProvider<HomeViewModel>(
          create: (_) => HomeViewModel(
            localDbService: localDbService,
            sshSyncService: sshSyncService,
            secureStorageService: secureStorageService,
            udpSyncService: udpSyncService,
          ),
        ),
        ChangeNotifierProvider<SettingsViewModel>(
          create: (_) => SettingsViewModel(
            localDbService: localDbService,
            secureStorageService: secureStorageService,
            sshSyncService: sshSyncService,
          ),
        ),
      ],
      child: const StickyNotesApp(),
    ),
  );
}

/// The root application widget configuring the Material 3 theme and navigation.
class StickyNotesApp extends StatelessWidget {
  /// Creates the [StickyNotesApp].
  const StickyNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sticky Notes',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
