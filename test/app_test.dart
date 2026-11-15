import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sticky_notes_ssh/models/ssh_profile.dart';
import 'package:sticky_notes_ssh/models/sticky_note.dart';
import 'package:sticky_notes_ssh/screens/home_screen.dart';
import 'package:sticky_notes_ssh/services/local_db_service.dart';
import 'package:sticky_notes_ssh/services/secure_storage_service.dart';
import 'package:sticky_notes_ssh/services/ssh_sync_service.dart';
import 'package:sticky_notes_ssh/theme/app_theme.dart';
import 'package:sticky_notes_ssh/view_models/home_view_model.dart';
import 'package:sticky_notes_ssh/view_models/settings_view_model.dart';

class FakeLocalDbService implements LocalDbService {
  final Map<String, StickyNote> storedNotes = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<StickyNote>> getAllNotes() async => storedNotes.values.toList();

  @override
  Future<List<SshProfile>> getAllProfiles() async => const [];

  @override
  Future<int> insertNote(StickyNote note) async {
    storedNotes[note.id] = note;
    return 1;
  }
}

class FakeSecureStorageService implements SecureStorageService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<String?> getPrivateKey(String profileId) async => null;

  @override
  Future<bool> getAutoSyncEnabled() async => false;
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
  Future<void> startRemoteFileWatcher({required void Function() onRemoteChange}) async {}

  @override
  void stopRemoteFileWatcher() {}
}

void main() {
  testWidgets('App renders HomeScreen with empty state and title', (tester) async {
    final fakeDb = FakeLocalDbService();
    final fakeStorage = FakeSecureStorageService();
    final fakeSync = FakeSshSyncService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<LocalDbService>.value(value: fakeDb),
          Provider<SecureStorageService>.value(value: fakeStorage),
          Provider<SshSyncService>.value(value: fakeSync),
          ChangeNotifierProvider<HomeViewModel>(
            create: (_) => HomeViewModel(
              localDbService: fakeDb,
              sshSyncService: fakeSync,
              secureStorageService: fakeStorage,
            ),
          ),
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

    expect(find.text('Sticky Notes'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('No notes yet. Tap + to create one.'), findsOneWidget);
  });
}
