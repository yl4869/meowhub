import '../entities/watch_history_item.dart';
import '../entities/media_service_config.dart';
import '../../core/services/security_service.dart';
import '../../core/session/session_expired_notifier.dart';
import '../../data/datasources/emby_api_client.dart';
import '../../data/models/emby_library_response.dart';
import '../../models/media_item.dart';

/// 通用媒体服务接口
/// 所有媒体服务提供商都应实现此接口
abstract class MediaService {
  /// 获取服务配置
  MediaServiceConfig get config;

  /// 验证连接是否有效
  Future<bool> verifyConnection();

  /// 获取观看历史
  Future<List<WatchHistoryItem>> getWatchHistory();

  /// 更新播放进度
  Future<void> updatePlaybackProgress(WatchHistoryItem item);

  /// 获取影片列表
  Future<List<MediaItem>> getMovies();

  /// 获取媒体详情（未来扩展）
  // Future<MediaDetail> getMediaDetail(String mediaId);

  /// 获取推荐内容（未来扩展）
  // Future<List<MediaItem>> getRecommendations();
}

/// 媒体服务工厂 — 根据配置创建相应的服务实现
class MediaServiceFactory {
  static MediaService create(
    MediaServiceConfig config, {
    required SecurityService securityService,
    required SessionExpiredNotifier sessionExpiredNotifier,
  }) {
    return switch (config.type) {
      MediaServiceType.emby => EmbyMediaService(
        config,
        securityService: securityService,
        sessionExpiredNotifier: sessionExpiredNotifier,
      ),
      MediaServiceType.plex => throw UnimplementedError(
        'Plex service not yet implemented',
      ),
      MediaServiceType.jellyfin => throw UnimplementedError(
        'Jellyfin service not yet implemented',
      ),
    };
  }
}

class EmbyMediaService implements MediaService {
  EmbyMediaService(
    this._config, {
    required SecurityService securityService,
    required SessionExpiredNotifier sessionExpiredNotifier,
  }) : _apiClient = EmbyApiClient(
         config: _config,
         securityService: securityService,
         sessionExpiredNotifier: sessionExpiredNotifier,
       ),
       _securityService = securityService;

  final MediaServiceConfig _config;
  final EmbyApiClient _apiClient;
  final SecurityService _securityService;

  @override
  MediaServiceConfig get config => _config;

  @override
  Future<bool> verifyConnection() async {
    try {
      await _apiClient.authenticate();
      await _apiClient.getSystemInfo();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<WatchHistoryItem>> getWatchHistory() async {
    final items = await _apiClient.getResumeItems();
    return items.map(_parseWatchHistoryItem).toList(growable: false);
  }

  @override
  Future<void> updatePlaybackProgress(WatchHistoryItem item) {
    return _apiClient.updatePlaybackProgress(
      itemId: item.id,
      position: item.position,
    );
  }

  @override
  Future<List<MediaItem>> getMovies() async {
    await _apiClient.authenticate();
    final response = await _apiClient.getMovieItems();
    final accessToken = await _securityService.readAccessToken();

    return response.items
        .map((item) => _mapMovieItem(item, accessToken: accessToken))
        .toList(growable: false);
  }

  WatchHistoryItem _parseWatchHistoryItem(Map<String, dynamic> item) {
    final id = item['Id'] as String? ?? '';
    final name = item['Name'] as String? ?? 'Unknown';
    final imageUrl = _buildImageUrl(item);
    final userData = item['UserData'] as Map<String, dynamic>? ?? {};
    final positionTicks = userData['PlaybackPositionTicks'] as int? ?? 0;
    final runtimeTicks = item['RunTimeTicks'] as int? ?? 0;
    final lastPlayedDate = userData['LastPlayedDate'] as String?;

    return WatchHistoryItem(
      id: id,
      title: name,
      poster: imageUrl,
      position: Duration(milliseconds: positionTicks ~/ 10000),
      duration: Duration(milliseconds: runtimeTicks ~/ 10000),
      updatedAt: lastPlayedDate != null
          ? DateTime.parse(lastPlayedDate)
          : DateTime.now(),
      sourceType: WatchSourceType.emby,
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

    return '${_config.normalizedServerUrl}/emby/Items/$itemId/Images/Primary?tag=$imageTag&maxHeight=300';
  }

  MediaItem _mapMovieItem(EmbyMovieItem item, {required String? accessToken}) {
    return MediaItem(
      id: _stableNumericId(item.id),
      sourceId: item.id,
      title: item.name,
      originalTitle: item.name,
      type: MediaType.movie,
      sourceType: WatchSourceType.emby,
      posterUrl: _buildPrimaryImageUrl(item.id, item.imageTags?.primary),
      backdropUrl: _buildBackdropImageUrl(
        item.id,
        item.backdropImageTags.firstOrNull,
      ),
      rating: (item.communityRating ?? 0).toDouble(),
      year: item.productionYear ?? item.premiereDate?.year,
      overview: item.overview ?? '',
      playUrl: _buildPlaybackUrl(item.id, accessToken),
    );
  }

  String? _buildPrimaryImageUrl(String itemId, String? imageTag) {
    if (imageTag == null || imageTag.isEmpty) {
      return null;
    }

    return '${_config.normalizedServerUrl}/emby/Items/$itemId/Images/Primary?tag=$imageTag&maxHeight=720';
  }

  String? _buildBackdropImageUrl(String itemId, String? imageTag) {
    if (imageTag == null || imageTag.isEmpty) {
      return null;
    }

    return '${_config.normalizedServerUrl}/emby/Items/$itemId/Images/Backdrop/0?tag=$imageTag&maxWidth=1280';
  }

  String? _buildPlaybackUrl(String itemId, String? accessToken) {
    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }

    return '${_config.normalizedServerUrl}/emby/Videos/$itemId/stream?Static=true&api_key=$accessToken';
  }

  int _stableNumericId(String value) {
    var hash = 0x811C9DC5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
