import 'package:flutter/foundation.dart';
import 'package:sticky_notes_ssh/models/ssh_profile.dart';
import 'package:sticky_notes_ssh/services/background_sync_manager.dart';
import 'package:sticky_notes_ssh/services/local_db_service.dart';
import 'package:sticky_notes_ssh/services/secure_storage_service.dart';
import 'package:sticky_notes_ssh/services/ssh_sync_service.dart';

/// ViewModel managing SSH server connection profiles, Ed25519 private keys,
/// reachability and authentication testing, profile priorities, and auto-sync preferences.
class SettingsViewModel extends ChangeNotifier {
  /// Creates a [SettingsViewModel] instance with optional service dependencies for testing.
  SettingsViewModel({
    LocalDbService? localDbService,
    SecureStorageService? secureStorageService,
    SshSyncService? sshSyncService,
  })  : _localDbService = localDbService ?? LocalDbService(),
        _secureStorageService = secureStorageService ?? SecureStorageService(),
        _sshSyncService = sshSyncService ?? SshSyncService();

  final LocalDbService _localDbService;
  final SecureStorageService _secureStorageService;
  final SshSyncService _sshSyncService;

  List<SshProfile> _profiles = const <SshProfile>[];
  bool _isLoading = false;
  String? _testResult;
  bool _isTesting = false;
  bool _autoSyncEnabled = false;

  /// Configured SSH profiles sorted by priority (lowest integer = highest priority).
  List<SshProfile> get profiles => _profiles;

  /// Whether profiles are actively loading from the database.
  bool get isLoading => _isLoading;

  /// Diagnostic output message from the most recent connection test.
  String? get testResult => _testResult;

  /// Whether an SSH connection diagnostic test is currently running.
  bool get isTesting => _isTesting;

  /// Whether background auto-sync on network connect is enabled.
  bool get autoSyncEnabled => _autoSyncEnabled;

  /// Loads all registered SSH profiles from SQLite ordered by priority,
  /// loads the auto-sync preference, and updates listeners.
  Future<void> loadProfiles() async {
    _isLoading = true;
    notifyListeners();

    try {
      _profiles = await _localDbService.getAllProfiles();
      _autoSyncEnabled = await _secureStorageService.getAutoSyncEnabled();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Saves a new [profile] to SQLite, stores its [privateKeyPem] in secure storage,
  /// and reloads the profile list.
  Future<void> addProfile(SshProfile profile, String privateKeyPem) async {
    await _localDbService.insertProfile(profile);
    await _secureStorageService.savePrivateKey(profile.id, privateKeyPem);
    if (profile.privateKeyId.isNotEmpty && profile.privateKeyId != profile.id) {
      await _secureStorageService.savePrivateKey(
        profile.privateKeyId,
        privateKeyPem,
      );
    }
    await loadProfiles();
  }

  /// Updates an existing [profile] in SQLite and optionally updates its private key PEM.
  Future<void> updateProfile(
    SshProfile profile, {
    String? newPrivateKeyPem,
  }) async {
    await _localDbService.updateProfile(profile);
    if (newPrivateKeyPem != null && newPrivateKeyPem.trim().isNotEmpty) {
      await _secureStorageService.savePrivateKey(
        profile.id,
        newPrivateKeyPem,
      );
      if (profile.privateKeyId.isNotEmpty &&
          profile.privateKeyId != profile.id) {
        await _secureStorageService.savePrivateKey(
          profile.privateKeyId,
          newPrivateKeyPem,
        );
      }
    }
    await loadProfiles();
  }

  /// Deletes the profile matching [id] from SQLite and purges its keys from secure storage.
  Future<void> deleteProfile(String id) async {
    final profile = await _localDbService.getProfileById(id);
    await _localDbService.deleteProfile(id);
    await _secureStorageService.deletePrivateKey(id);
    if (profile != null && profile.privateKeyId.isNotEmpty) {
      await _secureStorageService.deletePrivateKey(profile.privateKeyId);
    }
    await loadProfiles();
  }

  /// Reorders profiles by adjusting their priority indices and persisting the new order.
  Future<void> reorderProfiles(int oldIndex, int newIndex) async {
    final mutable = List<SshProfile>.from(_profiles);
    var targetIndex = newIndex;
    if (oldIndex < targetIndex) {
      targetIndex -= 1;
    }
    final item = mutable.removeAt(oldIndex);
    mutable.insert(targetIndex, item);

    for (var i = 0; i < mutable.length; i++) {
      final updated = mutable[i].copyWith(priority: i);
      await _localDbService.updateProfile(updated);
    }
    await loadProfiles();
  }

  /// Runs an SSH reachability and authentication diagnostic against [profile].
  Future<void> testConnection(SshProfile profile) async {
    _isTesting = true;
    _testResult = null;
    notifyListeners();

    try {
      final result = await _sshSyncService.testConnection(profile);
      _testResult = result;
    } catch (e) {
      _testResult = 'Connection test failed: $e';
    } finally {
      _isTesting = false;
      notifyListeners();
    }
  }

  /// Updates the auto-sync preference in secure storage, manages background tasks,
  /// triggers an immediate sync if laptop is reachable, and notifies listeners.
  Future<void> toggleAutoSync(bool enabled) async {
    _autoSyncEnabled = enabled;
    await _secureStorageService.setAutoSyncEnabled(enabled);
    if (enabled) {
      await BackgroundSyncManager.enableAutoSync();
      try {
        final reachable = await _sshSyncService.findReachableProfile();
        if (reachable != null) {
          await _sshSyncService.syncAll();
        }
      } catch (_) {}
    } else {
      await BackgroundSyncManager.disableAutoSync();
    }
    notifyListeners();
  }

  /// Emulates `ssh-copy-id`: Connects to host via password auth, adds the public key
  /// to `~/.ssh/authorized_keys`, and validates key authentication.
  Future<String> autoInstallKey({
    required String host,
    required int port,
    required String username,
    required String password,
    required String publicKeyOpenSsh,
    required String privateKeyPem,
    String remoteDir = '~/sticky-notes',
  }) {
    return _sshSyncService.installPublicKeyViaPassword(
      host: host,
      port: port,
      username: username,
      password: password,
      publicKeyOpenSsh: publicKeyOpenSsh,
      privateKeyPem: privateKeyPem,
      remoteDir: remoteDir,
    );
  }
}
