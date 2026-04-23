import '../models/emby/emby_resume_item_dto.dart';
import 'emby_api_client.dart';

/// ✅ 1. 契约层 (Interface)
/// 定义了所有 Emby 远程数据源必须具备的“超能力”
abstract class EmbyWatchHistoryRemoteDataSource {
  /// 获取 Emby 侧的“继续观看”列表
  Future<List<EmbyResumeItemDto>> getHistory();

  /// 通知服务器播放开始
  Future<void> startPlayback({
    required String itemId,
    required Duration position,
    required Duration duration,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  });

  /// 周期性上报播放进度
  Future<void> updateProgress({
    required String itemId,
    required Duration position,
    required Duration duration,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  });

  /// 通知服务器播放停止
  Future<void> stopPlayback({
    required String itemId,
    required Duration position,
    required Duration duration,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  });
}

/// ✅ 2. 正式实现类 (Implementation)
/// 专门负责拿着共享的 ApiClient 去跟 Emby 服务器通信
class EmbyWatchHistoryRemoteDataSourceImpl implements EmbyWatchHistoryRemoteDataSource {
  final EmbyApiClient _apiClient;

  EmbyWatchHistoryRemoteDataSourceImpl({
    required EmbyApiClient apiClient,
  }) : _apiClient = apiClient;

  @override
  Future<List<EmbyResumeItemDto>> getHistory() async {
    return await _apiClient.getRecentWatching();
  }

  @override
  Future<void> startPlayback({
    required String itemId,
    required Duration position,
    required Duration duration,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    await _apiClient.reportPlaybackAction(
      action: PlaybackAction.start,
      itemId: itemId,
      position: position,
      playSessionId: playSessionId,
    );
  }

  @override
  Future<void> updateProgress({
    required String itemId,
    required Duration position,
    required Duration duration,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    await _apiClient.reportPlaybackAction(
      action: PlaybackAction.progress,
      itemId: itemId,
      position: position,
      playSessionId: playSessionId,
    );
  }

  @override
  Future<void> stopPlayback({
    required String itemId,
    required Duration position,
    required Duration duration,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    await _apiClient.reportPlaybackAction(
      action: PlaybackAction.stop,
      itemId: itemId,
      position: position,
      playSessionId: playSessionId,
    );
  }
}

/// ✅ 3. 模拟实现类 (Mock)
/// 用于离线调试或尚未登录时，保证程序不会因为找不到方法而崩溃
class MockEmbyWatchHistoryRemoteDataSource implements EmbyWatchHistoryRemoteDataSource {
  @override
  Future<List<EmbyResumeItemDto>> getHistory() async => const [];

  @override
  Future<void> startPlayback({
    required String itemId, required Duration position, required Duration duration,
    String? playSessionId, String? mediaSourceId, int? audioStreamIndex, int? subtitleStreamIndex,
  }) async {}

  @override
  Future<void> updateProgress({
    required String itemId, required Duration position, required Duration duration,
    String? playSessionId, String? mediaSourceId, int? audioStreamIndex, int? subtitleStreamIndex,
  }) async {}

  @override
  Future<void> stopPlayback({
    required String itemId, required Duration position, required Duration duration,
    String? playSessionId, String? mediaSourceId, int? audioStreamIndex, int? subtitleStreamIndex,
  }) async {}
}