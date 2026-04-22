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
    final embyHistory = await _fetchAndCacheEmbyHistory();
    final localHistory = (await _localDataSource.getHistory())
        .map((record) => record.toWatchHistoryItem())
        .where((item) => item.sourceType == WatchSourceType.local)
        .toList(growable: false);

    final unifiedHistory = [...embyHistory, ...localHistory]
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return unifiedHistory;
  }

  @override
  Future<List<WatchHistoryItem>> getHistoryBySource(
    WatchSourceType sourceType,
  ) async {
    final history = switch (sourceType) {
      WatchSourceType.emby => await _fetchAndCacheEmbyHistory(),
      WatchSourceType.local =>
        (await _localDataSource.getHistory())
            .map((record) => record.toWatchHistoryItem())
            .where((item) => item.sourceType == sourceType)
            .toList(growable: false),
    };

    history.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
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
      poster: dto.primaryImageUrl ?? '',
      position: durationFromEmbyTicks(dto.playbackPositionTicks),
      duration: durationFromEmbyTicks(dto.runTimeTicks),
      updatedAt: updatedAt,
      sourceType: WatchSourceType.emby,
      seriesId: dto.seriesId,
      parentIndexNumber: dto.parentIndexNumber,
      indexNumber: dto.indexNumber,
    );
  }

  Future<List<WatchHistoryItem>> _fetchAndCacheEmbyHistory() async {
    final embyHistory = (await _embyRemoteDataSource.getHistory())
        .map(_mapEmbyDtoToEntity)
        .toList(growable: false);
    await _localDataSource.replaceHistoryForSource(
      WatchSourceType.emby,
      embyHistory
          .map(PlaybackRecord.fromWatchHistoryItem)
          .toList(growable: false),
    );
    return embyHistory;
  }
}
