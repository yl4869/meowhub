import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalMediaDatabase {
  LocalMediaDatabase();

  Database? _db;
  static const _dbVersion = 1;
  static const _dbName = 'meowhub_local_media.db';

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final appDir = await getApplicationSupportDirectory();
    final dbPath = '${appDir.path}/$_dbName';

    return openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE scanned_files (
        id TEXT PRIMARY KEY,
        file_path TEXT NOT NULL UNIQUE,
        file_name TEXT,
        file_size INTEGER,
        mtime INTEGER,
        duration_ms INTEGER,
        width INTEGER,
        height INTEGER,
        media_type TEXT NOT NULL DEFAULT 'movie',
        title TEXT,
        original_title TEXT,
        overview TEXT,
        year INTEGER,
        rating REAL,
        poster_path TEXT,
        backdrop_path TEXT,
        series_id TEXT,
        season_number INTEGER,
        episode_number INTEGER,
        parent_folder TEXT,
        nfo_path TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_scanned_files_series_id ON scanned_files(series_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_scanned_files_media_type ON scanned_files(media_type)
    ''');
    await db.execute('''
      CREATE INDEX idx_scanned_files_parent_folder ON scanned_files(parent_folder)
    ''');

    await db.execute('''
      CREATE TABLE series (
        id TEXT PRIMARY KEY,
        title TEXT,
        original_title TEXT,
        overview TEXT,
        poster_path TEXT,
        backdrop_path TEXT,
        year INTEGER,
        rating REAL,
        folder_path TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE scan_folders (
        path TEXT PRIMARY KEY,
        scanned_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> initialize() async {
    await _database;
    debugPrint('[LocalMedia][DB] 数据库初始化完成');
  }

  // --- Scan folder operations ---

  Future<Map<String, int>> getKnownFiles() async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT file_path, mtime FROM scanned_files',
    );
    return {for (final row in rows) row['file_path'] as String: row['mtime'] as int};
  }

  Future<Map<String, int>> getKnownFilesByFolder(String folderPath) async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT file_path, mtime FROM scanned_files WHERE parent_folder = ?',
      [folderPath],
    );
    return {for (final row in rows) row['file_path'] as String: row['mtime'] as int};
  }

  Future<void> upsertScannedFile(Map<String, dynamic> row) async {
    final db = await _database;
    await db.insert(
      'scanned_files',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertScannedFiles(List<Map<String, dynamic>> rows) async {
    final db = await _database;
    final batch = db.batch();
    for (final row in rows) {
      batch.insert('scanned_files', row, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteScannedFile(String filePath) async {
    final db = await _database;
    await db.delete('scanned_files', where: 'file_path = ?', whereArgs: [filePath]);
  }

  Future<void> deleteScannedFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    final db = await _database;
    final batch = db.batch();
    for (final path in paths) {
      batch.delete('scanned_files', where: 'file_path = ?', whereArgs: [path]);
    }
    await batch.commit(noResult: true);
  }

  // --- Series operations ---

  Future<void> upsertSeries(Map<String, dynamic> row) async {
    final db = await _database;
    await db.insert(
      'series',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- Scan folder operations ---

  Future<void> updateScanFolder(String path, {required int scannedAt}) async {
    final db = await _database;
    await db.insert(
      'scan_folders',
      {'path': path, 'scanned_at': scannedAt},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, int>> getScanFolders() async {
    final db = await _database;
    final rows = await db.rawQuery('SELECT path, scanned_at FROM scan_folders');
    return {for (final row in rows) row['path'] as String: row['scanned_at'] as int};
  }

  // --- Query operations for IMediaRepository ---

  Future<List<Map<String, dynamic>>> queryMovies() async {
    final db = await _database;
    return db.rawQuery(
      "SELECT * FROM scanned_files WHERE media_type = 'movie' ORDER BY title",
    );
  }

  Future<List<Map<String, dynamic>>> querySeries() async {
    final db = await _database;
    return db.rawQuery('SELECT * FROM series ORDER BY title');
  }

  Future<List<Map<String, dynamic>>> queryEpisodes(String seriesId) async {
    final db = await _database;
    return db.rawQuery(
      'SELECT * FROM scanned_files WHERE series_id = ? AND media_type = ? ORDER BY season_number, episode_number',
      [seriesId, 'series'],
    );
  }

  Future<List<Map<String, dynamic>>> queryEpisodesForSeason(
    String seriesId,
    int seasonNumber,
  ) async {
    final db = await _database;
    return db.rawQuery(
      'SELECT * FROM scanned_files WHERE series_id = ? AND season_number = ? AND media_type = ? ORDER BY episode_number',
      [seriesId, seasonNumber, 'series'],
    );
  }

  Future<List<Map<String, dynamic>>> querySeasons(String seriesId) async {
    final db = await _database;
    return db.rawQuery(
      'SELECT DISTINCT season_number, poster_path FROM scanned_files WHERE series_id = ? AND media_type = ? AND season_number IS NOT NULL ORDER BY season_number',
      [seriesId, 'series'],
    );
  }

  Future<List<Map<String, dynamic>>> search(String query, {int limit = 50}) async {
    final db = await _database;
    final pattern = '%$query%';
    return db.rawQuery(
      "SELECT * FROM scanned_files WHERE title LIKE ? OR original_title LIKE ? OR overview LIKE ? OR file_name LIKE ? ORDER BY title LIMIT ?",
      [pattern, pattern, pattern, pattern, limit],
    );
  }

  Future<Map<String, dynamic>?> getScannedFile(String id) async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT * FROM scanned_files WHERE id = ?',
      [id],
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<Map<String, dynamic>?> getSeriesEntry(String id) async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT * FROM series WHERE id = ?',
      [id],
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<List<Map<String, dynamic>>> queryFiles({
    String? libraryId,
    String? includeItemTypes,
    int? limit,
    int? startIndex,
    String? sortBy,
    String? sortOrder,
    bool excludeSeriesEpisodes = false,
  }) async {
    final db = await _database;

    final where = <String>[];
    final whereArgs = <dynamic>[];

    if (libraryId != null && libraryId != 'local-all') {
      where.add('parent_folder LIKE ?');
      whereArgs.add('$libraryId%');
    }

    if (includeItemTypes != null) {
      final types = includeItemTypes.split(',').map((t) => t.trim().toLowerCase()).toList();
      final typePlaceholders = types.map((_) => '?').join(',');
      where.add('media_type IN ($typePlaceholders)');
      whereArgs.addAll(types);
    }

    if (excludeSeriesEpisodes) {
      where.add('series_id IS NULL');
    }

    final whereClause = where.isNotEmpty ? 'WHERE ${where.join(' AND ')}' : '';

    var orderBy = 'ORDER BY title';
    if (sortBy != null) {
      final safeSortBy = _safeColumn(sortBy) ?? 'title';
      final safeSortOrder = (sortOrder?.toUpperCase() == 'DESC' || sortOrder?.toLowerCase() == 'descending') ? 'DESC' : 'ASC';
      orderBy = 'ORDER BY $safeSortBy $safeSortOrder';
    }

    var query = 'SELECT * FROM scanned_files $whereClause $orderBy';
    if (limit != null) {
      query += ' LIMIT ?';
      whereArgs.add(limit);
    }
    if (startIndex != null) {
      query += ' OFFSET ?';
      whereArgs.add(startIndex);
    }

    return db.rawQuery(query, whereArgs);
  }

  Future<List<Map<String, dynamic>>> querySeriesEntries({
    String? libraryId,
    int? limit,
    int? startIndex,
    String? sortBy,
    String? sortOrder,
  }) async {
    final db = await _database;

    final where = <String>[];
    final whereArgs = <dynamic>[];

    if (libraryId != null && libraryId != 'local-all') {
      where.add('folder_path LIKE ?');
      whereArgs.add('$libraryId%');
    }

    final whereClause = where.isNotEmpty ? 'WHERE ${where.join(' AND ')}' : '';

    var orderBy = 'ORDER BY title';
    if (sortBy != null) {
      final safeSortBy = _safeSeriesColumn(sortBy) ?? 'title';
      final safeSortOrder = (sortOrder?.toUpperCase() == 'DESC' || sortOrder?.toLowerCase() == 'descending') ? 'DESC' : 'ASC';
      orderBy = 'ORDER BY $safeSortBy $safeSortOrder';
    }

    var query = 'SELECT * FROM series $whereClause $orderBy';
    if (limit != null) {
      query += ' LIMIT ?';
      whereArgs.add(limit);
    }
    if (startIndex != null) {
      query += ' OFFSET ?';
      whereArgs.add(startIndex);
    }

    return db.rawQuery(query, whereArgs);
  }

  String? _safeColumn(String column) {
    const allowed = {
      'title', 'year', 'rating', 'file_path', 'file_name', 'file_size',
      'mtime', 'duration_ms', 'media_type', 'season_number', 'episode_number',
    };
    // Map Emby-style sort field names to local DB columns
    const aliases = {
      'DateCreated': 'mtime',
      'SortName': 'title',
    };
    final resolved = aliases[column] ?? column;
    return allowed.contains(resolved) ? resolved : null;
  }

  String? _safeSeriesColumn(String column) {
    const allowed = {'title', 'year', 'rating', 'folder_path'};
    const aliases = {
      'DateCreated': 'year',
      'SortName': 'title',
    };
    final resolved = aliases[column] ?? column;
    return allowed.contains(resolved) ? resolved : null;
  }
}
