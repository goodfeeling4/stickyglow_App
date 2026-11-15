import 'dart:convert';

/// Represents an SSH connection profile used to reach a remote laptop/server.
///
/// Each profile represents a specific machine (e.g. Laptop, Home Server).
/// Exactly one profile is active at a time. A profile can monitor multiple
/// remote directories and individual Markdown files.
class SshProfile {
  /// Creates a new [SshProfile] instance.
  const SshProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.remoteDir = '~/sticky-notes',
    this.remotePaths = const <String>[],
    this.priority = 0,
    required this.privateKeyId,
  });

  /// Unique identifier (UUID v4).
  final String id;

  /// Human-friendly label for this profile (e.g. 'Laptop', 'Home Server').
  final String name;

  /// Remote host address (IPv4, IPv6, or hostname).
  final String host;

  /// SSH port on the remote host (defaults to 22).
  final int port;

  /// SSH username on the remote host.
  final String username;

  /// Remote directory path containing the Git-versioned Markdown notes (primary default).
  final String remoteDir;

  /// Multiple remote directory and/or file paths monitored and synced for this profile.
  final List<String> remotePaths;

  /// Returns all configured remote paths, falling back to [remoteDir] if empty.
  List<String> get allRemotePaths {
    if (remotePaths.isNotEmpty) {
      return remotePaths;
    }
    return <String>[remoteDir];
  }

  /// Profile priority order; lower integer indicates higher probe priority.
  final int priority;

  /// Key identifier referencing the private key in secure storage.
  final String privateKeyId;

  /// Converts this [SshProfile] to a SQLite-compatible map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'remoteDir': remoteDir,
      'remotePaths': jsonEncode(remotePaths),
      'priority': priority,
      'privateKeyId': privateKeyId,
    };
  }

  /// Creates an [SshProfile] from a SQLite map.
  factory SshProfile.fromMap(Map<String, dynamic> map) {
    final rawPaths = map['remotePaths'];
    List<String> parsedPaths = const <String>[];
    if (rawPaths is String && rawPaths.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPaths);
        if (decoded is List) {
          parsedPaths = decoded.map((dynamic item) => item.toString()).toList();
        }
      } catch (_) {
        parsedPaths = const <String>[];
      }
    } else if (rawPaths is List) {
      parsedPaths = rawPaths.map((dynamic item) => item.toString()).toList();
    }

    final defaultDir = (map['remoteDir'] as String?) ?? '~/sticky-notes';

    return SshProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      host: map['host'] as String,
      port: (map['port'] as num?)?.toInt() ?? 22,
      username: map['username'] as String,
      remoteDir: defaultDir,
      remotePaths: parsedPaths.isNotEmpty ? parsedPaths : <String>[defaultDir],
      priority: (map['priority'] as num?)?.toInt() ?? 0,
      privateKeyId: (map['privateKeyId'] as String?) ?? '',
    );
  }

  /// Returns a copy of this [SshProfile] with updated fields.
  SshProfile copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? remoteDir,
    List<String>? remotePaths,
    int? priority,
    String? privateKeyId,
  }) {
    return SshProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      remoteDir: remoteDir ?? this.remoteDir,
      remotePaths: remotePaths ?? this.remotePaths,
      priority: priority ?? this.priority,
      privateKeyId: privateKeyId ?? this.privateKeyId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SshProfile || runtimeType != other.runtimeType) return false;

    if (id != other.id ||
        name != other.name ||
        host != other.host ||
        port != other.port ||
        username != other.username ||
        remoteDir != other.remoteDir ||
        priority != other.priority ||
        privateKeyId != other.privateKeyId) {
      return false;
    }

    if (remotePaths.length != other.remotePaths.length) return false;
    for (var i = 0; i < remotePaths.length; i++) {
      if (remotePaths[i] != other.remotePaths[i]) return false;
    }

    return true;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        host,
        port,
        username,
        remoteDir,
        Object.hashAll(remotePaths),
        priority,
        privateKeyId,
      );

  @override
  String toString() {
    return 'SshProfile('
        'id: $id, '
        'name: $name, '
        'host: $host, '
        'port: $port, '
        'username: $username, '
        'remoteDir: $remoteDir, '
        'remotePaths: $remotePaths, '
        'priority: $priority, '
        'privateKeyId: $privateKeyId'
        ')';
  }
}
