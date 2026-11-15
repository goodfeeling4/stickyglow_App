import 'dart:convert';

/// Synchronization status of a sticky note relative to the remote Git repository.
enum SyncStatus {
  /// The local note matches the remote repository.
  synced,

  /// The local note has unpushed changes or has not been synced yet.
  pending,

  /// A conflict occurred during sync and requires manual resolution.
  conflict,
}

/// Represents an offline-first sticky note.
///
/// Mobile-specific metadata ([colorIndex], [isPinned], [tags], [syncStatus],
/// [conflictRemoteContent], [lastSyncedAt], [profileId], [remotePath]) is stored
/// in SQLite, while the note markdown content is saved as a plain-text `.md` file
/// inside the isolated profile compartment without YAML frontmatter.
class StickyNote {
  /// Creates a new [StickyNote] instance.
  const StickyNote({
    required this.id,
    this.profileId = '',
    this.remotePath,
    required this.filename,
    required this.title,
    required this.content,
    this.colorIndex = 0,
    this.isPinned = false,
    this.tags = const <String>[],
    required this.updatedAt,
    required this.createdAt,
    this.syncStatus = SyncStatus.pending,
    this.conflictRemoteContent,
    this.lastSyncedAt,
  });

  /// Unique identifier (UUID v4).
  final String id;

  /// Identifier of the SSH profile compartment this note belongs to.
  final String profileId;

  /// Remote directory or file path this note belongs to (e.g. '~/sticky-notes').
  final String? remotePath;

  /// Markdown file name on disk and remote host (e.g. 'shopping-list.md').
  final String filename;

  /// User-facing title of the sticky note.
  final String title;

  /// Raw Markdown content of the sticky note (no frontmatter).
  final String content;

  /// Index (0-5) mapping to one of the 6 pastel sticky note palette colors.
  final int colorIndex;

  /// Whether the note is pinned to the top of the grid.
  final bool isPinned;

  /// List of tag labels associated with this note.
  final List<String> tags;

  /// Timestamp when the note was last modified locally.
  final DateTime updatedAt;

  /// Timestamp when the note was created.
  final DateTime createdAt;

  /// Current sync state relative to the laptop SSH host.
  final SyncStatus syncStatus;

  /// Remote Markdown content snapshot preserved when a conflict occurs.
  final String? conflictRemoteContent;

  /// Timestamp of the last successful sync with the remote repository.
  final DateTime? lastSyncedAt;

  /// Converts this [StickyNote] to a SQLite-compatible map.
  ///
  /// Tags are serialized as a JSON string, dates as ISO-8601 strings,
  /// booleans as integers (1/0), and [syncStatus] as its enum name.
  /// Converts this [StickyNote] to a SQLite-compatible map.
  ///
  /// Tags are serialized as a JSON string, dates as ISO-8601 strings,
  /// booleans as integers (1/0), and [syncStatus] as its enum name.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'profileId': profileId,
      'remotePath': remotePath,
      'filename': filename,
      'title': title,
      'content': content,
      'colorIndex': colorIndex,
      'isPinned': isPinned ? 1 : 0,
      'tags': jsonEncode(tags),
      'updatedAt': updatedAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'syncStatus': syncStatus.name,
      'conflictRemoteContent': conflictRemoteContent,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    };
  }

  /// Creates a [StickyNote] from a SQLite map.
  factory StickyNote.fromMap(Map<String, dynamic> map) {
    final rawTags = map['tags'];
    List<String> parsedTags;
    if (rawTags is String && rawTags.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawTags);
        if (decoded is List) {
          parsedTags = decoded.map((dynamic item) => item.toString()).toList();
        } else {
          parsedTags = const <String>[];
        }
      } catch (_) {
        parsedTags = const <String>[];
      }
    } else if (rawTags is List) {
      parsedTags = rawTags.map((dynamic item) => item.toString()).toList();
    } else {
      parsedTags = const <String>[];
    }

    final statusString = map['syncStatus'] as String?;
    final status = statusString != null
        ? SyncStatus.values.firstWhere(
            (SyncStatus item) => item.name == statusString,
            orElse: () => SyncStatus.pending,
          )
        : SyncStatus.pending;

    final rawIsPinned = map['isPinned'];
    final isPinned = rawIsPinned == 1 || rawIsPinned == true;

    final lastSyncedRaw = map['lastSyncedAt'] as String?;

    return StickyNote(
      id: map['id'] as String,
      profileId: (map['profileId'] as String?) ?? '',
      remotePath: map['remotePath'] as String?,
      filename: map['filename'] as String,
      title: (map['title'] as String?) ?? '',
      content: (map['content'] as String?) ?? '',
      colorIndex: (map['colorIndex'] as num?)?.toInt() ?? 0,
      isPinned: isPinned,
      tags: parsedTags,
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      createdAt: DateTime.parse(map['createdAt'] as String),
      syncStatus: status,
      conflictRemoteContent: map['conflictRemoteContent'] as String?,
      lastSyncedAt:
          lastSyncedRaw != null ? DateTime.parse(lastSyncedRaw) : null,
    );
  }

  /// Returns a copy of this [StickyNote] with updated fields.
  StickyNote copyWith({
    String? id,
    String? profileId,
    String? remotePath,
    String? filename,
    String? title,
    String? content,
    int? colorIndex,
    bool? isPinned,
    List<String>? tags,
    DateTime? updatedAt,
    DateTime? createdAt,
    SyncStatus? syncStatus,
    String? conflictRemoteContent,
    bool clearConflict = false,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
  }) {
    return StickyNote(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      remotePath: remotePath ?? this.remotePath,
      filename: filename ?? this.filename,
      title: title ?? this.title,
      content: content ?? this.content,
      colorIndex: colorIndex ?? this.colorIndex,
      isPinned: isPinned ?? this.isPinned,
      tags: tags ?? this.tags,
      updatedAt: updatedAt ?? this.updatedAt,
      createdAt: createdAt ?? this.createdAt,
      syncStatus: syncStatus ?? this.syncStatus,
      conflictRemoteContent: clearConflict
          ? null
          : (conflictRemoteContent ?? this.conflictRemoteContent),
      lastSyncedAt: clearLastSyncedAt
          ? null
          : (lastSyncedAt ?? this.lastSyncedAt),
    );
  }

  /// Returns the raw markdown content without any YAML frontmatter.
  String toMarkdown() => content;

  /// Converts a user-provided [title] into a safe kebab-case `.md` filename.
  ///
  /// Transforms input to lowercase, replaces whitespace sequences with hyphens,
  /// strips characters outside `[a-z0-9\-]`, collapses multiple hyphens,
  /// trims leading/trailing hyphens, and appends the `.md` extension.
  /// If the sanitized result is empty, defaults to `'untitled.md'`.
  static String filenameFromTitle(String title) {
    var sanitized = title.trim().toLowerCase();
    if (sanitized.endsWith('.md')) {
      sanitized = sanitized.substring(0, sanitized.length - 3);
    }
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), '-');
    sanitized = sanitized.replaceAll(RegExp(r'[^a-z0-9\-]'), '');
    sanitized = sanitized.replaceAll(RegExp(r'-+'), '-');
    sanitized = sanitized.replaceAll(RegExp(r'^-+|-+$'), '');
    if (sanitized.isEmpty) {
      sanitized = 'untitled';
    }
    return '$sanitized.md';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! StickyNote || runtimeType != other.runtimeType) return false;

    if (id != other.id ||
        profileId != other.profileId ||
        remotePath != other.remotePath ||
        filename != other.filename ||
        title != other.title ||
        content != other.content ||
        colorIndex != other.colorIndex ||
        isPinned != other.isPinned ||
        updatedAt != other.updatedAt ||
        createdAt != other.createdAt ||
        syncStatus != other.syncStatus ||
        conflictRemoteContent != other.conflictRemoteContent ||
        lastSyncedAt != other.lastSyncedAt) {
      return false;
    }

    if (tags.length != other.tags.length) return false;
    for (var i = 0; i < tags.length; i++) {
      if (tags[i] != other.tags[i]) return false;
    }

    return true;
  }

  @override
  int get hashCode => Object.hash(
        id,
        profileId,
        remotePath,
        filename,
        title,
        content,
        colorIndex,
        isPinned,
        Object.hashAll(tags),
        updatedAt,
        createdAt,
        syncStatus,
        conflictRemoteContent,
        lastSyncedAt,
      );

  @override
  String toString() {
    return 'StickyNote('
        'id: $id, '
        'profileId: $profileId, '
        'filename: $filename, '
        'title: $title, '
        'colorIndex: $colorIndex, '
        'isPinned: $isPinned, '
        'tags: $tags, '
        'syncStatus: ${syncStatus.name}, '
        'updatedAt: $updatedAt'
        ')';
  }
}
