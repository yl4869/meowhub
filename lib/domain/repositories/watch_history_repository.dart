import '../entities/watch_history_item.dart';

abstract class WatchHistoryRepository {
  Future<void> updateProgress(WatchHistoryItem item);

  Future<List<WatchHistoryItem>> getUnifiedHistory();

  Future<List<WatchHistoryItem>> getHistoryBySource(WatchSourceType sourceType);
}
