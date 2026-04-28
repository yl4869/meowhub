import 'package:flutter/foundation.dart';

import '../../core/services/security_service.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/media_service_config.dart';
import '../../domain/entities/playback_plan.dart';
import '../../domain/repositories/i_media_repository.dart';
import '../../domain/repositories/playback_repository.dart';
import '../../domain/repositories/watch_history_repository.dart';
import '../datasources/emby_api_client.dart';
import '../datasources/emby_watch_history_remote_data_source.dart';
import '../datasources/local_media_database.dart';
import '../datasources/local_thumbnail_service.dart';
import '../datasources/local_watch_history_data_source.dart';
import 'emby_media_repository_impl.dart';
import 'emby_playback_repository_impl.dart';
import 'empty_media_repository_impl.dart';
import 'local_media_repository_impl.dart';
import 'local_playback_repository_impl.dart';
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

class MediaRepositoryFactory {
  const MediaRepositoryFactory._();

  static IMediaRepository createMediaRepository({
    MediaServiceConfig? config,
    required SecurityService securityService,
    required LocalWatchHistoryDataSource localWatchHistoryDataSource,
    EmbyApiClient? embyApiClient,
    LocalMediaDatabase? localMediaDatabase,
    LocalThumbnailService? localThumbnailService,
  }) {
    if (config == null) {
      debugPrint('[LocalMedia][Factory] createMediaRepository: config=null -> EmptyMediaRepositoryImpl');
      return const EmptyMediaRepositoryImpl();
    }

    debugPrint('[LocalMedia][Factory] createMediaRepository: type=${config.type.name}, embyApiClient=${embyApiClient != null ? "已注入" : "null"}, localMediaDatabase=${localMediaDatabase != null ? "已注入" : "null"}');

    switch (config.type) {
      case MediaServiceType.emby:
      case MediaServiceType.jellyfin:
        if (embyApiClient != null) {
          debugPrint('[LocalMedia][Factory] -> EmbyMediaRepositoryImpl');
          return EmbyMediaRepositoryImpl(
            apiClient: embyApiClient,
            securityService: securityService,
          );
        }
        debugPrint('[LocalMedia][Factory] ⚠️ emby/jellyfin 类型但 embyApiClient 为 null -> EmptyMediaRepositoryImpl');
        return const EmptyMediaRepositoryImpl();
      case MediaServiceType.local:
        if (localMediaDatabase != null) {
          debugPrint('[LocalMedia][Factory] -> LocalMediaRepositoryImpl');
          return LocalMediaRepositoryImpl(
            database: localMediaDatabase,
            watchHistoryDataSource: localWatchHistoryDataSource,
          );
        }
        debugPrint('[LocalMedia][Factory] ⚠️ local 类型但 localMediaDatabase 为 null -> EmptyMediaRepositoryImpl (数据库未注入, 查询将返回空)');
        return const EmptyMediaRepositoryImpl();
      case MediaServiceType.plex:
        debugPrint('[LocalMedia][Factory] ⚠️ plex 类型不支持 -> EmptyMediaRepositoryImpl');
        return const EmptyMediaRepositoryImpl();
    }
  }

  static PlaybackRepository createPlaybackRepository({
    MediaServiceConfig? config,
    required SecurityService securityService,
    required LocalWatchHistoryDataSource localWatchHistoryDataSource,
    EmbyApiClient? embyApiClient,
    LocalMediaDatabase? localMediaDatabase,
    LocalThumbnailService? localThumbnailService,
  }) {
    if (config == null) {
      debugPrint('[LocalMedia][Factory] createPlaybackRepository: config=null -> UnavailablePlaybackRepository');
      return const UnavailablePlaybackRepository();
    }

    debugPrint('[LocalMedia][Factory] createPlaybackRepository: type=${config.type.name}');
    switch (config.type) {
      case MediaServiceType.emby:
      case MediaServiceType.jellyfin:
        if (embyApiClient != null) {
          debugPrint('[LocalMedia][Factory] -> EmbyPlaybackRepositoryImpl');
          return EmbyPlaybackRepositoryImpl(
            apiClient: embyApiClient,
            securityService: securityService,
          );
        }
        debugPrint('[LocalMedia][Factory] ⚠️ emby/jellyfin 但 embyApiClient 为 null -> UnavailablePlaybackRepository');
        return const UnavailablePlaybackRepository();
      case MediaServiceType.local:
        debugPrint('[LocalMedia][Factory] -> LocalPlaybackRepositoryImpl');
        return const LocalPlaybackRepositoryImpl();
      case MediaServiceType.plex:
        debugPrint('[LocalMedia][Factory] ⚠️ plex 类型不支持 -> UnavailablePlaybackRepository');
        return const UnavailablePlaybackRepository();
    }
  }

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
