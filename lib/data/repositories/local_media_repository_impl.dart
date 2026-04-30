import 'dart:io';

import '../../domain/entities/media_item.dart';
import '../../domain/entities/media_library_info.dart';
import '../../domain/entities/season_info.dart';
import '../../domain/entities/watch_history_item.dart';
import '../../domain/repositories/i_media_repository.dart';
import '../datasources/local_media_database.dart';
import '../datasources/local_file_resolver.dart';

class LocalMediaRepositoryImpl implements IMediaRepository {
  LocalMediaRepositoryImpl({
    required LocalMediaDatabase database,
    LocalFileResolver? fileResolver,
  }) : _database = database,
       _fileResolver = fileResolver ?? LocalFileResolver();

  final LocalMediaDatabase _database;
  final LocalFileResolver _fileResolver;

  @override
  Future<List<MediaItem>> getMovies() async {
    final rows = await _database.queryMovies();
    return rows.map(_rowToMediaItem).toList(growable: false);
  }

  @override
  Future<List<MediaItem>> getSeries() async {
    final rows = await _database.querySeries();
    return rows.map(_seriesRowToMediaItem).toList(growable: false);
  }

  @override
  Future<MediaItem> getMediaDetail(MediaItem item) async {
    if (item.type == MediaType.series && item.seriesId == null) {
      final episodes = await getPlayableItems(item);
      return item.copyWith(playableItems: episodes);
    }

    final sourceId = item.sourceId ?? item.dataSourceId;
    final stableId = LocalFileResolver.stableHash(sourceId).toString();
    final row = await _database.getScannedFile(stableId);
    if (row != null) {
      return _rowToMediaItem(row, existingProgress: item.playbackProgress);
    }

    return item;
  }

  @override
  Future<List<MediaItem>> getPlayableItems(MediaItem item) async {
    if (item.type == MediaType.movie) {
      return [item];
    }

    final seriesId = item.sourceId ?? item.dataSourceId;
    final episodes = await _database.queryEpisodes(seriesId);
    if (episodes.isNotEmpty) {
      return episodes.map(_rowToMediaItem).toList(growable: false);
    }

    return [item];
  }

  @override
  Future<List<MediaItem>> getRecentWatching({int limit = 50}) async {
    // Fetch recent standalone movies (no series_id)
    final movieRows = await _database.queryFiles(
      includeItemTypes: 'movie',
      limit: limit,
      sortBy: 'mtime',
      sortOrder: 'DESC',
      excludeSeriesEpisodes: true,
    );
    final movies = movieRows.map((r) => _rowToMediaItem(r)).toList();

    // Fetch recent episodes, consolidate by series
    final episodeRows = await _database.queryFiles(
      includeItemTypes: 'series',
      limit: limit * 3,
      sortBy: 'mtime',
      sortOrder: 'DESC',
    );

    // Group episodes by series_id, pick the most recent per series
    final seriesLatest = <String, Map<String, dynamic>>{};
    for (final row in episodeRows) {
      final sid = row['series_id'] as String?;
      if (sid == null || sid.isEmpty) continue;
      if (!seriesLatest.containsKey(sid) ||
          (row['mtime'] as int) > (seriesLatest[sid]!['mtime'] as int)) {
        seriesLatest[sid] = row;
      }
    }

    // Fetch all series info in one query for resolved series IDs
    Map<String, Map<String, dynamic>> seriesInfoMap = {};
    if (seriesLatest.isNotEmpty) {
      final allSeriesRows = await _database.querySeriesEntries();
      for (final sr in allSeriesRows) {
        seriesInfoMap[sr['id'] as String] = sr;
      }
    }

    // Build series items from series table info + episode poster
    final seriesItems = <MediaItem>[];
    for (final entry in seriesLatest.entries) {
      final epRow = entry.value;
      final seriesRow = seriesInfoMap[entry.key];

      if (seriesRow != null) {
        seriesItems.add(_seriesRowToMediaItem(seriesRow));
      } else {
        final folderPath = entry.key;
        final folderName = folderPath.split(Platform.pathSeparator).last;
        seriesItems.add(MediaItem(
          id: LocalFileResolver.stableHash(folderPath),
          sourceId: folderPath,
          title: folderName,
          originalTitle: '',
          type: MediaType.series,
          sourceType: WatchSourceType.local,
          posterUrl: _fileResolver.posterUrl(epRow),
          year: epRow['year'] as int?,
          overview: '',
          seriesId: entry.key,
        ));
      }
    }

    // Merge and sort by time
    final combined = <MediaItem>[...movies, ...seriesItems];
    combined.sort((a, b) {
      final aTime = a.lastPlayedAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.lastPlayedAt?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });

    return combined.take(limit).toList(growable: false);
  }

  @override
  Future<List<MediaLibraryInfo>> getMediaLibraries() async {
    final folders = await _database.getScanFolders();
    if (folders.isEmpty) {
      return const [
        MediaLibraryInfo(
          id: 'local-all',
          name: '全部本地视频',
          collectionType: 'mixed',
        ),
      ];
    }

    return folders.entries.map((entry) {
      final folderName = entry.key.split(Platform.pathSeparator).last;
      return MediaLibraryInfo(
        id: entry.key,
        name: folderName.isNotEmpty ? folderName : entry.key,
        collectionType: 'mixed',
      );
    }).toList(growable: false);
  }

  @override
  Future<List<SeasonInfo>> getSeasons(String seriesId) async {
    final rows = await _database.querySeasons(seriesId);
    return rows.map((row) {
      final seasonNum = row['season_number'] as int;
      return SeasonInfo(
        id: '${seriesId}_s$seasonNum',
        name: '第 $seasonNum 季',
        seriesId: seriesId,
        indexNumber: seasonNum,
        posterUrl: row['poster_path'] != null
            ? Uri.file(row['poster_path'] as String).toString()
            : null,
      );
    }).toList(growable: false);
  }

  @override
  Future<List<MediaItem>> getEpisodesForSeason(
    String seriesId,
    int seasonNumber,
  ) async {
    final rows = await _database.queryEpisodesForSeason(seriesId, seasonNumber);
    return rows.map(_rowToMediaItem).toList(growable: false);
  }

  @override
  Future<List<MediaItem>> search(String query, {int limit = 50}) async {
    final rows = await _database.search(query, limit: limit);
    return rows.map(_rowToMediaItem).toList(growable: false);
  }

  @override
  Future<List<MediaItem>> getItems({
    String? libraryId,
    String? includeItemTypes,
    int? limit,
    int? startIndex,
    String? sortBy,
    String? sortOrder,
  }) async {
    final types = (includeItemTypes ?? 'Movie,Series')
        .split(',')
        .map((t) => t.trim().toLowerCase())
        .toSet();

    final wantsSeries = types.contains('series');
    final wantsMovies = types.contains('movie');

    List<MediaItem> results = [];

    // Query standalone movies from scanned_files (exclude series episodes)
    if (wantsMovies) {
      final movieRows = await _database.queryFiles(
        libraryId: libraryId,
        includeItemTypes: 'movie',
        sortBy: sortBy,
        sortOrder: sortOrder,
        excludeSeriesEpisodes: true,
      );
      for (final row in movieRows) {
        results.add(_rowToMediaItem(row));
      }
    }

    // Query series from the series table
    if (wantsSeries) {
      final seriesRows = await _database.querySeriesEntries(
        libraryId: libraryId,
        sortBy: sortBy,
        sortOrder: sortOrder,
      );
      for (final row in seriesRows) {
        results.add(_seriesRowToMediaItem(row));
      }
    }

    // Sort combined results
    if (sortBy != null) {
      results.sort((a, b) {
        int cmp;
        switch (sortBy) {
          case 'DateCreated':
          case 'mtime':
            cmp = 0; // series don't have mtime, keep order
            break;
          case 'SortName':
          case 'title':
            cmp = a.title.compareTo(b.title);
            break;
          case 'year':
            cmp = (a.year ?? 0).compareTo(b.year ?? 0);
            break;
          case 'rating':
            cmp = a.rating.compareTo(b.rating);
            break;
          default:
            cmp = a.title.compareTo(b.title);
        }
        return sortOrder?.toUpperCase() == 'DESC' ||
                sortOrder?.toLowerCase() == 'descending'
            ? -cmp
            : cmp;
      });
    }

    // Apply pagination on combined results
    final offset = startIndex ?? 0;
    final end = limit != null ? offset + limit : results.length;
    return results.sublist(offset.clamp(0, results.length), end.clamp(0, results.length));
  }

  // --- Mapping helpers ---

  MediaItem _rowToMediaItem(
    Map<String, dynamic> row, {
    MediaPlaybackProgress? existingProgress,
  }) {
    final filePath = row['file_path'] as String;
    final id = LocalFileResolver.stableHash(filePath);

    return MediaItem(
      id: id,
      sourceId: filePath,
      title: row['title'] as String? ?? LocalFileResolver.titleFromPath(filePath),
      originalTitle: (row['original_title'] as String?) ?? '',
      type: row['media_type'] == 'series'
          ? MediaType.series
          : MediaType.movie,
      sourceType: WatchSourceType.local,
      posterUrl: _fileResolver.posterUrl(row),
      backdropUrl: _fileResolver.backdropUrl(row),
      rating: (row['rating'] as num?)?.toDouble() ?? 0,
      year: row['year'] as int?,
      overview: row['overview'] as String? ?? '',
      playUrl: Uri.file(filePath).toString(),
      seriesId: row['series_id'] as String?,
      indexNumber: row['episode_number'] as int?,
      parentIndexNumber: row['season_number'] as int?,
      playbackProgress: existingProgress,
    );
  }

  MediaItem _seriesRowToMediaItem(Map<String, dynamic> row) {
    final id = row['id'] as String;

    return MediaItem(
      id: LocalFileResolver.stableHash(id),
      sourceId: id,
      title: row['title'] as String,
      originalTitle: (row['original_title'] as String?) ?? '',
      type: MediaType.series,
      sourceType: WatchSourceType.local,
      posterUrl: _fileResolver.posterUrl({
        'poster_path': row['poster_path'],
      }),
      backdropUrl: _fileResolver.backdropUrl({
        'backdrop_path': row['backdrop_path'],
      }),
      rating: (row['rating'] as num?)?.toDouble() ?? 0,
      year: row['year'] as int?,
      overview: row['overview'] as String? ?? '',
      seriesId: id,
    );
  }
}
