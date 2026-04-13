import '../../domain/entities/watch_history_item.dart';
import '../../domain/repositories/media_service.dart';

/// 通用的远程数据源适配器
/// 将任何MediaService实现适配为EmbyWatchHistoryRemoteDataSource
class RemoteWatchHistoryDataSourceAdapter
    implements EmbyWatchHistoryRemoteDataSource {
  RemoteWatchHistoryDataSourceAdapter({
    required MediaService mediaService,
  }) : _mediaService = mediaService;

  final MediaService _mediaService;

  @override
  Future<List<WatchHistoryItem>> getHistory() {
    return _mediaService.getWatchHistory();
  }

  @override
  Future<void> updateProgress(WatchHistoryItem item) {
    return _mediaService.updatePlaybackProgress(item);
  }
}

/// 原始的抽象类（保持向后兼容）
abstract class EmbyWatchHistoryRemoteDataSource {
  Future<void> updateProgress(WatchHistoryItem item);

  Future<List<WatchHistoryItem>> getHistory();
}

/// Mock实现（用于开发和测试）
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
