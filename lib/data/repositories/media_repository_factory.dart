import '../../core/services/security_service.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/media_service_config.dart';
import '../../domain/entities/playback_plan.dart';
import '../../domain/repositories/i_media_repository.dart';
import '../../domain/repositories/playback_repository.dart';
import '../../domain/repositories/watch_history_repository.dart';
import '../datasources/emby_api_client.dart';
import '../datasources/emby_watch_history_remote_data_source.dart';
import '../datasources/local_watch_history_data_source.dart';
import 'emby_media_repository_impl.dart';
import 'emby_playback_repository_impl.dart';
import 'empty_media_repository_impl.dart';
import 'watch_history_repository_impl.dart';

class UnavailablePlaybackRepository implements PlaybackRepository {
  const UnavailablePlaybackRepository();

  @override
  Future<PlaybackPlan> getPlaybackPlan(
    MediaItem item, {
    int? maxStreamingBitrate,
    bool? requireAvc,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    String? playSessionId,
    bool preferTranscoding = false,
  }) {
    throw StateError(
      'Playback repository is unavailable for current media service',
    );
  }
}

/// 根据 [MediaServiceConfig] 的类型创建对应的 Repository 实现。
///
/// 当前 Emby 为完整实现，Jellyfin 可复用 Emby API（API 兼容），
/// Plex 和未知类型回退到空实现，后续可扩展。
class MediaRepositoryFactory {
  const MediaRepositoryFactory._();

  /// 创建 [IMediaRepository]
  static IMediaRepository createMediaRepository({
    MediaServiceConfig? config,
    required SecurityService securityService,
    required LocalWatchHistoryDataSource localWatchHistoryDataSource,
    EmbyApiClient? embyApiClient,
  }) {
    if (embyApiClient == null || config == null) {
      return const EmptyMediaRepositoryImpl();
    }

    return switch (config.type) {
      MediaServiceType.emby ||
      MediaServiceType.jellyfin => EmbyMediaRepositoryImpl(
          apiClient: embyApiClient,
          securityService: securityService,
        ),
      MediaServiceType.plex => const EmptyMediaRepositoryImpl(),
    };
  }

  /// 创建 [PlaybackRepository]
  static PlaybackRepository createPlaybackRepository({
    MediaServiceConfig? config,
    required SecurityService securityService,
    required LocalWatchHistoryDataSource localWatchHistoryDataSource,
    EmbyApiClient? embyApiClient,
  }) {
    if (embyApiClient == null || config == null) {
      return const UnavailablePlaybackRepository();
    }

    return switch (config.type) {
      MediaServiceType.emby ||
      MediaServiceType.jellyfin => EmbyPlaybackRepositoryImpl(
          apiClient: embyApiClient,
          securityService: securityService,
        ),
      MediaServiceType.plex => const UnavailablePlaybackRepository(),
    };
  }

  /// 创建 [WatchHistoryRepository]
  static WatchHistoryRepository createWatchHistoryRepository({
    MediaServiceConfig? config,
    required SecurityService securityService,
    required LocalWatchHistoryDataSource localWatchHistoryDataSource,
    EmbyApiClient? embyApiClient,
  }) {
    final EmbyWatchHistoryRemoteDataSource remoteDataSource;
    if (embyApiClient != null &&
        config != null &&
        (config.type == MediaServiceType.emby ||
            config.type == MediaServiceType.jellyfin)) {
      remoteDataSource = EmbyWatchHistoryRemoteDataSourceImpl(
        apiClient: embyApiClient,
      );
    } else {
      remoteDataSource = MockEmbyWatchHistoryRemoteDataSource();
    }

    return WatchHistoryRepositoryImpl(
      embyRemoteDataSource: remoteDataSource,
      localDataSource: localWatchHistoryDataSource,
    );
  }
}
