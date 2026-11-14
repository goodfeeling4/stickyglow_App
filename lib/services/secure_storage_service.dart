import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service managing secure credential storage for SSH profiles.
///
/// Stores sensitive data (SSH private key PEMs, passwords) using
/// [FlutterSecureStorage] with Android encrypted shared preferences.
class SecureStorageService {
  /// Creates a new [SecureStorageService] instance with optional [storage] injection.
  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const String _keyPrefix = 'ssh_key_';
  static const String _passPrefix = 'ssh_pass_';

  String _privateKeyKey(String profileId) => '$_keyPrefix$profileId';
  String _passwordKey(String profileId) => '$_passPrefix$profileId';

  /// Saves the private key PEM content for [profileId].
  Future<void> savePrivateKey(String profileId, String pemContent) async {
    await _storage.write(
      key: _privateKeyKey(profileId),
      value: pemContent,
    );
  }

  /// Retrieves the private key PEM content for [profileId], or `null` if not set.
  Future<String?> getPrivateKey(String profileId) async {
    return _storage.read(key: _privateKeyKey(profileId));
  }

  /// Deletes the private key for [profileId].
  Future<void> deletePrivateKey(String profileId) async {
    await _storage.delete(key: _privateKeyKey(profileId));
  }

  /// Saves the SSH connection password for [profileId].
  Future<void> savePassword(String profileId, String password) async {
    await _storage.write(
      key: _passwordKey(profileId),
      value: password,
    );
  }

  /// Retrieves the SSH connection password for [profileId], or `null` if not set.
  Future<String?> getPassword(String profileId) async {
    return _storage.read(key: _passwordKey(profileId));
  }

  /// Deletes the SSH connection password for [profileId].
  Future<void> deletePassword(String profileId) async {
    await _storage.delete(key: _passwordKey(profileId));
  }

  static const String _autoSyncKey = 'auto_sync_enabled';

  /// Saves the auto-sync preference.
  Future<void> setAutoSyncEnabled(bool enabled) async {
    await _storage.write(
      key: _autoSyncKey,
      value: enabled ? 'true' : 'false',
    );
  }

  /// Retrieves the auto-sync preference, defaulting to false.
  Future<bool> getAutoSyncEnabled() async {
    final value = await _storage.read(key: _autoSyncKey);
    return value == 'true';
  }
}
