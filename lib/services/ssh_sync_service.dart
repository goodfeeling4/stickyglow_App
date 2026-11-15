import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
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

/// Parameters passed to the background sync isolate.
class SyncWorkerParams {
  /// Creates a new [SyncWorkerParams] set.
  const SyncWorkerParams({
    required this.profile,
    required this.privateKeyPem,
    required this.notesDirPath,
    required this.syncBaseDirPath,
    required this.localNotes,
  });

  /// SSH connection profile to use.
  final SshProfile profile;

  /// Decrypted private key in PEM format.
  final String? privateKeyPem;

  /// Absolute filesystem path to local working notes directory.
  final String notesDirPath;

  /// Absolute filesystem path to sync base snapshot directory.
  final String syncBaseDirPath;

  /// Snapshot of notes currently present in the local database.
  final List<StickyNote> localNotes;
}

/// Aggregated result returned from the background sync isolate.
class SyncWorkerResult {
  /// Creates a new [SyncWorkerResult].
  const SyncWorkerResult({
    required this.syncResult,
    required this.notesToInsert,
    required this.notesToUpdate,
    required this.noteIdsToDelete,
    required this.recentlyWrittenFiles,
  });

  /// The standard [SyncResult] summary.
  final SyncResult syncResult;

  /// Notes newly discovered on the remote laptop to insert into SQLite.
  final List<StickyNote> notesToInsert;

  /// Existing notes modified, merged, or flagged as conflict to update in SQLite.
  final List<StickyNote> notesToUpdate;

  /// Note IDs deleted on the remote laptop to remove from SQLite.
  final List<String> noteIdsToDelete;

  /// Relative filenames written to or deleted on the laptop during sync,
  /// used to suppress echo events in inotifywait.
  final List<String> recentlyWrittenFiles;
}

/// Background worker function executed in an isolated thread via [compute].
///
/// Handles all SSH/SFTP network I/O, remote shell execution, SHA-256 batch manifest
/// hashing, local disk file updates, and line-level 3-way diff calculations without
/// interrupting the main Flutter UI thread.
@pragma('vm:entry-point')
Future<SyncWorkerResult> _isolateSyncWorker(SyncWorkerParams params) async {
  final profile = params.profile;
  final errors = <String>[];
  var pulled = 0;
  var pushed = 0;
  var autoMerged = 0;
  var conflicts = 0;
  var deleted = 0;
  var remoteHasChanges = false;
  final notesToInsert = <StickyNote>[];
  final notesToUpdate = <StickyNote>[];
  final noteIdsToDelete = <String>[];
  final recentlyWrittenFiles = <String>[];

  SSHClient? client;
  SftpClient? sftp;

  try {
    client = await SshSyncService._connectWithKey(profile, params.privateKeyPem);
    sftp = await client.sftp();
    final remoteMdFiles = <String, String>{};
    final remoteFileFullPaths = <String, String>{};
    final remoteConflictFiles = <String, List<String>>{};
    final configuredDirs = <String>[];
    String primaryRemoteDir = '';

    for (final configuredPath in profile.allRemotePaths) {
      final resolved = await SshSyncService._resolveRemoteDir(client, configuredPath);
      if (resolved.endsWith('.md')) {
        // Individual markdown file
        final parentDir = p.dirname(resolved);
        try {
          await client.run('mkdir -p "$parentDir"');
          final outBytes = await client.run('sha256sum "$resolved" 2>/dev/null || true');
          final outStr = utf8.decode(outBytes).trim();
          if (outStr.isNotEmpty && outStr.length >= 64) {
            final hash = outStr.substring(0, 64).trim();
            final filename = p.basename(resolved);
            remoteMdFiles[filename] = hash;
            remoteFileFullPaths[filename] = resolved;
          }
        } catch (_) {}
      } else {
        // Remote notes directory
        if (primaryRemoteDir.isEmpty) {
          primaryRemoteDir = resolved;
        }
        configuredDirs.add(resolved);

        final batchCommand = 'mkdir -p "$resolved" && '
            'cd "$resolved" && '
            '(git rev-parse --git-dir >/dev/null 2>&1 || git init) && '
            '(git config user.name >/dev/null 2>&1 || git config user.name "Sticky Notes") && '
            '(git config user.email >/dev/null 2>&1 || git config user.email "notes@stickyapp.local") && '
            'git add -A && '
            '(git diff --cached --quiet || git commit -m "Laptop auto-commit \$(date -Iseconds)") && '
            'find . -type f -name "*.md" -not -path "*/.*" -exec sha256sum {} +';

        try {
          final outBytes = await client.run(batchCommand);
          final findOutput = utf8.decode(outBytes, allowMalformed: true);
          for (final rawLine in findOutput.split('\n')) {
            final line = rawLine.trim();
            if (line.isEmpty) continue;
            final spaceIdx = line.indexOf(' ');
            if (spaceIdx < 64) continue;
            final hash = line.substring(0, spaceIdx).trim();
            var filePath = line.substring(spaceIdx + 1).trim();
            if (filePath.startsWith('*')) {
              filePath = filePath.substring(1).trim();
            }
            if (filePath.startsWith('./')) {
              filePath = filePath.substring(2);
            }
            if (p.style == p.Style.windows) {
              filePath = filePath.replaceAll('\\', '/');
            }

            if (filePath.contains('.conflict-')) {
              final conflictIdx = filePath.indexOf('.conflict-');
              final baseName = '${filePath.substring(0, conflictIdx)}.md';
              remoteConflictFiles.putIfAbsent(baseName, () => <String>[]).add(filePath);
            } else if (filePath.endsWith('.md')) {
              remoteMdFiles[filePath] = hash;
              remoteFileFullPaths[filePath] = '$resolved/$filePath';
            }
          }
        } catch (e) {
          errors.add('Failed to execute remote batch command for $resolved: $e');
        }
      }
    }

    if (primaryRemoteDir.isEmpty) {
      primaryRemoteDir = configuredDirs.isNotEmpty
          ? configuredDirs.first
          : await SshSyncService._resolveRemoteDir(client, profile.remoteDir);
    }

    // Map local notes
    final localNotesMap = <String, StickyNote>{
      for (final note in params.localNotes) note.filename: note,
    };

    // Calculate local file hashes from notes directory
    final notesDir = Directory(params.notesDirPath);
    final localFileHashes = <String, String>{};
    if (await notesDir.exists()) {
      await for (final entity in notesDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.md')) {
          var relPath = p.relative(entity.path, from: notesDir.path);
          if (p.style == p.Style.windows) {
            relPath = relPath.replaceAll('\\', '/');
          }
          final bytes = await entity.readAsBytes();
          localFileHashes[relPath] = sha256.convert(bytes).toString();
        }
      }
    }

    // Ensure any note present in database snapshot but missing on disk is saved & hashed
    for (final entry in localNotesMap.entries) {
      if (!localFileHashes.containsKey(entry.key)) {
        final bytes = utf8.encode(entry.value.content);
        localFileHashes[entry.key] = sha256.convert(bytes).toString();
        final f = File(p.join(params.notesDirPath, entry.key));
        if (!f.parent.existsSync()) {
          f.parent.createSync(recursive: true);
        }
        await f.writeAsBytes(bytes, flush: true);
      }
    }

    // Calculate base snapshot hashes from .sync_base directory
    final syncBaseDir = Directory(params.syncBaseDirPath);
    final baseFileHashes = <String, String>{};
    if (await syncBaseDir.exists()) {
      await for (final entity in syncBaseDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.md')) {
          var relPath = p.relative(entity.path, from: syncBaseDir.path);
          if (p.style == p.Style.windows) {
            relPath = relPath.replaceAll('\\', '/');
          }
          final bytes = await entity.readAsBytes();
          baseFileHashes[relPath] = sha256.convert(bytes).toString();
        }
      }
    }

    final allFilenames = <String>{
      ...remoteMdFiles.keys,
      ...localNotesMap.keys,
      ...baseFileHashes.keys,
    };

    final remoteDir = primaryRemoteDir;

    for (final filename in allFilenames) {
      try {
        final isRemote = remoteMdFiles.containsKey(filename);
        final isLocal = localNotesMap.containsKey(filename);
        final isBase = baseFileHashes.containsKey(filename);

        final remoteFilePath = remoteFileFullPaths[filename] ??
            (localNotesMap[filename]?.remotePath != null &&
                    localNotesMap[filename]!.remotePath!.isNotEmpty
                ? localNotesMap[filename]!.remotePath!
                : '$remoteDir/$filename');
        final fileRemoteDir = p.dirname(remoteFilePath);

        final localFile = File(p.join(params.notesDirPath, filename));
        final baseFile = File(p.join(params.syncBaseDirPath, filename));

        // 1. Deletions
        if (isBase && !isRemote) {
          // Deleted on laptop -> delete locally
          if (isLocal) {
            final localNote = localNotesMap[filename]!;
            noteIdsToDelete.add(localNote.id);
            if (await localFile.exists()) {
              await localFile.delete();
            }
          }
          if (await baseFile.exists()) {
            await baseFile.delete();
          }
          deleted++;
          continue;
        }

        if (isBase && !isLocal) {
          // Deleted on phone -> delete on remote
          if (isRemote) {
            try {
              recentlyWrittenFiles.add(filename);
              await sftp.remove(remoteFilePath);
              remoteHasChanges = true;
              deleted++;
            } catch (e) {
              errors.add('Failed to delete remote file $filename: $e');
            }
          }
          if (await baseFile.exists()) {
            await baseFile.delete();
          }
          continue;
        }

        // 2. New local-only note (push to laptop)
        if (isLocal && !isRemote && !isBase) {
          final localNote = localNotesMap[filename]!;
          final content = (await localFile.exists())
              ? await localFile.readAsString()
              : localNote.content;
          await SshSyncService._writeRemoteFile(
            sftp,
            remoteFilePath,
            content,
            client: client,
          );
          recentlyWrittenFiles.add(filename);
          if (!baseFile.parent.existsSync()) {
            await baseFile.parent.create(recursive: true);
          }
          await baseFile.writeAsString(content, flush: true);
          notesToUpdate.add(
            localNote.copyWith(
              profileId: profile.id,
              remotePath: remoteFilePath,
              syncStatus: SyncStatus.synced,
              lastSyncedAt: DateTime.now(),
              clearConflict: true,
            ),
          );
          remoteHasChanges = true;
          pushed++;
          continue;
        }

        // 3. New remote-only note (pull to phone)
        if (isRemote && !isLocal && !isBase) {
          final content = await SshSyncService._readRemoteFile(sftp, remoteFilePath);
          if (!localFile.parent.existsSync()) {
            await localFile.parent.create(recursive: true);
          }
          await localFile.writeAsString(content, flush: true);
          if (!baseFile.parent.existsSync()) {
            await baseFile.parent.create(recursive: true);
          }
          await baseFile.writeAsString(content, flush: true);

          final title = SshSyncService._deriveTitle(content, filename);
          final now = DateTime.now();
          final newNote = StickyNote(
            id: const Uuid().v4(),
            profileId: profile.id,
            remotePath: remoteFilePath,
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
          notesToInsert.add(newNote);
          pulled++;
          continue;
        }

        // 4. Both exist -> Evaluate hashes and 3-way conflict resolution
        if (isLocal && isRemote) {
          final localNote = localNotesMap[filename]!;
          final remoteHash = remoteMdFiles[filename]!;
          final localHash = localFileHashes[filename];
          final baseHash = baseFileHashes[filename];

          // 4a. Already in sync (all hashes match) -> 0 bytes transferred over SFTP!
          if (baseHash != null && remoteHash == baseHash && localHash == baseHash) {
            if (localNote.syncStatus != SyncStatus.synced ||
                localNote.conflictRemoteContent != null) {
              notesToUpdate.add(
                localNote.copyWith(
                  profileId: profile.id,
                  remotePath: remoteFilePath,
                  syncStatus: SyncStatus.synced,
                  lastSyncedAt: DateTime.now(),
                  clearConflict: true,
                ),
              );
            }
            if (await SshSyncService._cleanupRemoteConflictFiles(
              sftp,
              fileRemoteDir,
              filename,
              remoteConflictFiles,
              recentlyWrittenFiles,
            )) {
              remoteHasChanges = true;
            }
            continue;
          }

          // 4b. Local content matches remote content
          if (localHash != null && localHash == remoteHash) {
            final localContent = (await localFile.exists())
                ? await localFile.readAsString()
                : localNote.content;
            if (!baseFile.parent.existsSync()) {
              await baseFile.parent.create(recursive: true);
            }
            await baseFile.writeAsString(localContent, flush: true);
            if (localNote.syncStatus != SyncStatus.synced ||
                localNote.conflictRemoteContent != null) {
              notesToUpdate.add(
                localNote.copyWith(
                  profileId: profile.id,
                  remotePath: remoteFilePath,
                  syncStatus: SyncStatus.synced,
                  lastSyncedAt: DateTime.now(),
                  clearConflict: true,
                ),
              );
            }
            if (await SshSyncService._cleanupRemoteConflictFiles(
              sftp,
              fileRemoteDir,
              filename,
              remoteConflictFiles,
              recentlyWrittenFiles,
            )) {
              remoteHasChanges = true;
            }
            continue;
          }

          // 4c. Fast-Forward Pull (Laptop changed, Phone unchanged)
          if (baseHash != null && localHash == baseHash && remoteHash != baseHash) {
            final remoteContent = await SshSyncService._readRemoteFile(sftp, remoteFilePath);
            if (!localFile.parent.existsSync()) {
              await localFile.parent.create(recursive: true);
            }
            await localFile.writeAsString(remoteContent, flush: true);
            if (!baseFile.parent.existsSync()) {
              await baseFile.parent.create(recursive: true);
            }
            await baseFile.writeAsString(remoteContent, flush: true);
            final title = SshSyncService._deriveTitle(remoteContent, filename);
            notesToUpdate.add(
              localNote.copyWith(
                profileId: profile.id,
                remotePath: remoteFilePath,
                title: title,
                content: remoteContent,
                syncStatus: SyncStatus.synced,
                lastSyncedAt: DateTime.now(),
                clearConflict: true,
              ),
            );
            if (await SshSyncService._cleanupRemoteConflictFiles(
              sftp,
              fileRemoteDir,
              filename,
              remoteConflictFiles,
              recentlyWrittenFiles,
            )) {
              remoteHasChanges = true;
            }
            pulled++;
            continue;
          }

          // 4d. Fast-Forward Push (Phone changed, Laptop unchanged)
          if (baseHash != null && remoteHash == baseHash && localHash != baseHash) {
            final localContent = (await localFile.exists())
                ? await localFile.readAsString()
                : localNote.content;
            await SshSyncService._writeRemoteFile(
              sftp,
              remoteFilePath,
              localContent,
              client: client,
            );
            recentlyWrittenFiles.add(filename);
            if (!baseFile.parent.existsSync()) {
              await baseFile.parent.create(recursive: true);
            }
            await baseFile.writeAsString(localContent, flush: true);
            notesToUpdate.add(
              localNote.copyWith(
                profileId: profile.id,
                remotePath: remoteFilePath,
                syncStatus: SyncStatus.synced,
                lastSyncedAt: DateTime.now(),
                clearConflict: true,
              ),
            );
            await SshSyncService._cleanupRemoteConflictFiles(
              sftp,
              fileRemoteDir,
              filename,
              remoteConflictFiles,
              recentlyWrittenFiles,
            );
            remoteHasChanges = true;
            pushed++;
            continue;
          }

          // 4e. Both modified or un-hashed base -> Read contents and 3-way resolve
          final localContent = (await localFile.exists())
              ? await localFile.readAsString()
              : localNote.content;
          final remoteContent = await SshSyncService._readRemoteFile(sftp, remoteFilePath);
          final baseContent = (await baseFile.exists())
              ? await baseFile.readAsString()
              : null;

          // Check if resolved on laptop
          if (localNote.syncStatus == SyncStatus.conflict) {
            final pcHasConflictFile = remoteConflictFiles[filename]?.isNotEmpty ?? false;
            if (!pcHasConflictFile ||
                (localNote.conflictRemoteContent != null &&
                    remoteContent != localNote.conflictRemoteContent) ||
                localContent == remoteContent) {
              if (!localFile.parent.existsSync()) {
                await localFile.parent.create(recursive: true);
              }
              await localFile.writeAsString(remoteContent, flush: true);
              if (!baseFile.parent.existsSync()) {
                await baseFile.parent.create(recursive: true);
              }
              await baseFile.writeAsString(remoteContent, flush: true);
              final title = SshSyncService._deriveTitle(remoteContent, filename);
              notesToUpdate.add(
                localNote.copyWith(
                  profileId: profile.id,
                  remotePath: remoteFilePath,
                  title: title,
                  content: remoteContent,
                  syncStatus: SyncStatus.synced,
                  lastSyncedAt: DateTime.now(),
                  clearConflict: true,
                ),
              );
              if (await SshSyncService._cleanupRemoteConflictFiles(
                sftp,
                fileRemoteDir,
                filename,
                remoteConflictFiles,
                recentlyWrittenFiles,
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
              if (!baseFile.parent.existsSync()) {
                await baseFile.parent.create(recursive: true);
              }
              await baseFile.writeAsString(localContent, flush: true);
              if (localNote.syncStatus != SyncStatus.synced ||
                  localNote.conflictRemoteContent != null) {
                notesToUpdate.add(
                  localNote.copyWith(
                    profileId: profile.id,
                    remotePath: remoteFilePath,
                    syncStatus: SyncStatus.synced,
                    lastSyncedAt: DateTime.now(),
                    clearConflict: true,
                  ),
                );
              }
              if (await SshSyncService._cleanupRemoteConflictFiles(
                sftp,
                fileRemoteDir,
                filename,
                remoteConflictFiles,
                recentlyWrittenFiles,
              )) {
                remoteHasChanges = true;
              }

            case FastForwardPull(:final content):
              if (!localFile.parent.existsSync()) {
                await localFile.parent.create(recursive: true);
              }
              await localFile.writeAsString(content, flush: true);
              if (!baseFile.parent.existsSync()) {
                await baseFile.parent.create(recursive: true);
              }
              await baseFile.writeAsString(content, flush: true);
              final title = SshSyncService._deriveTitle(content, filename);
              notesToUpdate.add(
                localNote.copyWith(
                  profileId: profile.id,
                  remotePath: remoteFilePath,
                  title: title,
                  content: content,
                  syncStatus: SyncStatus.synced,
                  lastSyncedAt: DateTime.now(),
                  clearConflict: true,
                ),
              );
              if (await SshSyncService._cleanupRemoteConflictFiles(
                sftp,
                fileRemoteDir,
                filename,
                remoteConflictFiles,
                recentlyWrittenFiles,
              )) {
                remoteHasChanges = true;
              }
              pulled++;

            case FastForwardPush():
              await SshSyncService._writeRemoteFile(
                sftp,
                remoteFilePath,
                localContent,
                client: client,
              );
              recentlyWrittenFiles.add(filename);
              if (!baseFile.parent.existsSync()) {
                await baseFile.parent.create(recursive: true);
              }
              await baseFile.writeAsString(localContent, flush: true);
              notesToUpdate.add(
                localNote.copyWith(
                  profileId: profile.id,
                  remotePath: remoteFilePath,
                  syncStatus: SyncStatus.synced,
                  lastSyncedAt: DateTime.now(),
                  clearConflict: true,
                ),
              );
              await SshSyncService._cleanupRemoteConflictFiles(
                sftp,
                fileRemoteDir,
                filename,
                remoteConflictFiles,
                recentlyWrittenFiles,
              );
              remoteHasChanges = true;
              pushed++;

            case AutoMerged(:final mergedContent):
              await SshSyncService._writeRemoteFile(
                sftp,
                remoteFilePath,
                mergedContent,
                client: client,
              );
              recentlyWrittenFiles.add(filename);
              if (!localFile.parent.existsSync()) {
                await localFile.parent.create(recursive: true);
              }
              await localFile.writeAsString(mergedContent, flush: true);
              if (!baseFile.parent.existsSync()) {
                await baseFile.parent.create(recursive: true);
              }
              await baseFile.writeAsString(mergedContent, flush: true);
              final title = SshSyncService._deriveTitle(mergedContent, filename);
              notesToUpdate.add(
                localNote.copyWith(
                  profileId: profile.id,
                  remotePath: remoteFilePath,
                  title: title,
                  content: mergedContent,
                  syncStatus: SyncStatus.synced,
                  lastSyncedAt: DateTime.now(),
                  clearConflict: true,
                ),
              );
              await SshSyncService._cleanupRemoteConflictFiles(
                sftp,
                fileRemoteDir,
                filename,
                remoteConflictFiles,
                recentlyWrittenFiles,
              );
              remoteHasChanges = true;
              autoMerged++;

            case ConflictDetected():
              final conflictFilename = SshSyncService._generateConflictFilename(filename);
              try {
                final conflictContent = SshSyncService._generateConflictFileContent(
                  filename: filename,
                  laptopContent: remoteContent,
                  phoneContent: localContent,
                );
                await SshSyncService._writeRemoteFile(
                  sftp,
                  '$fileRemoteDir/$conflictFilename',
                  conflictContent,
                  client: client,
                );
                recentlyWrittenFiles.add(conflictFilename);
                remoteHasChanges = true;
              } catch (e) {
                errors.add('Failed to write conflict backup $conflictFilename: $e');
              }
              notesToUpdate.add(
                localNote.copyWith(
                  profileId: profile.id,
                  remotePath: remoteFilePath,
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

    // Clean up lingering conflict files on laptop for notes that are synced
    for (final entry in remoteConflictFiles.entries) {
      final baseName = entry.key;
      final localNote = localNotesMap[baseName];
      if (localNote != null &&
          localNote.syncStatus == SyncStatus.synced &&
          localNote.conflictRemoteContent == null) {
        final conflictDir = p.dirname(remoteFileFullPaths[baseName] ?? '$primaryRemoteDir/$baseName');
        for (final file in entry.value) {
          try {
            recentlyWrittenFiles.add(file);
            await sftp.remove('$conflictDir/$file');
            remoteHasChanges = true;
          } catch (_) {}
        }
      }
    }

    // Remote Git commit if phone made changes
    if (remoteHasChanges) {
      for (final dir in configuredDirs) {
        try {
          await client.run(
            'cd "$dir" && git add -A && (git diff --cached --quiet || git commit -m "Mobile sync \$(date -Iseconds)")',
          );
        } catch (e) {
          errors.add('Failed to commit remote changes in $dir via Git: $e');
        }
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

  return SyncWorkerResult(
    syncResult: SyncResult(
      pulled: pulled,
      pushed: pushed,
      autoMerged: autoMerged,
      conflicts: conflicts,
      deleted: deleted,
      errors: errors,
      connectedProfile: profile.name,
    ),
    notesToInsert: notesToInsert,
    notesToUpdate: notesToUpdate,
    noteIdsToDelete: noteIdsToDelete,
    recentlyWrittenFiles: recentlyWrittenFiles,
  );
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

  final Map<String, DateTime> _recentlyWrittenByApp = <String, DateTime>{};

  /// Probes [profile] using a TCP socket with a 1500ms timeout.
  ///
  /// Returns [profile] if responsive, or `null` if unreachable.
  Future<SshProfile?> probeProfile(SshProfile profile) async {
    try {
      final socket = await Socket.connect(
        profile.host,
        profile.port,
        timeout: const Duration(milliseconds: 1500),
      );
      socket.destroy();
      return profile;
    } catch (_) {
      return null;
    }
  }

  /// Retrieves the current active profile selected by the user.
  ///
  /// If no profile is explicitly marked active, defaults to the first profile
  /// in SQLite and persists it as active. Returns `null` if no profiles exist.
  Future<SshProfile?> getActiveProfile() async {
    final activeId = await _secureStorageService.getActiveProfileId();
    if (activeId != null && activeId.isNotEmpty) {
      final profile = await _localDbService.getProfileById(activeId);
      if (profile != null) return profile;
    }
    final all = await _localDbService.getAllProfiles();
    if (all.isEmpty) return null;
    final fallback = all.first;
    await _secureStorageService.saveActiveProfileId(fallback.id);
    return fallback;
  }

  /// Probes ONLY the current active SSH profile.
  ///
  /// Strictly respects user profile selection: if the active profile is
  /// unreachable, returns `null` (offline) and NEVER automatically hops
  /// or probes other machines.
  Future<SshProfile?> findReachableProfile() async {
    final active = await getActiveProfile();
    if (active == null) return null;
    return probeProfile(active);
  }

  /// Connects to the remote host using [profile] and [keyPem], returning an authenticated [SSHClient].
  static Future<SSHClient> _connectWithKey(SshProfile profile, String? keyPem) async {
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
    );

    await client.authenticated;
    return client;
  }

  /// Connects to the remote host using [profile] credentials and returns an [SSHClient].
  Future<SSHClient> _connectClient(SshProfile profile) async {
    final keyPem = await _secureStorageService.getPrivateKey(profile.id);
    return _connectWithKey(profile, keyPem);
  }

  /// Expands leading `~` in [remoteDir] into an absolute path on the remote host.
  static Future<String> _resolveRemoteDir(SSHClient client, String remoteDir) async {
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
  static Future<String> _readRemoteFile(SftpClient sftp, String remotePath) async {
    final file = await sftp.open(remotePath, mode: SftpFileOpenMode.read);
    try {
      final bytes = await file.readBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      await file.close();
    }
  }

  /// Writes [content] to a file on the remote host via SFTP.
  static Future<void> _writeRemoteFile(
    SftpClient sftp,
    String remotePath,
    String content, {
    SSHClient? client,
  }) async {
    if (client != null) {
      final parentDir = p.dirname(remotePath);
      try {
        await client.run('mkdir -p "$parentDir"');
      } catch (_) {}
    }
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

  /// Executes full bidirectional sync between local notes and the remote laptop Git repo
  /// inside a background isolate via [compute], preventing UI frame drops.
  ///
  /// Synchronizes ONLY the active profile (or [profileId] if specified).
  /// If the machine is unreachable, returns an empty result without auto-hopping.
  Future<SyncResult> syncAll({String? profileId}) async {
    SshProfile? profile;
    try {
      if (profileId != null && profileId.isNotEmpty) {
        profile = await _localDbService.getProfileById(profileId);
      } else {
        profile = await getActiveProfile();
      }

      if (profile != null) {
        final reachable = await probeProfile(profile);
        if (reachable == null) {
          // Machine is unreachable: strictly offline, do not jump to other profiles!
          return const SyncResult.empty();
        }
      }
    } catch (e) {
      return SyncResult(
        pulled: 0,
        pushed: 0,
        autoMerged: 0,
        conflicts: 0,
        deleted: 0,
        errors: <String>['Failed to probe active profile: $e'],
        connectedProfile: null,
      );
    }

    if (profile == null) {
      return const SyncResult.empty();
    }

    try {
      await _localDbService.migrateLegacyFilesIfNeeded(profile.id);
      final keyPem = await _secureStorageService.getPrivateKey(profile.id);
      final notesDir = await _localDbService.getNotesDir(profileId: profile.id);
      final syncBaseDir = await _localDbService.getSyncBaseDir(profileId: profile.id);
      final localNotes = await _localDbService.getAllNotes(profileId: profile.id);

      final params = SyncWorkerParams(
        profile: profile,
        privateKeyPem: keyPem,
        notesDirPath: notesDir.path,
        syncBaseDirPath: syncBaseDir.path,
        localNotes: localNotes,
      );

      // Execute entire SSH sync transaction in background worker isolate
      final workerResult = await compute(_isolateSyncWorker, params);

      // Record recently written files on service to suppress inotifywait echo events
      final now = DateTime.now();
      for (final file in workerResult.recentlyWrittenFiles) {
        _recentlyWrittenByApp[file] = now;
        _recentlyWrittenByApp[p.basename(file)] = now;
      }

      // Apply SQLite database transactions cleanly on main isolate ensuring profileId
      for (final note in workerResult.notesToInsert) {
        final toSave = note.profileId.isEmpty
            ? note.copyWith(profileId: profile.id)
            : note;
        await _localDbService.insertNote(toSave);
      }
      for (final note in workerResult.notesToUpdate) {
        final toSave = note.profileId.isEmpty
            ? note.copyWith(profileId: profile.id)
            : note;
        await _localDbService.updateNote(toSave);
      }
      for (final id in workerResult.noteIdsToDelete) {
        await _localDbService.deleteNote(id);
      }

      return workerResult.syncResult;
    } catch (e) {
      return SyncResult(
        pulled: 0,
        pushed: 0,
        autoMerged: 0,
        conflicts: 0,
        deleted: 0,
        errors: <String>['SSH sync isolate error: $e'],
        connectedProfile: profile.name,
      );
    }
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
  static Future<bool> _cleanupRemoteConflictFiles(
    SftpClient sftp,
    String remoteDir,
    String filename,
    Map<String, List<String>> remoteConflictFiles, [
    List<String>? recentlyWrittenFiles,
  ]) async {
    final files = remoteConflictFiles[filename];
    var didDelete = false;
    if (files != null && files.isNotEmpty) {
      for (final file in files) {
        try {
          recentlyWrittenFiles?.add(file);
          await sftp.remove('$remoteDir/$file');
          didDelete = true;
        } catch (_) {}
      }
      remoteConflictFiles.remove(filename);
    }
    return didDelete;
  }

  /// Derives a clean note title from the first heading or line of markdown content.
  static String _deriveTitle(String content, String filename) {
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

      // 4. SFTP paths verification
      final sftp = await client.sftp();
      final pathsSummary = <String>[];
      for (final pth in profile.allRemotePaths) {
        final resolved = await _resolveRemoteDir(client, pth);
        if (resolved.endsWith('.md')) {
          pathsSummary.add('• File: $resolved');
        } else {
          await client.run('mkdir -p "$resolved"');
          final entries = await sftp.listdir(resolved);
          pathsSummary.add('• Dir: $resolved (${entries.length} items found)');
        }
      }
      sftp.close();

      return 'Connection successful!\n'
          '• Host: ${profile.host}:${profile.port}\n'
          '• User: ${profile.username}\n'
          '• Git: $gitVersion\n'
          '${pathsSummary.join('\n')}';
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

  /// Ensures that the remote directories for [profile] exist and have Git initialized,
  /// then triggers an immediate bidirectional sync transaction.
  Future<SyncResult> initializeDirectoryAndSync(SshProfile profile) async {
    SSHClient? client;
    try {
      client = await _connectClient(profile);
      for (final pth in profile.allRemotePaths) {
        final resolved = await _resolveRemoteDir(client, pth);
        final targetDir = resolved.endsWith('.md') ? p.dirname(resolved) : resolved;
        await client.run(
          'mkdir -p "$targetDir" && '
          'cd "$targetDir" && (git rev-parse --git-dir >/dev/null 2>&1 || git init) && '
          '(git config user.name >/dev/null 2>&1 || git config user.name "Sticky Notes") && '
          '(git config user.email >/dev/null 2>&1 || git config user.email "notes@stickyapp.local")',
        );
      }
    } catch (e) {
      debugPrint('Failed to initialize Git directory on remote: $e');
    } finally {
      client?.close();
    }

    return syncAll(profileId: profile.id);
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
  /// Uses kernel-level exclusion for `.git`, `.sync_base`, and temporary conflict files
  /// to eliminate echo loops, with an 800ms debounce to coalesce rapid edits.
  Future<void> startRemoteFileWatcher({
    required void Function() onRemoteChange,
  }) async {
    if (_isWatching) return;

    final profile = await getActiveProfile();
    if (profile == null) return;
    final reachable = await probeProfile(profile);
    if (reachable == null) return;

    try {
      _watcherClient = await _connectClient(profile);
      final remoteDir = await _resolveRemoteDir(_watcherClient!, profile.remoteDir);

      // Verify inotifywait is available on the remote host
      final checkBytes = await _watcherClient!.run('which inotifywait');
      final whichPath = utf8.decode(checkBytes).trim();
      if (whichPath.isEmpty || !whichPath.contains('inotifywait')) {
        return;
      }

      // Execute inotifywait in continuous recursive monitor mode with kernel-level exclusions
      _watcherSession = await _watcherClient!.execute(
        'inotifywait -r -m -q --exclude \'(\\.(git|sync_base|cache)|\\.conflict-)\' -e close_write,create,delete,moved_to,moved_from --format "%e %w%f" "$remoteDir"',
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
        final fullPath =
            spaceIdx != -1 ? trimmed.substring(spaceIdx + 1).trim() : trimmed;

        final relPath = fullPath.startsWith('$remoteDir/')
            ? fullPath.substring(remoteDir.length + 1)
            : p.basename(fullPath);

        // Strictly ignore non-.md files
        if (!relPath.endsWith('.md')) {
          return;
        }

        // Suppress echo events caused by the phone's own SFTP writes
        final writeTime = _recentlyWrittenByApp[relPath] ??
            _recentlyWrittenByApp[p.basename(relPath)];
        if (writeTime != null &&
            DateTime.now().difference(writeTime).inSeconds < 4) {
          _recentlyWrittenByApp.remove(relPath);
          _recentlyWrittenByApp.remove(p.basename(relPath));
          return;
        }

        // Debounce to batch rapid edits
        _watcherDebounceTimer?.cancel();
        _watcherDebounceTimer = Timer(const Duration(milliseconds: 800), () {
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
