import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sticky_notes_ssh/models/ssh_profile.dart';
import 'package:sticky_notes_ssh/models/sticky_note.dart';

/// Service managing SQLite persistence for sticky note metadata and SSH profiles,
/// as well as local file storage for markdown files and sync base snapshots.
class LocalDbService {
  LocalDbService._internal();

  static final LocalDbService _instance = LocalDbService._internal();

  /// Factory constructor returning the singleton instance.
  factory LocalDbService() => _instance;

  static const String _databaseName = 'sticky_notes.db';
  static const int _databaseVersion = 1;

  Database? _database;

  /// Returns the underlying [Database], initializing it if necessary.
  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  /// Sets an explicit [Database] instance, primarily used for automated tests.
  void setDatabaseForTesting(Database? db) {
    _database = db;
  }

  Future<Database> _initDatabase() async {
    final dbDir = await getDatabasesPath();
    final dbPath = p.join(dbDir, _databaseName);

    return openDatabase(
      dbPath,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        filename TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        colorIndex INTEGER NOT NULL DEFAULT 0,
        isPinned INTEGER NOT NULL DEFAULT 0,
        tags TEXT NOT NULL DEFAULT '[]',
        updatedAt TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        syncStatus TEXT NOT NULL DEFAULT 'pending',
        conflictRemoteContent TEXT,
        lastSyncedAt TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE ssh_profiles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        host TEXT NOT NULL,
        port INTEGER NOT NULL DEFAULT 22,
        username TEXT NOT NULL,
        remoteDir TEXT NOT NULL DEFAULT '~/sticky-notes',
        priority INTEGER NOT NULL DEFAULT 0,
        privateKeyId TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_notes_filename ON notes (filename)');
    await db.execute('CREATE INDEX idx_notes_sync_status ON notes (syncStatus)');
    await db.execute('CREATE INDEX idx_notes_is_pinned ON notes (isPinned)');
    await db.execute('CREATE INDEX idx_profiles_priority ON ssh_profiles (priority)');
  }

  // ===========================================================================
  // Sticky Notes CRUD
  // ===========================================================================

  /// Retrieves all notes ordered by pinned status (descending) and last updated (descending).
  Future<List<StickyNote>> getAllNotes() async {
    final db = await database;
    final results = await db.query(
      'notes',
      orderBy: 'isPinned DESC, updatedAt DESC',
    );
    return results.map(StickyNote.fromMap).toList();
  }

  /// Retrieves a single note by its unique [id], or `null` if not found.
  Future<StickyNote?> getNoteById(String id) async {
    final db = await database;
    final results = await db.query(
      'notes',
      where: 'id = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    if (results.isEmpty) {
      return null;
    }
    return StickyNote.fromMap(results.first);
  }

  /// Retrieves a single note by its [filename], or `null` if not found.
  Future<StickyNote?> getNoteByFilename(String filename) async {
    final db = await database;
    final results = await db.query(
      'notes',
      where: 'filename = ?',
      whereArgs: <Object>[filename],
      limit: 1,
    );
    if (results.isEmpty) {
      return null;
    }
    return StickyNote.fromMap(results.first);
  }

  /// Inserts a new [note] or replaces an existing note with the same primary key.
  Future<int> insertNote(StickyNote note) async {
    final db = await database;
    return db.insert(
      'notes',
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Updates an existing [note] matching its `id`.
  Future<int> updateNote(StickyNote note) async {
    final db = await database;
    return db.update(
      'notes',
      note.toMap(),
      where: 'id = ?',
      whereArgs: <Object>[note.id],
    );
  }

  /// Deletes a note by its [id].
  Future<int> deleteNote(String id) async {
    final db = await database;
    return db.delete(
      'notes',
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  /// Retrieves all notes currently flagged with [SyncStatus.conflict].
  Future<List<StickyNote>> getConflictNotes() async {
    final db = await database;
    final results = await db.query(
      'notes',
      where: 'syncStatus = ?',
      whereArgs: <Object>[SyncStatus.conflict.name],
      orderBy: 'updatedAt DESC',
    );
    return results.map(StickyNote.fromMap).toList();
  }

  /// Searches notes whose title or content contains [query], case-insensitively.
  Future<List<StickyNote>> searchNotes(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return getAllNotes();
    }
    final db = await database;
    final pattern = '%$trimmed%';
    final results = await db.query(
      'notes',
      where: 'title LIKE ? OR content LIKE ?',
      whereArgs: <Object>[pattern, pattern],
      orderBy: 'isPinned DESC, updatedAt DESC',
    );
    return results.map(StickyNote.fromMap).toList();
  }

  /// Retrieves notes containing the specified [tag].
  Future<List<StickyNote>> getNotesByTag(String tag) async {
    final db = await database;
    // JSON tags are stored as '["tag1","tag2"]', so match quoted tag.
    final pattern = '%"${tag.replaceAll('"', '')}"%';
    final results = await db.query(
      'notes',
      where: 'tags LIKE ?',
      whereArgs: <Object>[pattern],
      orderBy: 'isPinned DESC, updatedAt DESC',
    );
    return results
        .map(StickyNote.fromMap)
        .where((StickyNote note) => note.tags.contains(tag))
        .toList();
  }

  // ===========================================================================
  // SSH Profiles CRUD
  // ===========================================================================

  /// Retrieves all registered SSH profiles sorted by priority (ascending).
  Future<List<SshProfile>> getAllProfiles() async {
    final db = await database;
    final results = await db.query(
      'ssh_profiles',
      orderBy: 'priority ASC',
    );
    return results.map(SshProfile.fromMap).toList();
  }

  /// Retrieves an SSH profile by its unique [id], or `null` if not found.
  Future<SshProfile?> getProfileById(String id) async {
    final db = await database;
    final results = await db.query(
      'ssh_profiles',
      where: 'id = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    if (results.isEmpty) {
      return null;
    }
    return SshProfile.fromMap(results.first);
  }

  /// Inserts a new [profile] or replaces an existing profile with the same id.
  Future<int> insertProfile(SshProfile profile) async {
    final db = await database;
    return db.insert(
      'ssh_profiles',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Updates an existing [profile] matching its `id`.
  Future<int> updateProfile(SshProfile profile) async {
    final db = await database;
    return db.update(
      'ssh_profiles',
      profile.toMap(),
      where: 'id = ?',
      whereArgs: <Object>[profile.id],
    );
  }

  /// Deletes an SSH profile by its [id].
  Future<int> deleteProfile(String id) async {
    final db = await database;
    return db.delete(
      'ssh_profiles',
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  // ===========================================================================
  // File I/O for Notes & Sync Base
  // ===========================================================================

  /// Returns the local working notes directory (`appDocDir/notes/`),
  /// creating it if it does not already exist.
  Future<Directory> getNotesDir() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final notesDir = Directory(p.join(appDocDir.path, 'notes'));
    if (!await notesDir.exists()) {
      await notesDir.create(recursive: true);
    }
    return notesDir;
  }

  /// Returns the sync base snapshot directory (`appDocDir/.sync_base/`),
  /// creating it if it does not already exist.
  Future<Directory> getSyncBaseDir() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final syncBaseDir = Directory(p.join(appDocDir.path, '.sync_base'));
    if (!await syncBaseDir.exists()) {
      await syncBaseDir.create(recursive: true);
    }
    return syncBaseDir;
  }

  /// Reads the plain markdown text of a local note from `notes/[filename]`.
  /// Returns `null` if the file does not exist.
  Future<String?> readLocalFile(String filename) async {
    final dir = await getNotesDir();
    final file = File(p.join(dir.path, filename));
    if (await file.exists()) {
      return file.readAsString();
    }
    return null;
  }

  /// Writes [content] to `notes/[filename]` as plain markdown.
  Future<File> writeLocalFile(String filename, String content) async {
    final dir = await getNotesDir();
    final file = File(p.join(dir.path, filename));
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    return file.writeAsString(content, flush: true);
  }

  /// Deletes `notes/[filename]` if it exists.
  Future<void> deleteLocalFile(String filename) async {
    final dir = await getNotesDir();
    final file = File(p.join(dir.path, filename));
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Reads the plain markdown text of a base snapshot from `.sync_base/[filename]`.
  /// Returns `null` if the file does not exist.
  Future<String?> readBaseFile(String filename) async {
    final dir = await getSyncBaseDir();
    final file = File(p.join(dir.path, filename));
    if (await file.exists()) {
      return file.readAsString();
    }
    return null;
  }

  /// Writes [content] to `.sync_base/[filename]` as the last known sync baseline.
  Future<File> writeBaseFile(String filename, String content) async {
    final dir = await getSyncBaseDir();
    final file = File(p.join(dir.path, filename));
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    return file.writeAsString(content, flush: true);
  }

  /// Deletes `.sync_base/[filename]` if it exists.
  Future<void> deleteBaseFile(String filename) async {
    final dir = await getSyncBaseDir();
    final file = File(p.join(dir.path, filename));
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Closes the database connection if open.
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
