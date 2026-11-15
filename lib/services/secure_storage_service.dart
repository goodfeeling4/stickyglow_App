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

  String _privateKeyKey(String profileId) => '$_keyPrefix$profileId';

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

  static const String _homeBackgroundKey = 'home_background_config';

  /// Saves the home screen background configuration JSON.
  Future<void> saveHomeBackground(String jsonConfig) async {
    await _storage.write(
      key: _homeBackgroundKey,
      value: jsonConfig,
    );
  }

  /// Retrieves the home screen background configuration JSON, or `null` if not set.
  Future<String?> getHomeBackground() async {
    return _storage.read(key: _homeBackgroundKey);
  }

  /// Deletes the home screen background configuration.
  Future<void> deleteHomeBackground() async {
    await _storage.delete(key: _homeBackgroundKey);
  }

  static const String _viewModeKey = 'home_is_grid_view';

  /// Saves the home screen grid view mode preference.
  Future<void> setGridViewMode(bool isGrid) async {
    await _storage.write(
      key: _viewModeKey,
      value: isGrid ? 'true' : 'false',
    );
  }

  /// Retrieves the home screen grid view preference, defaulting to true.
  Future<bool> getGridViewMode() async {
    final value = await _storage.read(key: _viewModeKey);
    return value != 'false';
  }
}
