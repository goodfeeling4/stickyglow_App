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
  final List<SshProfile> storedProfiles = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<StickyNote>> getAllNotes({String? profileId}) async =>
      storedNotes.values.toList();

  @override
  Future<List<SshProfile>> getAllProfiles() async => storedProfiles;

  @override
  Future<int> insertProfile(SshProfile profile) async {
    storedProfiles.add(profile);
    return storedProfiles.length;
  }
}

class FakeSecureStorageService implements SecureStorageService {
  String? bgConfig;
  bool isGrid = true;

  String? activeProfileId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<String?> getActiveProfileId() async => activeProfileId;

  @override
  Future<void> saveActiveProfileId(String profileId) async {
    activeProfileId = profileId;
  }

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

  String? activeLocation;
  Set<String>? selectedLocationKeys;

  @override
  Future<void> saveActiveLocation(String? location) async {
    activeLocation = location;
  }

  @override
  Future<String?> getActiveLocation() async => activeLocation;

  @override
  Future<void> saveSelectedLocationKeys(Set<String> keys) async {
    selectedLocationKeys = Set.from(keys);
  }

  @override
  Future<Set<String>?> getSelectedLocationKeys() async => selectedLocationKeys;
}

class FakeSshSyncService implements SshSyncService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<SyncResult> syncAll({String? profileId}) async =>
      const SyncResult.empty();

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

  testWidgets('HomeScreen machine chip opens switcher sheet and shows independent directory entries with switches', (tester) async {
    final fakeDb = FakeLocalDbService();
    final fakeStorage = FakeSecureStorageService();
    final fakeSync = FakeSshSyncService();

    const p1 = SshProfile(
      id: 'p1',
      name: 'Laptop',
      host: '192.168.1.100',
      username: 'user',
      remotePaths: <String>['~/sticky-notes', '~/projects/docs'],
      privateKeyId: 'k1',
    );
    const p2 = SshProfile(
      id: 'p2',
      name: 'Home Server',
      host: '192.168.1.200',
      username: 'user',
      remotePaths: <String>['/var/notes'],
      privateKeyId: 'k2',
    );

    await fakeDb.insertProfile(p1);
    await fakeDb.insertProfile(p2);
    await fakeStorage.saveActiveProfileId('p1');
    await fakeStorage.saveActiveLocation('~/sticky-notes');

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

    // Verify machine chip shows Laptop (sticky-notes)
    expect(find.text('Laptop (sticky-notes)'), findsOneWidget);

    // Tap machine chip to open sheet
    await tester.tap(find.text('Laptop (sticky-notes)'));
    await tester.pumpAndSettle();

    // Verify sheet title and independent items
    expect(find.text('Machines & Directories'), findsOneWidget);
    expect(find.text('Laptop (~/sticky-notes)'), findsOneWidget);
    expect(find.text('Laptop (~/projects/docs)'), findsOneWidget);
    expect(find.text('Home Server (/var/notes)'), findsOneWidget);

    // Verify separate switches for all 3 entries
    expect(find.byType(Switch), findsNWidgets(3));

    // Tap the second entry 'Laptop (~/projects/docs)'
    await tester.tap(find.text('Laptop (~/projects/docs)'));
    await tester.pumpAndSettle();

    // Verify active selection updated
    expect(homeVm.isLocationSelected('p1', '~/sticky-notes'), isTrue);
    expect(homeVm.isLocationSelected('p1', '~/projects/docs'), isTrue);
    expect(homeVm.selectedLocationsCount, 2);
    expect(find.text('2 Locations'), findsOneWidget);
  });
}
