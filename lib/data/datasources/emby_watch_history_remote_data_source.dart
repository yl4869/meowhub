import '../../core/utils/emby_ticks.dart';
import 'package:flutter/foundation.dart';

import '../../domain/entities/media_service_config.dart';
import '../../core/services/security_service.dart';
import '../../core/session/session_expired_notifier.dart';
import '../models/emby/emby_resume_item_dto.dart';
import 'emby_api_client.dart';

/// 通用的远程数据源适配器
/// 直接通过 Emby API 拉取与回写观看历史，避免额外的 service 包装层。
class EmbyWatchHistoryRemoteDataSourceImpl
    implements EmbyWatchHistoryRemoteDataSource {
  EmbyWatchHistoryRemoteDataSourceImpl({
    required MediaServiceConfig config,
    required SecurityService securityService,
    required SessionExpiredNotifier sessionExpiredNotifier,
  }) : _apiClient = EmbyApiClient(
         config: config,
         securityService: securityService,
         sessionExpiredNotifier: sessionExpiredNotifier,
       );

  final EmbyApiClient _apiClient;

  @override
  Future<List<EmbyResumeItemDto>> getHistory() async {
    final items = await _apiClient.getRecentlyWatchedItems();
    final parsed = items.map(_parseResumeItem).toList(growable: false);
    final firstItem = parsed.isEmpty ? null : parsed.first;
    debugPrint(
      '[Recent][Emby][Parsed] count=${parsed.length} '
      'firstId=${firstItem?.id ?? ''} '
      'firstTitle=${firstItem?.name ?? ''} '
      'firstPosition=${firstItem?.playbackPositionTicks ?? 0}',
    );
    return parsed;
  }

  @override
  Future<void> startPlayback({
    required String itemId,
    required Duration position,
    Duration duration = Duration.zero,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) => _report(PlaybackAction.start, itemId, position, duration, playSessionId, mediaSourceId, audioStreamIndex, subtitleStreamIndex);

  @override
  Future<void> updateProgress({
    required String itemId,
    required Duration position,
    Duration duration = Duration.zero,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) => _report(PlaybackAction.progress, itemId, position, duration, playSessionId, mediaSourceId, audioStreamIndex, subtitleStreamIndex);

  @override
  Future<void> stopPlayback({
    required String itemId,
    required Duration position,
    Duration duration = Duration.zero,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) => _report(PlaybackAction.progress, itemId, position, duration, playSessionId, mediaSourceId, audioStreamIndex, subtitleStreamIndex);

  /// 私有辅助方法，统一调用重构后的 ApiClient
  Future<void> _report(
    PlaybackAction action,
    String itemId,
    Duration position,
    Duration duration,
    String? sessionId,
    String? sourceId,
    int? audioIdx,
    int? subIdx,
  ) {
    return _apiClient.reportPlaybackAction(
      action: action,
      itemId: itemId,
      position: position,
      duration: duration,
      playSessionId: sessionId,
      mediaSourceId: sourceId,
      audioStreamIndex: audioIdx,
      subtitleStreamIndex: subIdx,
    );
  }

  // --- 解析逻辑精简 ---

  EmbyResumeItemDto _parseResumeItem(Map<String, dynamic> item) {
    final userData = item['UserData'] as Map<String, dynamic>? ?? {};

    return EmbyResumeItemDto(
      id: item['Id'] ?? '',
      name: item['Name'] ?? 'Unknown',
      primaryImageUrl: _buildImageUrl(item),
      playbackPositionTicks: userData['PlaybackPositionTicks'] ?? 0,
      runTimeTicks: item['RunTimeTicks'] ?? 0,
      lastPlayedDate: userData['LastPlayedDate'],
      seriesId: item['SeriesId'],
      parentIndexNumber: (item['ParentIndexNumber'] as num?)?.toInt(),
      indexNumber: (item['IndexNumber'] as num?)?.toInt(),
    );
  }

  String _buildImageUrl(Map<String, dynamic> item) {
    final itemId = item['Id'];
    final imageTag = (item['ImageTags'] as Map?)?['Primary'];
    
    if (itemId == null || imageTag == null) return '';

    return '${_apiClient.serverUrl}/emby/Items/$itemId/Images/Primary?tag=$imageTag&maxHeight=300';
  }
}

abstract class EmbyWatchHistoryRemoteDataSource {
  Future<void> startPlayback({
    required String itemId,
    required Duration position,
    Duration duration = Duration.zero,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  });

  Future<void> updateProgress({
    required String itemId,
    required Duration position,
    Duration duration = Duration.zero,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  });

  Future<void> stopPlayback({
    required String itemId,
    required Duration position,
    Duration duration = Duration.zero,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  });

  Future<List<EmbyResumeItemDto>> getHistory();
}

/// Mock实现同步瘦身
class MockEmbyWatchHistoryRemoteDataSource implements EmbyWatchHistoryRemoteDataSource {
  MockEmbyWatchHistoryRemoteDataSource({
    List<EmbyResumeItemDto> initialHistory = const [],
  }) : _historyById = {for (final item in initialHistory) item.id: item};

  final Map<String, EmbyResumeItemDto> _historyById;

  @override
  Future<List<EmbyResumeItemDto>> getHistory() async => _historyById.values.toList(growable: false);

  @override
  Future<void> startPlayback({required String itemId, required Duration position, Duration duration = Duration.zero, String? playSessionId, String? mediaSourceId, int? audioStreamIndex, int? subtitleStreamIndex}) 
    => updateProgress(itemId: itemId, position: position, duration: duration);

  @override
  Future<void> stopPlayback({required String itemId, required Duration position, Duration duration = Duration.zero, String? playSessionId, String? mediaSourceId, int? audioStreamIndex, int? subtitleStreamIndex}) 
    => updateProgress(itemId: itemId, position: position, duration: duration);

  @override
  Future<void> updateProgress({
    required String itemId,
    required Duration position,
    Duration duration = Duration.zero,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    final prev = _historyById[itemId];
    _historyById[itemId] = EmbyResumeItemDto(
      id: itemId,
      name: prev?.name ?? 'Unknown',
      primaryImageUrl: prev?.primaryImageUrl,
      playbackPositionTicks: durationToEmbyTicks(position),
      runTimeTicks: duration > Duration.zero ? durationToEmbyTicks(duration) : (prev?.runTimeTicks ?? 0),
      lastPlayedDate: DateTime.now().toIso8601String(),
    );
  }
}
