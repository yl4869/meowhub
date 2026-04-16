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
  Future<void> updateProgress({
    required String itemId,
    required Duration position,
  }) {
    return _apiClient.updatePlaybackProgress(
      itemId: itemId,
      position: position,
    );
  }

  EmbyResumeItemDto _parseResumeItem(Map<String, dynamic> item) {
    final id = item['Id'] as String? ?? '';
    final name = item['Name'] as String? ?? 'Unknown';
    final imageUrl = _buildImageUrl(item);
    final userData = item['UserData'] as Map<String, dynamic>? ?? {};
    final positionTicks = userData['PlaybackPositionTicks'] as int? ?? 0;
    final runtimeTicks = item['RunTimeTicks'] as int? ?? 0;
    final lastPlayedDate = userData['LastPlayedDate'] as String?;
    final seriesId = item['SeriesId'] as String?;
    final parentIndexNumber = (item['ParentIndexNumber'] as num?)?.toInt();
    final indexNumber = (item['IndexNumber'] as num?)?.toInt();

    return EmbyResumeItemDto(
      id: id,
      name: name,
      primaryImageUrl: imageUrl,
      playbackPositionTicks: positionTicks,
      runTimeTicks: runtimeTicks,
      lastPlayedDate: lastPlayedDate,
      seriesId: seriesId,
      parentIndexNumber: parentIndexNumber,
      indexNumber: indexNumber,
    );
  }

  String _buildImageUrl(Map<String, dynamic> item) {
    final itemId = item['Id'] as String?;
    if (itemId == null) {
      return '';
    }

    final imageTags = item['ImageTags'];
    final imageTag = imageTags is Map ? imageTags['Primary'] as String? : null;
    if (imageTag == null || imageTag.isEmpty) {
      return '';
    }

    return '${_apiClient.serverUrl}/emby/Items/$itemId/Images/Primary?tag=$imageTag&maxHeight=300';
  }
}

abstract class EmbyWatchHistoryRemoteDataSource {
  Future<void> updateProgress({
    required String itemId,
    required Duration position,
  });
  Future<List<EmbyResumeItemDto>> getHistory();
}

/// Mock实现（用于开发和测试）
class MockEmbyWatchHistoryRemoteDataSource
    implements EmbyWatchHistoryRemoteDataSource {
  MockEmbyWatchHistoryRemoteDataSource({
    List<EmbyResumeItemDto> initialHistory = const [],
  }) : _historyById = {for (final item in initialHistory) item.id: item};

  final Map<String, EmbyResumeItemDto> _historyById;

  @override
  Future<List<EmbyResumeItemDto>> getHistory() async {
    return _historyById.values.toList(growable: false);
  }

  @override
  Future<void> updateProgress({
    required String itemId,
    required Duration position,
  }) async {
    final prev = _historyById[itemId];
    _historyById[itemId] = EmbyResumeItemDto(
      id: itemId,
      name: prev?.name ?? 'Unknown',
      primaryImageUrl: prev?.primaryImageUrl,
      playbackPositionTicks: position.inMilliseconds * 10000,
      runTimeTicks: prev?.runTimeTicks ?? 0,
      lastPlayedDate: DateTime.now().toIso8601String(),
    );
  }
}
