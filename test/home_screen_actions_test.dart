import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sticky_notes_ssh/models/home_background.dart';
import 'package:sticky_notes_ssh/models/ssh_profile.dart';
import 'package:sticky_notes_ssh/models/sticky_note.dart';
import 'package:sticky_notes_ssh/screens/home_screen.dart';
import 'package:sticky_notes_ssh/services/local_db_service.dart';
import 'package:sticky_notes_ssh/services/secure_storage_service.dart';
import 'package:sticky_notes_ssh/services/ssh_sync_service.dart';
import 'package:sticky_notes_ssh/theme/app_theme.dart';
import 'package:sticky_notes_ssh/view_models/home_view_model.dart';
import 'package:sticky_notes_ssh/view_models/settings_view_model.dart';
import 'package:sticky_notes_ssh/widgets/background_picker_sheet.dart';

class FakeLocalDbService implements LocalDbService {
  final Map<String, StickyNote> storedNotes = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<StickyNote>> getAllNotes() async => storedNotes.values.toList();

  @override
  Future<List<SshProfile>> getAllProfiles() async => const [];
}

class FakeSecureStorageService implements SecureStorageService {
  String? bgConfig;
  bool isGrid = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<String?> getPrivateKey(String profileId) async => null;

  @override
  Future<bool> getAutoSyncEnabled() async => false;

  @override
  Future<String?> getHomeBackground() async => bgConfig;

  @override
  Future<void> saveHomeBackground(String jsonConfig) async {
    bgConfig = jsonConfig;
  }

  @override
  Future<void> deleteHomeBackground() async {
    bgConfig = null;
  }

  @override
  Future<bool> getGridViewMode() async => isGrid;

  @override
  Future<void> setGridViewMode(bool grid) async {
    isGrid = grid;
  }
}

class FakeSshSyncService implements SshSyncService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<SyncResult> syncAll() async => const SyncResult.empty();

  @override
  Future<SshProfile?> findReachableProfile() async => null;

  @override
  bool get isWatchingRemote => false;

  @override
  void stopRemoteFileWatcher() {}
}

void main() {
  testWidgets('HomeScreen has View Mode toggle and Background Customizer buttons', (tester) async {
    final fakeDb = FakeLocalDbService();
    final fakeStorage = FakeSecureStorageService();
    final fakeSync = FakeSshSyncService();

    final homeVm = HomeViewModel(
      localDbService: fakeDb,
      sshSyncService: fakeSync,
      secureStorageService: fakeStorage,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<LocalDbService>.value(value: fakeDb),
          Provider<SecureStorageService>.value(value: fakeStorage),
          Provider<SshSyncService>.value(value: fakeSync),
          ChangeNotifierProvider<HomeViewModel>.value(value: homeVm),
          ChangeNotifierProvider<SettingsViewModel>(
            create: (_) => SettingsViewModel(
              localDbService: fakeDb,
              secureStorageService: fakeStorage,
              sshSyncService: fakeSync,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: const HomeScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify View Mode button exists with tooltip
    expect(find.byTooltip('Markdown Reader View'), findsOneWidget);

    // Tap View Mode button to toggle to Reader View
    await tester.tap(find.byTooltip('Markdown Reader View'));
    await tester.pumpAndSettle();

    expect(homeVm.isGridView, isFalse);
    expect(find.byTooltip('Grid View'), findsOneWidget);

    // Verify Customize Background button exists
    expect(find.byTooltip('Customize background'), findsOneWidget);

    // Tap Customize background to open bottom sheet
    await tester.tap(find.byTooltip('Customize background'));
    await tester.pumpAndSettle();

    expect(find.byType(BackgroundPickerSheet), findsOneWidget);
    expect(find.text('Home Background'), findsOneWidget);
    expect(find.text('CURATED GRADIENTS'), findsOneWidget);
    expect(find.text('PASTEL & SOLID COLORS'), findsOneWidget);

    // Tap on Warm Amber preset color in the bottom sheet
    await tester.tap(find.byTooltip('Warm Amber'));
    await tester.pumpAndSettle();

    expect(homeVm.background.type, HomeBackgroundType.color);
    expect(homeVm.background.colorValue, 0xFFFFF8E1);
  });
}
