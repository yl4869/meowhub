import 'dart:io';

import 'package:flutter/foundation.dart';

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
    debugPrint('[LocalMedia][Repo] getMovies() 调用...');
    final rows = await _database.queryMovies();
    debugPrint('[LocalMedia][Repo] getMovies() 返回: ${rows.length} 条');
    final items = rows.map(_rowToMediaItem).toList(growable: false);
    for (final item in items) {
      debugPrint('[LocalMedia][Repo]   -> id=${item.id}, title="${item.title}", poster=${item.posterUrl != null ? "有" : "无"}');
    }
    return items;
  }

  @override
  Future<List<MediaItem>> getSeries() async {
    debugPrint('[LocalMedia][Repo] getSeries() 调用...');
    final rows = await _database.querySeries();
    debugPrint('[LocalMedia][Repo] getSeries() 返回: ${rows.length} 条');
    return rows.map(_seriesRowToMediaItem).toList(growable: false);
  }

  @override
  Future<MediaItem> getMediaDetail(MediaItem item) async {
    debugPrint('[LocalMedia][Repo] getMediaDetail() id=${item.id}, type=${item.type.name}');
    if (item.type == MediaType.series && item.seriesId == null) {
      final episodes = await getPlayableItems(item);
      return item.copyWith(playableItems: episodes);
    }

    final id = item.sourceId ?? item.dataSourceId;
    debugPrint('[LocalMedia][Repo] getMediaDetail: 查询 sourceId="$id"');
    final row = await _database.getScannedFile(id);
    if (row != null) {
      debugPrint('[LocalMedia][Repo] getMediaDetail: 找到 DB 记录');
      return _rowToMediaItem(row, existingProgress: item.playbackProgress);
    }

    debugPrint('[LocalMedia][Repo] getMediaDetail: 未找到, 回退查询...');
    final allRows = id.isNotEmpty
        ? await _database.queryFiles(limit: 1)
        : <Map<String, dynamic>>[];
    for (final r in allRows) {
      if (LocalFileResolver.stableHash(r['file_path'] as String).toString() ==
          id.toString()) {
        return _rowToMediaItem(r, existingProgress: item.playbackProgress);
      }
    }

    debugPrint('[LocalMedia][Repo] getMediaDetail: 回退也失败, 返回原 item');
    return item;
  }

  @override
  Future<List<MediaItem>> getPlayableItems(MediaItem item) async {
    debugPrint('[LocalMedia][Repo] getPlayableItems() id=${item.id}, type=${item.type.name}');
    if (item.type == MediaType.movie) {
      return [item];
    }

    final seriesId = item.sourceId ?? item.dataSourceId;
    debugPrint('[LocalMedia][Repo] getPlayableItems: 查询系列 "$seriesId" 的剧集');
    final episodes = await _database.queryEpisodes(seriesId);
    debugPrint('[LocalMedia][Repo] getPlayableItems: 找到 ${episodes.length} 集');
    if (episodes.isNotEmpty) {
      return episodes.map(_rowToMediaItem).toList(growable: false);
    }

    return [item];
  }

  @override
  Future<List<MediaItem>> getRecentWatching({int limit = 50}) async {
    debugPrint('[LocalMedia][Repo] getRecentWatching() 返回空 (由 UserDataProvider 交叉引用)');
    return const [];
  }

  @override
  Future<List<MediaLibraryInfo>> getMediaLibraries() async {
    debugPrint('[LocalMedia][Repo] getMediaLibraries() 调用...');
    final folders = await _database.getScanFolders();
    debugPrint('[LocalMedia][Repo] getMediaLibraries: 扫描文件夹=${folders.length} 个');
    if (folders.isEmpty) {
      debugPrint('[LocalMedia][Repo] getMediaLibraries: 返回默认"全部本地视频"库');
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
    debugPrint('[LocalMedia][Repo] getSeasons("$seriesId") 调用...');
    final rows = await _database.querySeasons(seriesId);
    debugPrint('[LocalMedia][Repo] getSeasons: 返回 ${rows.length} 季');
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
    debugPrint('[LocalMedia][Repo] getEpisodesForSeason("$seriesId", S$seasonNumber)');
    final rows = await _database.queryEpisodesForSeason(seriesId, seasonNumber);
    debugPrint('[LocalMedia][Repo] getEpisodesForSeason: 返回 ${rows.length} 集');
    return rows.map(_rowToMediaItem).toList(growable: false);
  }

  @override
  Future<List<MediaItem>> search(String query, {int limit = 50}) async {
    debugPrint('[LocalMedia][Repo] search("$query") 调用...');
    final rows = await _database.search(query, limit: limit);
    debugPrint('[LocalMedia][Repo] search: 返回 ${rows.length} 条');
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
    debugPrint('[LocalMedia][Repo] getItems() libraryId=$libraryId, types=$includeItemTypes');
    final rows = await _database.queryFiles(
      libraryId: libraryId,
      includeItemTypes: includeItemTypes,
      limit: limit,
      startIndex: startIndex,
      sortBy: sortBy,
      sortOrder: sortOrder,
    );
    debugPrint('[LocalMedia][Repo] getItems: 返回 ${rows.length} 条');
    return rows.map(_rowToMediaItem).toList(growable: false);
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
