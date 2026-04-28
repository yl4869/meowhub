import '../entities/watch_history_item.dart';

abstract class WatchHistoryRepository {
  Future<void> startPlayback(
    WatchHistoryItem item, {
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  });

  Future<void> updateProgress(
    WatchHistoryItem item, {
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  });

  Future<void> stopPlayback(
    WatchHistoryItem item, {
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  });

  Future<List<WatchHistoryItem>> getUnifiedHistory();

  Future<List<WatchHistoryItem>> getHistoryBySource(WatchSourceType sourceType);

  Future<void> clearCachedHistory(WatchSourceType sourceType);
}
