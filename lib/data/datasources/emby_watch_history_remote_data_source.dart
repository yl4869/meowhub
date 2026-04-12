import '../../domain/entities/watch_history_item.dart';

abstract class EmbyWatchHistoryRemoteDataSource {
  Future<void> updateProgress(WatchHistoryItem item);

  Future<List<WatchHistoryItem>> getHistory();
}

class MockEmbyWatchHistoryRemoteDataSource
    implements EmbyWatchHistoryRemoteDataSource {
  MockEmbyWatchHistoryRemoteDataSource({
    List<WatchHistoryItem> initialHistory = const [],
  }) : _historyById = {
         for (final item in initialHistory) item.id: item,
       };

  final Map<String, WatchHistoryItem> _historyById;

  @override
  Future<List<WatchHistoryItem>> getHistory() async {
    return _historyById.values.toList(growable: false);
  }

  @override
  Future<void> updateProgress(WatchHistoryItem item) async {
    _historyById[item.id] = item.copyWith(updatedAt: DateTime.now());
  }
}
