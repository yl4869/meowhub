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
    final embyDtos = await _embyRemoteDataSource.getHistory();
    final embyHistory = embyDtos.map(_mapEmbyDtoToEntity).toList();
    final localHistory = await _localDataSource.getHistory();

    final merged = <String, WatchHistoryItem>{};
    for (final item in embyHistory) {
      merged[item.uniqueKey] = item;
    }
    for (final record in localHistory) {
      final item = record.toWatchHistoryItem();
      final existing = merged[item.uniqueKey];
      if (existing == null || item.updatedAt.isAfter(existing.updatedAt)) {
        merged[item.uniqueKey] = item;
      }
    }

    final unifiedHistory = merged.values.toList(growable: false)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return unifiedHistory;
  }

  @override
  Future<List<WatchHistoryItem>> getHistoryBySource(
    WatchSourceType sourceType,
  ) async {
    final history = switch (sourceType) {
      WatchSourceType.emby =>
        (await _embyRemoteDataSource.getHistory())
            .map(_mapEmbyDtoToEntity)
            .toList(growable: false),
      WatchSourceType.local =>
        (await _localDataSource.getHistory())
            .map((record) => record.toWatchHistoryItem())
            .toList(growable: false),
    };

    history.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return history;
  }

  @override
  Future<void> updateProgress(WatchHistoryItem item) {
    return switch (item.sourceType) {
      WatchSourceType.emby => _embyRemoteDataSource.updateProgress(
        itemId: item.id,
        position: item.position,
      ),
      WatchSourceType.local => _localDataSource.updateProgress(
        PlaybackRecord.fromWatchHistoryItem(item),
      ),
    };
  }

  WatchHistoryItem _mapEmbyDtoToEntity(EmbyResumeItemDto dto) {
    final updatedAt = dto.lastPlayedDate != null
        ? DateTime.tryParse(dto.lastPlayedDate!) ?? DateTime.now()
        : DateTime.now();
    return WatchHistoryItem(
      id: dto.id,
      title: dto.name,
      poster: dto.primaryImageUrl ?? '',
      position: Duration(milliseconds: dto.playbackPositionTicks ~/ 10000),
      duration: Duration(milliseconds: dto.runTimeTicks ~/ 10000),
      updatedAt: updatedAt,
      sourceType: WatchSourceType.emby,
    );
  }
}
