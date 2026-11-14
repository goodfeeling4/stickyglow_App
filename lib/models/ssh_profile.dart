/// Represents an SSH connection profile used to reach a remote laptop/server.
///
/// Multiple profiles can be registered with different priorities (e.g. Android
/// Hotspot IP, Home LAN IP, Tailscale IP). The app probes them to find the
/// fastest responsive route.
class SshProfile {
  /// Creates a new [SshProfile] instance.
  const SshProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.remoteDir = '~/sticky-notes',
    this.priority = 0,
    required this.privateKeyId,
  });

  /// Unique identifier (UUID v4).
  final String id;

  /// Human-friendly label for this profile (e.g. 'Home LAN', 'Tailscale').
  final String name;

  /// Remote host address (IPv4, IPv6, or hostname).
  final String host;

  /// SSH port on the remote host (defaults to 22).
  final int port;

  /// SSH username on the remote host.
  final String username;

  /// Remote directory path containing the Git-versioned Markdown notes.
  final String remoteDir;

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
      'priority': priority,
      'privateKeyId': privateKeyId,
    };
  }

  /// Creates an [SshProfile] from a SQLite map.
  factory SshProfile.fromMap(Map<String, dynamic> map) {
    return SshProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      host: map['host'] as String,
      port: (map['port'] as num?)?.toInt() ?? 22,
      username: map['username'] as String,
      remoteDir: (map['remoteDir'] as String?) ?? '~/sticky-notes',
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
      priority: priority ?? this.priority,
      privateKeyId: privateKeyId ?? this.privateKeyId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SshProfile &&
        runtimeType == other.runtimeType &&
        id == other.id &&
        name == other.name &&
        host == other.host &&
        port == other.port &&
        username == other.username &&
        remoteDir == other.remoteDir &&
        priority == other.priority &&
        privateKeyId == other.privateKeyId;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        host,
        port,
        username,
        remoteDir,
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
        'priority: $priority, '
        'privateKeyId: $privateKeyId'
        ')';
  }
}
