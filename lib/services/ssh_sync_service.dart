import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:sticky_notes_ssh/models/ssh_profile.dart';
import 'package:sticky_notes_ssh/models/sticky_note.dart';
import 'package:sticky_notes_ssh/services/conflict_resolver.dart';
import 'package:sticky_notes_ssh/services/local_db_service.dart';
import 'package:sticky_notes_ssh/services/secure_storage_service.dart';

/// Summary result of a bidirectional sync transaction.
class SyncResult {
  /// Creates a new [SyncResult].
  const SyncResult({
    required this.pulled,
    required this.pushed,
    required this.autoMerged,
    required this.conflicts,
    required this.deleted,
    required this.errors,
    this.connectedProfile,
  });

  /// An empty [SyncResult] representing no-op or unreachable endpoints.
  const SyncResult.empty()
      : pulled = 0,
        pushed = 0,
        autoMerged = 0,
        conflicts = 0,
        deleted = 0,
        errors = const <String>[],
        connectedProfile = null;

  /// Number of notes pulled from laptop to phone.
  final int pulled;

  /// Number of notes pushed from phone to laptop.
  final int pushed;

  /// Number of notes automatically merged cleanly without line collisions.
  final int autoMerged;

  /// Number of conflicting notes quarantined for manual user review.
  final int conflicts;

  /// Number of deleted notes propagated between laptop and phone.
  final int deleted;

  /// Error messages encountered during the sync transaction.
  final List<String> errors;

  /// Name of the SSH profile successfully used for this sync.
  final String? connectedProfile;

  /// Whether any notes were modified, added, merged, or deleted.
  bool get hasChanges =>
      pulled > 0 || pushed > 0 || autoMerged > 0 || deleted > 0;

  /// Whether any merge conflicts were encountered.
  bool get hasConflicts => conflicts > 0;

  /// Whether any errors occurred during the sync process.
  bool get hasErrors => errors.isNotEmpty;

  /// Human-readable summary of the sync transaction.
  String get summary {
    final parts = <String>[];
    if (pulled > 0) parts.add('Pulled $pulled');
    if (pushed > 0) parts.add('Pushed $pushed');
    if (autoMerged > 0) parts.add('Auto-merged $autoMerged');
    if (deleted > 0) parts.add('Deleted $deleted');
    if (conflicts > 0) {
      parts.add('$conflicts ${conflicts == 1 ? 'conflict' : 'conflicts'}');
    }

    if (parts.isEmpty) {
      if (hasErrors) {
        return 'Sync completed with errors';
      }
      return 'All notes up to date';
    }
    return parts.join(', ');
  }
}

/// Represents a Git log commit entry parsed from the remote repository.
class GitLogEntry {
  /// Creates a [GitLogEntry].
  const GitLogEntry({
    required this.hash,
    required this.date,
    required this.message,
  });

  /// Short commit hash (e.g. 'a1b2c3d').
  final String hash;

  /// Commit timestamp.
  final DateTime date;

  /// Commit subject message.
  final String message;
}

/// Service handling SSH/SFTP connectivity, reachability probing,
/// remote Git operations, and bidirectional file synchronization.
class SshSyncService {
  /// Creates an [SshSyncService] with optional service injections.
  SshSyncService({
    LocalDbService? localDbService,
    SecureStorageService? secureStorageService,
  })  : _localDbService = localDbService ?? LocalDbService(),
        _secureStorageService = secureStorageService ?? SecureStorageService();

  final LocalDbService _localDbService;
  final SecureStorageService _secureStorageService;

  /// Loads all configured profiles sorted by priority and probes each
  /// in parallel using TCP sockets with a 1500ms timeout.
  ///
  /// Returns the first responsive [SshProfile], or `null` if none respond.
  Future<SshProfile?> findReachableProfile() async {
    final profiles = await _localDbService.getAllProfiles();
    if (profiles.isEmpty) return null;

    final completer = Completer<SshProfile?>();
    var pendingCount = profiles.length;

    for (final profile in profiles) {
      Socket.connect(
        profile.host,
        profile.port,
        timeout: const Duration(milliseconds: 1500),
      ).then((socket) {
        socket.destroy();
        if (!completer.isCompleted) {
          completer.complete(profile);
        }
      }).catchError((_) {
        pendingCount--;
        if (pendingCount == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      });
    }

    return completer.future;
  }

  /// Connects to the remote host using [profile] credentials and returns an [SSHClient].
  Future<SSHClient> _connectClient(SshProfile profile) async {
    final keyPem = await _secureStorageService.getPrivateKey(profile.id) ??
        (profile.privateKeyId.isNotEmpty
            ? await _secureStorageService.getPrivateKey(profile.privateKeyId)
            : null);
    final password = await _secureStorageService.getPassword(profile.id);

    List<SSHKeyPair>? identities;
    if (keyPem != null && keyPem.trim().isNotEmpty) {
      try {
        identities = SSHKeyPair.fromPem(keyPem);
      } catch (_) {
        identities = null;
      }
    }

    final socket = await SSHSocket.connect(
      profile.host,
      profile.port,
      timeout: const Duration(seconds: 10),
    );

    final client = SSHClient(
      socket,
      username: profile.username,
      identities: identities,
      onPasswordRequest: password != null && password.isNotEmpty
          ? () => password
          : null,
    );

    await client.authenticated;
    return client;
  }

  /// Expands leading `~` in [remoteDir] into an absolute path on the remote host.
  Future<String> _resolveRemoteDir(SSHClient client, String remoteDir) async {
    if (remoteDir.startsWith('~/') || remoteDir == '~') {
      try {
        final homeBytes = await client.run('echo \$HOME');
        final home = utf8.decode(homeBytes).trim();
        if (home.isNotEmpty) {
          if (remoteDir == '~') return home;
          return '$home/${remoteDir.substring(2)}';
        }
      } catch (_) {
        // Fall back to original path if echo $HOME fails.
      }
    }
    return remoteDir;
  }

  /// Reads a file from the remote host via SFTP.
  Future<String> _readRemoteFile(SftpClient sftp, String remotePath) async {
    final file = await sftp.open(remotePath, mode: SftpFileOpenMode.read);
    try {
      final bytes = await file.readBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      await file.close();
    }
  }

  final Map<String, DateTime> _recentlyWrittenByApp = <String, DateTime>{};

  /// Writes [content] to a file on the remote host via SFTP.
  Future<void> _writeRemoteFile(
    SftpClient sftp,
    String remotePath,
    String content,
  ) async {
    _recentlyWrittenByApp[p.basename(remotePath)] = DateTime.now();
    final file = await sftp.open(
      remotePath,
      mode: SftpFileOpenMode.create |
          SftpFileOpenMode.truncate |
          SftpFileOpenMode.write,
    );
    try {
      await file.writeBytes(Uint8List.fromList(utf8.encode(content)));
    } finally {
      await file.close();
    }
  }

  /// Executes full bidirectional sync between local notes and the remote laptop Git repo.
  Future<SyncResult> syncAll() async {
    final errors = <String>[];
    SshProfile? profile;
    try {
      profile = await findReachableProfile();
    } catch (e) {
      return SyncResult(
        pulled: 0,
        pushed: 0,
        autoMerged: 0,
        conflicts: 0,
        deleted: 0,
        errors: <String>['Failed to probe reachable profiles: $e'],
        connectedProfile: null,
      );
    }

    if (profile == null) {
      return const SyncResult.empty();
    }

    SSHClient? client;
    SftpClient? sftp;
    var pulled = 0;
    var pushed = 0;
    var autoMerged = 0;
    var conflicts = 0;
    var deleted = 0;
    var remoteHasChanges = false;

    try {
      client = await _connectClient(profile);
      sftp = await client.sftp();
      final remoteDir = await _resolveRemoteDir(client, profile.remoteDir);

      // Ensure remote directory exists
      try {
        await client.run('mkdir -p "$remoteDir"');
      } catch (e) {
        errors.add('Failed to create remote directory: $e');
      }

      // Ensure it is a Git repository and has user config
      try {
        await client.run(
          'cd "$remoteDir" && (git rev-parse --git-dir >/dev/null 2>&1 || git init) && '
          '(git config user.name >/dev/null 2>&1 || git config user.name "Sticky Notes") && '
          '(git config user.email >/dev/null 2>&1 || git config user.email "notes@stickyapp.local")',
        );
      } catch (e) {
        errors.add('Failed to verify or initialize Git repo: $e');
      }

      // Auto-commit any uncommitted laptop changes first
      try {
        await client.run(
          'cd "$remoteDir" && git add -A && (git diff --cached --quiet || git commit -m "Laptop auto-commit \$(date -Iseconds)")',
        );
      } catch (e) {
        errors.add('Failed to auto-commit laptop changes: $e');
      }

      // List remote .md files
      final remoteMdFiles = <String, SftpName>{};
      final remoteConflictFiles = <String, List<String>>{};
      try {
        final remoteEntries = await sftp.listdir(remoteDir);
        for (final entry in remoteEntries) {
          final name = entry.filename;
          if (name.endsWith('.md') && !name.startsWith('.')) {
            if (name.contains('.conflict-')) {
              final conflictIdx = name.indexOf('.conflict-');
              final baseName = '${name.substring(0, conflictIdx)}.md';
              remoteConflictFiles.putIfAbsent(baseName, () => <String>[]).add(name);
            } else {
              remoteMdFiles[name] = entry;
            }
          }
        }
      } catch (e) {
        errors.add('Failed to list remote files via SFTP: $e');
        return SyncResult(
          pulled: pulled,
          pushed: pushed,
          autoMerged: autoMerged,
          conflicts: conflicts,
          deleted: deleted,
          errors: errors,
          connectedProfile: profile.name,
        );
      }

      // List local notes
      final localNotes = await _localDbService.getAllNotes();
      final localNotesMap = <String, StickyNote>{
        for (final note in localNotes) note.filename: note,
      };

      // List base snapshots
      final syncBaseDir = await _localDbService.getSyncBaseDir();
      final baseFilenames = <String>{};
      if (await syncBaseDir.exists()) {
        await for (final entity in syncBaseDir.list()) {
          if (entity is File && entity.path.endsWith('.md')) {
            baseFilenames.add(p.basename(entity.path));
          }
        }
      }

      final allFilenames = <String>{
        ...remoteMdFiles.keys,
        ...localNotesMap.keys,
        ...baseFilenames,
      };

      for (final filename in allFilenames) {
        try {
          final isRemote = remoteMdFiles.containsKey(filename);
          final isLocal = localNotesMap.containsKey(filename);
          final isBase = baseFilenames.contains(filename);

          // Handle deletions
          if (isBase && !isRemote) {
            // Deleted on laptop -> delete locally
            if (isLocal) {
              final localNote = localNotesMap[filename]!;
              await _localDbService.deleteNote(localNote.id);
              await _localDbService.deleteLocalFile(filename);
            }
            await _localDbService.deleteBaseFile(filename);
            deleted++;
            continue;
          }

          if (isBase && !isLocal) {
            // Deleted on phone -> delete remote
            if (isRemote) {
              try {
                _recentlyWrittenByApp[filename] = DateTime.now();
                await sftp.remove('$remoteDir/$filename');
                remoteHasChanges = true;
                deleted++;
              } catch (e) {
                errors.add('Failed to delete remote file $filename: $e');
              }
            }
            await _localDbService.deleteBaseFile(filename);
            continue;
          }

          // Handle new local-only file (push to remote)
          if (isLocal && !isRemote && !isBase) {
            final localNote = localNotesMap[filename]!;
            final content = await _localDbService.readLocalFile(filename) ??
                localNote.content;
            await _writeRemoteFile(sftp, '$remoteDir/$filename', content);
            await _localDbService.writeBaseFile(filename, content);
            await _localDbService.updateNote(
              localNote.copyWith(
                syncStatus: SyncStatus.synced,
                lastSyncedAt: DateTime.now(),
                clearConflict: true,
              ),
            );
            remoteHasChanges = true;
            pushed++;
            continue;
          }

          // Handle new remote-only file (pull to local)
          if (isRemote && !isLocal && !isBase) {
            final content = await _readRemoteFile(sftp, '$remoteDir/$filename');
            await _localDbService.writeLocalFile(filename, content);
            await _localDbService.writeBaseFile(filename, content);
            final title = _deriveTitle(content, filename);
            final now = DateTime.now();
            final newNote = StickyNote(
              id: const Uuid().v4(),
              filename: filename,
              title: title,
              content: content,
              colorIndex: 0,
              isPinned: false,
              tags: const <String>[],
              updatedAt: now,
              createdAt: now,
              syncStatus: SyncStatus.synced,
              lastSyncedAt: now,
            );
            await _localDbService.insertNote(newNote);
            pulled++;
            continue;
          }

          // Both exist: evaluate 3-way resolution
          if (isLocal && isRemote) {
            final localNote = localNotesMap[filename]!;
            final localContent =
                await _localDbService.readLocalFile(filename) ??
                    localNote.content;
            final remoteContent =
                await _readRemoteFile(sftp, '$remoteDir/$filename');
            final baseContent = await _localDbService.readBaseFile(filename);

            // Detect if a prior conflict was resolved on the laptop:
            // Either the PC user deleted the conflict file on PC, or edited the remote file.
            if (localNote.syncStatus == SyncStatus.conflict) {
              final pcHasConflictFile =
                  remoteConflictFiles[filename]?.isNotEmpty ?? false;
              if (!pcHasConflictFile ||
                  (localNote.conflictRemoteContent != null &&
                      remoteContent != localNote.conflictRemoteContent) ||
                  localContent == remoteContent) {
                // Resolved on PC or matching -> adopt remote version cleanly
                await _localDbService.writeLocalFile(filename, remoteContent);
                await _localDbService.writeBaseFile(filename, remoteContent);
                final title = _deriveTitle(remoteContent, filename);
                await _localDbService.updateNote(
                  localNote.copyWith(
                    title: title,
                    content: remoteContent,
                    syncStatus: SyncStatus.synced,
                    lastSyncedAt: DateTime.now(),
                    clearConflict: true,
                  ),
                );
                if (await _cleanupRemoteConflictFiles(
                  sftp,
                  remoteDir,
                  filename,
                  remoteConflictFiles,
                )) {
                  remoteHasChanges = true;
                }
                pulled++;
                continue;
              }
            }

            final resolution = ConflictResolver.resolve(
              base: baseContent,
              local: localContent,
              remote: remoteContent,
            );

            switch (resolution) {
              case AlreadyInSync():
                await _localDbService.writeBaseFile(filename, localContent);
                if (localNote.syncStatus != SyncStatus.synced ||
                    localNote.conflictRemoteContent != null) {
                  await _localDbService.updateNote(
                    localNote.copyWith(
                      syncStatus: SyncStatus.synced,
                      lastSyncedAt: DateTime.now(),
                      clearConflict: true,
                    ),
                  );
                }
                if (await _cleanupRemoteConflictFiles(
                  sftp,
                  remoteDir,
                  filename,
                  remoteConflictFiles,
                )) {
                  remoteHasChanges = true;
                }

              case FastForwardPull(:final content):
                await _localDbService.writeLocalFile(filename, content);
                await _localDbService.writeBaseFile(filename, content);
                final title = _deriveTitle(content, filename);
                await _localDbService.updateNote(
                  localNote.copyWith(
                    title: title,
                    content: content,
                    syncStatus: SyncStatus.synced,
                    lastSyncedAt: DateTime.now(),
                    clearConflict: true,
                  ),
                );
                if (await _cleanupRemoteConflictFiles(
                  sftp,
                  remoteDir,
                  filename,
                  remoteConflictFiles,
                )) {
                  remoteHasChanges = true;
                }
                pulled++;

              case FastForwardPush():
                await _writeRemoteFile(
                  sftp,
                  '$remoteDir/$filename',
                  localContent,
                );
                await _localDbService.writeBaseFile(filename, localContent);
                await _localDbService.updateNote(
                  localNote.copyWith(
                    syncStatus: SyncStatus.synced,
                    lastSyncedAt: DateTime.now(),
                    clearConflict: true,
                  ),
                );
                await _cleanupRemoteConflictFiles(
                  sftp,
                  remoteDir,
                  filename,
                  remoteConflictFiles,
                );
                remoteHasChanges = true;
                pushed++;

              case AutoMerged(:final mergedContent):
                await _writeRemoteFile(sftp, '$remoteDir/$filename', mergedContent);
                await _localDbService.writeLocalFile(filename, mergedContent);
                await _localDbService.writeBaseFile(filename, mergedContent);
                final title = _deriveTitle(mergedContent, filename);
                await _localDbService.updateNote(
                  localNote.copyWith(
                    title: title,
                    content: mergedContent,
                    syncStatus: SyncStatus.synced,
                    lastSyncedAt: DateTime.now(),
                    clearConflict: true,
                  ),
                );
                await _cleanupRemoteConflictFiles(
                  sftp,
                  remoteDir,
                  filename,
                  remoteConflictFiles,
                );
                remoteHasChanges = true;
                autoMerged++;

              case ConflictDetected():
                final conflictFilename =
                    _generateConflictFilename(filename);
                try {
                  final conflictContent = _generateConflictFileContent(
                    filename: filename,
                    laptopContent: remoteContent,
                    phoneContent: localContent,
                  );
                  await _writeRemoteFile(
                    sftp,
                    '$remoteDir/$conflictFilename',
                    conflictContent,
                  );
                  remoteHasChanges = true;
                } catch (e) {
                  errors.add('Failed to write conflict backup $conflictFilename: $e');
                }
                await _localDbService.updateNote(
                  localNote.copyWith(
                    syncStatus: SyncStatus.conflict,
                    conflictRemoteContent: remoteContent,
                  ),
                );
                conflicts++;
            }
          }
        } catch (fileErr) {
          errors.add('Error syncing $filename: $fileErr');
        }
      }

      // Clean up any lingering conflict files on the laptop for notes that are now synced
      for (final entry in remoteConflictFiles.entries) {
        final baseName = entry.key;
        final localNote = localNotesMap[baseName];
        if (localNote != null &&
            localNote.syncStatus == SyncStatus.synced &&
            localNote.conflictRemoteContent == null) {
          for (final file in entry.value) {
            try {
              _recentlyWrittenByApp[file] = DateTime.now();
              await sftp.remove('$remoteDir/$file');
              remoteHasChanges = true;
            } catch (_) {}
          }
        }
      }

      // Step 16: Commit mobile changes on remote Git repository
      if (remoteHasChanges) {
        try {
          await client.run(
            'cd "$remoteDir" && git add -A && (git diff --cached --quiet || git commit -m "Mobile sync \$(date -Iseconds)")',
          );
        } catch (e) {
          errors.add('Failed to commit remote changes via Git: $e');
        }
      }
    } catch (e) {
      errors.add('SSH sync failed: $e');
    } finally {
      try {
        sftp?.close();
      } catch (_) {}
      try {
        client?.close();
      } catch (_) {}
    }

    return SyncResult(
      pulled: pulled,
      pushed: pushed,
      autoMerged: autoMerged,
      conflicts: conflicts,
      deleted: deleted,
      errors: errors,
      connectedProfile: profile.name,
    );
  }

  /// Generates a unique backup filename for quarantined conflict files.
  static String _generateConflictFilename(String filename, [DateTime? time]) {
    final timestamp = (time ?? DateTime.now())
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final baseName = filename.endsWith('.md')
        ? filename.substring(0, filename.length - 3)
        : filename;
    return '$baseName.conflict-$timestamp.md';
  }

  /// Formats a standard Git-style 3-way conflict diff file so PC users can inspect both versions.
  static String _generateConflictFileContent({
    required String filename,
    required String laptopContent,
    required String phoneContent,
  }) {
    return '<<<<<<< LAPTOP (Current ~/sticky-notes/$filename)\n'
        '$laptopContent\n'
        '=======\n'
        '$phoneContent\n'
        '>>>>>>> PHONE (Mobile version)\n';
  }

  /// Removes temporary `.conflict-*.md` backup files from the laptop once a note is in sync.
  Future<bool> _cleanupRemoteConflictFiles(
    SftpClient sftp,
    String remoteDir,
    String filename,
    Map<String, List<String>> remoteConflictFiles,
  ) async {
    final files = remoteConflictFiles[filename];
    var didDelete = false;
    if (files != null && files.isNotEmpty) {
      for (final file in files) {
        try {
          _recentlyWrittenByApp[file] = DateTime.now();
          await sftp.remove('$remoteDir/$file');
          didDelete = true;
        } catch (_) {}
      }
      remoteConflictFiles.remove(filename);
    }
    return didDelete;
  }

  /// Derives a clean note title from the first heading or line of markdown content.
  String _deriveTitle(String content, String filename) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ')) {
        return trimmed.substring(2).trim();
      }
    }
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        return trimmed.length > 50
            ? '${trimmed.substring(0, 47)}...'
            : trimmed;
      }
    }
    return filename.endsWith('.md')
        ? filename.substring(0, filename.length - 3)
        : filename;
  }

  /// Retrieves the remote Git commit log history for [filename].
  Future<List<GitLogEntry>> getGitLog(
    SshProfile profile,
    String filename, {
    int limit = 20,
  }) async {
    SSHClient? client;
    try {
      client = await _connectClient(profile);
      final remoteDir = await _resolveRemoteDir(client, profile.remoteDir);
      final outputBytes = await client.run(
        'cd "$remoteDir" && git log --format="%h|%aI|%s" -n $limit -- "$filename"',
      );
      final output = utf8.decode(outputBytes).trim();
      if (output.isEmpty) return const <GitLogEntry>[];

      final entries = <GitLogEntry>[];
      final lines = output.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final parts = trimmed.split('|');
        if (parts.length >= 3) {
          final hash = parts[0];
          final date = DateTime.tryParse(parts[1]) ?? DateTime.now();
          final message = parts.sublist(2).join('|');
          entries.add(GitLogEntry(hash: hash, date: date, message: message));
        }
      }
      return entries;
    } catch (_) {
      return const <GitLogEntry>[];
    } finally {
      client?.close();
    }
  }

  /// Retrieves the raw content of [filename] at the specified Git [commitHash].
  Future<String> getFileAtCommit(
    SshProfile profile,
    String commitHash,
    String filename,
  ) async {
    SSHClient? client;
    try {
      client = await _connectClient(profile);
      final remoteDir = await _resolveRemoteDir(client, profile.remoteDir);
      final outputBytes = await client.run(
        'cd "$remoteDir" && git show "$commitHash:$filename"',
      );
      return utf8.decode(outputBytes, allowMalformed: true);
    } finally {
      client?.close();
    }
  }

  /// Tests SSH connection, Git availability, and SFTP access for [profile],
  /// returning a diagnostic summary string.
  Future<String> testConnection(SshProfile profile) async {
    SSHClient? client;
    try {
      // 1. TCP socket reachability probe
      final socket = await Socket.connect(
        profile.host,
        profile.port,
        timeout: const Duration(milliseconds: 3000),
      );
      socket.destroy();

      // 2. SSH Client authentication
      client = await _connectClient(profile);

      // 3. Remote Git check
      final gitBytes = await client.run('git --version');
      final gitVersion = utf8.decode(gitBytes).trim();

      // 4. SFTP directory verification
      final sftp = await client.sftp();
      final remoteDir = await _resolveRemoteDir(client, profile.remoteDir);
      await client.run('mkdir -p "$remoteDir"');
      final entries = await sftp.listdir(remoteDir);
      sftp.close();

      return 'Connection successful!\n'
          '• Host: ${profile.host}:${profile.port}\n'
          '• User: ${profile.username}\n'
          '• Git: $gitVersion\n'
          '• Remote Directory: $remoteDir (${entries.length} items found)';
    } catch (e) {
      return 'Connection test failed: $e';
    } finally {
      client?.close();
    }
  }

  /// Builds the shell script to safely and idempotently install a base64-encoded
  /// public key into `~/.ssh/authorized_keys` with strict permissions (700/600).
  static String buildInstallKeyScript(String base64Key) {
    return 'umask 077 && '
        'mkdir -p ~/.ssh && '
        'chmod 700 ~/.ssh && '
        'touch ~/.ssh/authorized_keys && '
        'chmod 600 ~/.ssh/authorized_keys && '
        'K=\$(echo "$base64Key" | base64 -d) && '
        '(grep -q -F "\$K" ~/.ssh/authorized_keys 2>/dev/null || printf "%s\\n" "\$K" >> ~/.ssh/authorized_keys)';
  }

  /// Emulates `ssh-copy-id`: Connects to the host using [password] authentication,
  /// safely appends [publicKeyOpenSsh] to `~/.ssh/authorized_keys` with standard
  /// permissions (700 for ~/.ssh and 600 for authorized_keys), and verifies
  /// that authentication with [privateKeyPem] succeeds immediately afterwards.
  ///
  /// Returns a diagnostic verification summary on success or throws an exception on failure.
  Future<String> installPublicKeyViaPassword({
    required String host,
    required int port,
    required String username,
    required String password,
    required String publicKeyOpenSsh,
    required String privateKeyPem,
    String remoteDir = '~/sticky-notes',
  }) async {
    // 1. Probe TCP socket reachability
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
    } catch (e) {
      throw Exception('Cannot reach host $host:$port via TCP: $e');
    }

    // 2. Connect with password authentication
    SSHClient? passClient;
    try {
      final socket = await SSHSocket.connect(
        host,
        port,
        timeout: const Duration(seconds: 10),
      );
      passClient = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
      );
      await passClient.authenticated.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('SSH password authentication timed out.'),
      );
    } catch (e) {
      passClient?.close();
      throw Exception('Password authentication failed on $username@$host: $e');
    }

    // 3. Install public key to ~/.ssh/authorized_keys
    try {
      final base64Key = base64.encode(utf8.encode(publicKeyOpenSsh.trim()));
      final installScript = buildInstallKeyScript(base64Key);
      await passClient.run(installScript);

      // Also ensure target notes directory exists
      final resolvedDir = await _resolveRemoteDir(passClient, remoteDir);
      await passClient.run('mkdir -p "$resolvedDir"');
    } catch (e) {
      throw Exception('Failed to write authorized_keys on remote host: $e');
    } finally {
      passClient.close();
    }

    // Brief delay to allow SSH daemon to clean up prior session
    await Future<void>.delayed(const Duration(milliseconds: 250));

    // 4. Verify that private key authentication now works directly
    SSHClient? keyClient;
    try {
      final identities = SSHKeyPair.fromPem(privateKeyPem);
      if (identities.isEmpty) {
        throw Exception('Generated private key is empty or invalid.');
      }

      final keySocket = await SSHSocket.connect(
        host,
        port,
        timeout: const Duration(seconds: 10),
      );
      keyClient = SSHClient(
        keySocket,
        username: username,
        identities: identities,
      );
      await keyClient.authenticated.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Key authentication timed out waiting for server response.'),
      );

      // Check remote git
      final gitBytes = await keyClient.run('git --version');
      final gitVersion = utf8.decode(gitBytes).trim();

      return 'Key setup successful (ssh-copy-id completed)!\n'
          '• Host: $host:$port\n'
          '• User: $username\n'
          '• Auth: Public Key Verified (Passwordless)\n'
          '• Git: $gitVersion';
    } catch (e) {
      throw Exception('Key was copied, but private key authentication failed: $e');
    } finally {
      keyClient?.close();
    }
  }

  SSHClient? _watcherClient;
  SSHSession? _watcherSession;
  StreamSubscription<String>? _watcherStdoutSubscription;
  Timer? _watcherDebounceTimer;
  bool _isWatching = false;

  /// Whether the live Linux `inotifywait` file watcher is currently active.
  bool get isWatchingRemote => _isWatching;

  /// Starts listening to remote Linux filesystem events using `inotifywait` over an SSH session.
  ///
  /// Whenever a file is created, modified, or deleted on the laptop, [onRemoteChange] is invoked
  /// with a 500ms debounce to trigger a real-time sync.
  Future<void> startRemoteFileWatcher({
    required void Function() onRemoteChange,
  }) async {
    if (_isWatching) return;

    final profile = await findReachableProfile();
    if (profile == null) return;

    try {
      _watcherClient = await _connectClient(profile);
      final remoteDir = await _resolveRemoteDir(_watcherClient!, profile.remoteDir);

      // Verify inotifywait is available on the remote host
      final checkBytes = await _watcherClient!.run('which inotifywait');
      final whichPath = utf8.decode(checkBytes).trim();
      if (whichPath.isEmpty || !whichPath.contains('inotifywait')) {
        return;
      }

      // Execute inotifywait in continuous monitor mode
      _watcherSession = await _watcherClient!.execute(
        'inotifywait -m -q -e close_write,create,delete,moved_to,moved_from --format "%e %f" "$remoteDir"',
      );

      _isWatching = true;

      _watcherStdoutSubscription = _watcherSession!.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) return;

        final spaceIdx = trimmed.indexOf(' ');
        final filename =
            spaceIdx != -1 ? trimmed.substring(spaceIdx + 1).trim() : trimmed;

        // Ignore git internal files, temp files, and conflict backups
        if (filename.contains('.git') ||
            filename.contains('.conflict-') ||
            !filename.endsWith('.md')) {
          return;
        }

        // Suppress echo events caused by the phone's own SFTP writes
        final writeTime = _recentlyWrittenByApp[filename];
        if (writeTime != null &&
            DateTime.now().difference(writeTime).inSeconds < 3) {
          _recentlyWrittenByApp.remove(filename);
          return;
        }

        // Debounce to batch rapid edits
        _watcherDebounceTimer?.cancel();
        _watcherDebounceTimer = Timer(const Duration(milliseconds: 500), () {
          onRemoteChange();
        });
      }, onDone: () {
        stopRemoteFileWatcher();
      }, onError: (_) {
        stopRemoteFileWatcher();
      });
    } catch (_) {
      stopRemoteFileWatcher();
    }
  }

  /// Stops the active remote `inotifywait` file watcher and cleans up SSH sessions.
  void stopRemoteFileWatcher() {
    _isWatching = false;
    _watcherDebounceTimer?.cancel();
    _watcherStdoutSubscription?.cancel();
    _watcherStdoutSubscription = null;
    try {
      _watcherSession?.close();
    } catch (_) {}
    _watcherSession = null;
    try {
      _watcherClient?.close();
    } catch (_) {}
    _watcherClient = null;
  }
}
