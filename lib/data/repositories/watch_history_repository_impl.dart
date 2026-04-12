import '../../domain/entities/watch_history_item.dart';
import '../../domain/repositories/watch_history_repository.dart';
import '../datasources/emby_watch_history_remote_data_source.dart';
import '../datasources/local_watch_history_data_source.dart';
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
    final embyHistory = await _embyRemoteDataSource.getHistory();
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
  Future<void> updateProgress(WatchHistoryItem item) {
    return switch (item.sourceType) {
      WatchSourceType.emby => _embyRemoteDataSource.updateProgress(item),
      WatchSourceType.local => _localDataSource.updateProgress(
        PlaybackRecord.fromWatchHistoryItem(item),
      ),
    };
  }
}
