import 'package:dio/dio.dart';
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
  }) : _config = config,
       _securityService = securityService,
       _apiClient = EmbyApiClient(
         config: config,
         securityService: securityService,
         sessionExpiredNotifier: sessionExpiredNotifier,
       );

  final MediaServiceConfig _config;
  final SecurityService _securityService;
  final EmbyApiClient _apiClient;

  @override
  Future<List<EmbyResumeItemDto>> getHistory() async {
    final rawUserId = await _securityService.readUserId();
    final userId = rawUserId?.trim() ?? '';
    if (userId.isEmpty) {
      debugPrint(
        '[EmbyHistory] userId is empty, skip requesting /Users/{userId}/Items',
      );
      return const [];
    }

    final path = '/emby/Users/$userId/Items';
    final queryParameters = <String, dynamic>{
      'Recursive': true,
      'MediaTypes': 'Video',
      'SortBy': 'DatePlayed',
      'SortOrder': 'Descending',
      'Filters': 'IsPlayed',
      'EnableUserData': true,
      'EnableImages': true,
      'EnableImageTypes': 'Primary',
      'ImageTypeLimit': 1,
      'Limit': 200,
    };
    final headers = await _buildDebugHeaders();

    debugPrint('[EmbyHistory] baseUrl=${_config.normalizedServerUrl}');
    debugPrint('[EmbyHistory] path=$path');
    debugPrint('[EmbyHistory] queryParameters=$queryParameters');
    debugPrint('[EmbyHistory] headers=$headers');

    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        path,
        queryParameters: queryParameters,
      );
      final data = response.data ?? <String, dynamic>{};
      final items = (data['Items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      return items.map(_parseResumeItem).toList(growable: false);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      debugPrint(
        '[EmbyHistory] DioException status=$statusCode message=${e.message}',
      );
      if (statusCode == 500) {
        debugPrint('[EmbyHistory] 500 response body=${e.response?.data}');
      }
      rethrow;
    }
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

    return EmbyResumeItemDto(
      id: id,
      name: name,
      primaryImageUrl: imageUrl,
      playbackPositionTicks: positionTicks,
      runTimeTicks: runtimeTicks,
      lastPlayedDate: lastPlayedDate,
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

  Future<Map<String, String>> _buildDebugHeaders() async {
    final token = (await _securityService.readAccessToken())?.trim() ?? '';
    final deviceId = _normalizedDeviceId;
    return <String, String>{
      'Content-Type': 'application/json',
      'X-Emby-Authorization':
          'MediaBrowser Client="MeowHub", Device="MeowHub", DeviceId="$deviceId", Version="1.0.0"',
      'X-Emby-Device-Id': deviceId,
      if (token.isNotEmpty) 'X-Emby-Token': token,
    };
  }

  String get _normalizedDeviceId {
    final deviceId = _config.deviceId?.trim();
    if (deviceId == null || deviceId.isEmpty) {
      return 'meowhub-device';
    }
    return deviceId;
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
