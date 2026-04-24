import 'package:flutter/foundation.dart';

import '../../core/utils/emby_ticks.dart';
import '../../domain/entities/watch_history_item.dart';
import '../../domain/repositories/watch_history_repository.dart';
import '../datasources/emby_watch_history_remote_data_source.dart';
import '../datasources/local_watch_history_data_source.dart';
import '../models/emby/emby_resume_item_dto.dart';
import '../models/playback_record.dart';

class WatchHistoryRepositoryImpl implements WatchHistoryRepository {
  const WatchHistoryRepositoryImpl({
    required EmbyWatchHistoryRemoteDataSource embyRemoteDataSource,
    required LocalWatchHistoryDataSource localDataSource,
  }) : _embyRemoteDataSource = embyRemoteDataSource,
       _localDataSource = localDataSource;

  final EmbyWatchHistoryRemoteDataSource _embyRemoteDataSource;
  final LocalWatchHistoryDataSource _localDataSource;

  @override
  Future<List<WatchHistoryItem>> getUnifiedHistory() async {
    if (kDebugMode) {
      debugPrint('[Diag][WatchHistoryRepository] getUnifiedHistory:start');
    }
    final embyHistory = await getHistoryBySource(WatchSourceType.emby);
    final localHistory = await _loadLocalHistoryForSource(WatchSourceType.local);

    final unifiedHistory = [...embyHistory, ...localHistory]
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    if (kDebugMode) {
      debugPrint(
        '[Diag][WatchHistoryRepository] getUnifiedHistory:success | '
        'embyCount=${embyHistory.length}, '
        'localCount=${localHistory.length}, '
        'unifiedCount=${unifiedHistory.length}',
      );
    }
    return unifiedHistory;
  }

  @override
  Future<List<WatchHistoryItem>> getHistoryBySource(
    WatchSourceType sourceType,
  ) async {
    if (kDebugMode) {
      debugPrint(
        '[Diag][WatchHistoryRepository] getHistoryBySource:start | '
        'sourceType=${sourceType.name}',
      );
    }
    final history = switch (sourceType) {
      WatchSourceType.emby => await _getMergedEmbyHistory(),
      WatchSourceType.local => await _loadLocalHistoryForSource(sourceType),
    };

    history.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    if (kDebugMode) {
      debugPrint(
        '[Diag][WatchHistoryRepository] getHistoryBySource:success | '
        'sourceType=${sourceType.name}, count=${history.length}',
      );
    }
    return history;
  }

  @override
  Future<void> startPlayback(
    WatchHistoryItem item, {
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    await _localDataSource.updateProgress(
      PlaybackRecord.fromWatchHistoryItem(item),
    );
    if (item.sourceType == WatchSourceType.emby) {
      await _embyRemoteDataSource.startPlayback(
        itemId: item.id,
        position: item.position,
        duration: item.duration,
        playSessionId: playSessionId,
        mediaSourceId: mediaSourceId,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      );
    }
  }

  @override
  Future<void> updateProgress(
    WatchHistoryItem item, {
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    await _localDataSource.updateProgress(
      PlaybackRecord.fromWatchHistoryItem(item),
    );
    if (item.sourceType == WatchSourceType.emby) {
      await _embyRemoteDataSource.updateProgress(
        itemId: item.id,
        position: item.position,
        duration: item.duration,
        playSessionId: playSessionId,
        mediaSourceId: mediaSourceId,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      );
    }
  }

  @override
  Future<void> stopPlayback(
    WatchHistoryItem item, {
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    await _localDataSource.updateProgress(
      PlaybackRecord.fromWatchHistoryItem(item),
    );
    if (item.sourceType == WatchSourceType.emby) {
      await _embyRemoteDataSource.stopPlayback(
        itemId: item.id,
        position: item.position,
        duration: item.duration,
        playSessionId: playSessionId,
        mediaSourceId: mediaSourceId,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      );
    }
  }

  WatchHistoryItem _mapEmbyDtoToEntity(EmbyResumeItemDto dto) {
    final updatedAt = dto.lastPlayedDate != null
        ? DateTime.tryParse(dto.lastPlayedDate!) ?? DateTime.now()
        : DateTime.now();
    return WatchHistoryItem(
      id: dto.id,
      title: dto.name,
      poster: dto.posterUrl ?? '',
      position: durationFromEmbyTicks(dto.playbackPositionTicks),
      duration: durationFromEmbyTicks(dto.runTimeTicks),
      updatedAt: updatedAt,
      sourceType: WatchSourceType.emby,
      originalTitle: dto.originalTitle,
      overview: dto.overview,
      backdrop: dto.backdropUrl,
      parentTitle: dto.seriesName,
      year: dto.productionYear,
      seriesId: dto.seriesId,
      parentIndexNumber: dto.parentIndexNumber,
      indexNumber: dto.indexNumber,
    );
  }

  Future<List<WatchHistoryItem>> _fetchEmbyHistory() async {
    if (kDebugMode) {
      debugPrint(
        '[Diag][WatchHistoryRepository] fetchEmbyHistory:start',
      );
    }
    final embyHistory = (await _embyRemoteDataSource.getHistory())
        .map(_mapEmbyDtoToEntity)
        .toList(growable: false);
    if (kDebugMode) {
      debugPrint(
        '[Diag][WatchHistoryRepository] fetchEmbyHistory:success | '
        'count=${embyHistory.length}',
      );
    }
    return embyHistory;
  }

  Future<List<WatchHistoryItem>> _getMergedEmbyHistory() async {
    final localHistory = await _loadLocalHistoryForSource(WatchSourceType.emby);
    try {
      final remoteHistory = await _fetchEmbyHistory();
      final mergedHistory = _mergeHistoryById(
        remoteHistory: remoteHistory,
        localHistory: localHistory,
      );
      await _localDataSource.replaceHistoryForSource(
        WatchSourceType.emby,
        mergedHistory
            .map(PlaybackRecord.fromWatchHistoryItem)
            .toList(growable: false),
      );
      if (kDebugMode) {
        debugPrint(
          '[Diag][WatchHistoryRepository] getMergedEmbyHistory:success | '
          'remoteCount=${remoteHistory.length}, '
          'localCount=${localHistory.length}, '
          'mergedCount=${mergedHistory.length}',
        );
      }
      return mergedHistory;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          '[Diag][WatchHistoryRepository] getMergedEmbyHistory:fallback_local | '
          'localCount=${localHistory.length}, error=$error',
        );
        debugPrint(stackTrace.toString());
      }
      return localHistory;
    }
  }

  Future<List<WatchHistoryItem>> _loadLocalHistoryForSource(
    WatchSourceType sourceType,
  ) async {
    final history = (await _localDataSource.getHistory())
        .map((record) => record.toWatchHistoryItem())
        .where((item) => item.sourceType == sourceType)
        .toList(growable: false);
    if (kDebugMode) {
      debugPrint(
        '[Diag][WatchHistoryRepository] loadLocalHistoryForSource | '
        'sourceType=${sourceType.name}, count=${history.length}',
      );
    }
    return history;
  }

  List<WatchHistoryItem> _mergeHistoryById({
    required List<WatchHistoryItem> remoteHistory,
    required List<WatchHistoryItem> localHistory,
  }) {
    final merged = <String, WatchHistoryItem>{};

    for (final item in remoteHistory) {
      merged[item.uniqueKey] = item;
    }
    for (final item in localHistory) {
      final existing = merged[item.uniqueKey];
      merged[item.uniqueKey] = existing == null
          ? item
          : _mergeHistoryItem(existing, item);
    }

    final result = merged.values.toList(growable: false)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return result;
  }

  WatchHistoryItem _mergeHistoryItem(
    WatchHistoryItem remote,
    WatchHistoryItem local,
  ) {
    final primary = local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
    final secondary = identical(primary, local) ? remote : local;

    return primary.copyWith(
      title: primary.title.isNotEmpty ? primary.title : secondary.title,
      poster: primary.poster.isNotEmpty ? primary.poster : secondary.poster,
      position: primary.position > Duration.zero
          ? primary.position
          : secondary.position,
      duration: primary.duration > Duration.zero
          ? primary.duration
          : secondary.duration,
      updatedAt: primary.updatedAt.isAfter(secondary.updatedAt)
          ? primary.updatedAt
          : secondary.updatedAt,
      originalTitle: primary.originalTitle ?? secondary.originalTitle,
      overview: primary.overview ?? secondary.overview,
      backdrop: primary.backdrop ?? secondary.backdrop,
      parentTitle: primary.parentTitle ?? secondary.parentTitle,
      year: primary.year ?? secondary.year,
      seriesId: primary.seriesId ?? secondary.seriesId,
      parentIndexNumber:
          primary.parentIndexNumber ?? secondary.parentIndexNumber,
      indexNumber: primary.indexNumber ?? secondary.indexNumber,
    );
  }
}
