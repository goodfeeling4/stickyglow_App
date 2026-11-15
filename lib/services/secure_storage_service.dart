import 'dart:convert';

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

  static const String _activeProfileIdKey = 'active_profile_id';

  /// Saves the currently selected active SSH profile ID.
  Future<void> saveActiveProfileId(String profileId) async {
    await _storage.write(
      key: _activeProfileIdKey,
      value: profileId,
    );
  }

  /// Retrieves the currently selected active SSH profile ID, or `null` if not set.
  Future<String?> getActiveProfileId() async {
    return _storage.read(key: _activeProfileIdKey);
  }

  /// Deletes the currently selected active SSH profile ID.
  Future<void> deleteActiveProfileId() async {
    await _storage.delete(key: _activeProfileIdKey);
  }

  static const String _activeLocationKey = 'active_profile_location';

  /// Saves the currently selected active location/directory for notes.
  Future<void> saveActiveLocation(String? location) async {
    if (location == null) {
      await _storage.delete(key: _activeLocationKey);
    } else {
      await _storage.write(key: _activeLocationKey, value: location);
    }
  }

  /// Retrieves the currently selected active location/directory, or `null`.
  Future<String?> getActiveLocation() async {
    return _storage.read(key: _activeLocationKey);
  }

  static const String _selectedLocationsKey = 'selected_profile_locations';

  /// Saves the set of multi-selected location keys ('$profileId::$locationPath').
  Future<void> saveSelectedLocationKeys(Set<String> keys) async {
    await _storage.write(
      key: _selectedLocationsKey,
      value: jsonEncode(keys.toList()),
    );
  }

  /// Retrieves the set of multi-selected location keys, or null if never set.
  Future<Set<String>?> getSelectedLocationKeys() async {
    final raw = await _storage.read(key: _selectedLocationsKey);
    if (raw == null) return null;
    if (raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toSet();
      }
    } catch (_) {}
    return <String>{};
  }
}
