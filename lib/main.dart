import 'dart:async';
import 'dart:io';

import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/persistence/file_source_store.dart';
import 'core/services/capability_prober.dart';
import 'core/services/security_service.dart';
import 'core/session/session_expired_notifier.dart';
import 'data/datasources/emby_api_client.dart';
import 'data/datasources/local_media_database.dart';
import 'data/services/storage_permission_service.dart';
import 'data/datasources/local_media_scanner.dart';
import 'data/datasources/local_thumbnail_service.dart';

import 'data/datasources/local_watch_history_data_source.dart';
import 'data/repositories/empty_media_repository_impl.dart';
import 'data/repositories/media_repository_factory.dart';
import 'data/repositories/media_service_manager_impl.dart';
import 'data/repositories/mock_media_repository_impl.dart';
import 'domain/entities/media_item.dart';
import 'domain/entities/media_library_info.dart';
import 'domain/entities/media_service_config.dart';
import 'domain/repositories/i_media_repository.dart';
import 'domain/repositories/i_media_service_manager.dart'; // ✅ 唯一接口
import 'domain/repositories/playback_repository.dart';
import 'domain/repositories/watch_history_repository.dart';
import 'providers/app_provider.dart';

import 'providers/media_detail_provider.dart';
import 'providers/local_media_provider.dart';
import 'providers/media_library_provider.dart';
import 'providers/media_with_user_data_provider.dart';
import 'providers/user_data_provider.dart';
import 'theme/app_theme.dart';
import 'ui/mobile/sample/mobile_ui_sample_view.dart';
import 'ui/responsive/home_view.dart';
import 'ui/responsive/media_detail_view.dart';
import 'ui/responsive/media_library_collection_view.dart';
import 'ui/responsive/player_view.dart';
import 'ui/screens/media_service_config_screen.dart';

const List<Locale> _supportedLocales = [Locale('zh', 'CN'), Locale('en', 'US')];

const String _devicePreviewMode = String.fromEnvironment(
  'DEVICE_PREVIEW',
  defaultValue: 'auto',
);
const bool _useMockRepository = bool.fromEnvironment('USE_MOCK_REPOSITORY');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 基础基础设施初始化
  final preferences = await SharedPreferences.getInstance();
  final securityService = SecurityService(preferences: preferences);
  final sessionExpiredNotifier = SessionExpiredNotifier();
  final capabilityProber = CapabilityProber();
  final fileSourceStore = FileSourceStore();

  // ✅ 在这里创建本地数据源单例，防止被 Provider 频繁重写
  final localWatchHistoryDataSource = InMemoryLocalWatchHistoryDataSource();

  final mediaServiceManager = MediaServiceManagerImpl(preferences: preferences);
  await mediaServiceManager.initialize();

  // 3. 文件源引导逻辑（传入接口类型）
  final fileSourceBootstrap = await _loadFileSourceBootstrap(
    fileSourceStore: fileSourceStore,
    mediaServiceManager: mediaServiceManager,
  );

  // 4. 自动同步配置逻辑
  final selectedServer = fileSourceBootstrap.selectedServer;
  if (selectedServer?.config case final selectedConfig?) {
    final currentConfig = mediaServiceManager.getSavedConfig();
    if (currentConfig?.credentialNamespace !=
        selectedConfig.credentialNamespace) {
      try {
        await mediaServiceManager.setConfig(selectedConfig);
      } catch (error) {
        // Ignore bootstrap sync failures; the saved manager config remains active.
      }
    }
  }

	// 5. 本地媒体数据库初始化
	final localMediaDatabase = LocalMediaDatabase();
	await localMediaDatabase.initialize();
	final localThumbnailService = LocalThumbnailService();

	// 启动时增量扫描
	final selectedConfig = fileSourceBootstrap.selectedServer?.config;
	if (selectedConfig != null &&
	    selectedConfig.type == MediaServiceType.local &&
	    selectedConfig.localPaths.isNotEmpty) {
	  unawaited(_startupIncrementalScan(selectedConfig.localPaths, localMediaDatabase));
	}

  // 6. 启动应用
  runApp(
    DevicePreview(
      enabled: _isDevicePreviewEnabled(),
      defaultDevice: Devices.ios.iPhone13,
      availableLocales: _supportedLocales,
      builder: (context) => MeowHubApp(
        preferences: preferences,
        capabilityProber: capabilityProber,
        securityService: securityService,
        mediaServiceManager: mediaServiceManager,
        fileSourceStore: fileSourceStore,
        initialServers: fileSourceBootstrap.servers,
        initialSelectedServerId: fileSourceBootstrap.selectedServer?.id,
        sessionExpiredNotifier: sessionExpiredNotifier,
        localWatchHistoryDataSource: localWatchHistoryDataSource,
        localMediaDatabase: localMediaDatabase,
        localThumbnailService: localThumbnailService,
      ),
    ),
  );
}

class MeowHubApp extends StatefulWidget {
  const MeowHubApp({
    super.key,
    required this.preferences,
    required this.capabilityProber,
    required this.securityService,
    required this.mediaServiceManager,
    required this.fileSourceStore,
    required this.initialServers,
    required this.initialSelectedServerId,
    required this.sessionExpiredNotifier,
    required this.localWatchHistoryDataSource,
    required this.localMediaDatabase,
    required this.localThumbnailService,
  });

  final SharedPreferences preferences;
  final CapabilityProber capabilityProber;
  final SecurityService securityService;
  final IMediaServiceManager mediaServiceManager;
  final FileSourceStore fileSourceStore;
  final List<MediaServerInfo> initialServers;
  final String? initialSelectedServerId;
  final SessionExpiredNotifier sessionExpiredNotifier;
  final LocalWatchHistoryDataSource localWatchHistoryDataSource;
  final LocalMediaDatabase localMediaDatabase;
  final LocalThumbnailService localThumbnailService;

  @override
  State<MeowHubApp> createState() => _MeowHubAppState();
}

class _MeowHubAppState extends State<MeowHubApp> {
  late final GoRouter _router = GoRouter(
    initialLocation: HomeView.routePath,
    refreshListenable: widget.sessionExpiredNotifier,
    redirect: (context, state) {
      final isLoginRoute =
          state.matchedLocation == MediaServiceConfigScreen.routePath;
      if (widget.sessionExpiredNotifier.requiresLogin && !isLoginRoute) {
        return MediaServiceConfigScreen.routePath;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: MediaServiceConfigScreen.routePath,
        builder: (context, state) => const MediaServiceConfigScreen(),
      ),
      GoRoute(
        path: HomeView.routePath,
        builder: (context, state) => const HomeView(),
      ),
      GoRoute(
        path: MediaDetailView.routePath,
        builder: (context, state) {
          final mediaItem = state.extra;
          if (mediaItem is! MediaItem) {
            return const _RouteErrorView(message: '作品数据丢失，请重新进入。');
          }

          return ChangeNotifierProxyProvider3<
            UserDataProvider,
            PlaybackRepository,
            IMediaRepository,
            MediaDetailProvider
          >(
            create: (context) => MediaDetailProvider(
              playbackRepository: context.read<PlaybackRepository>(),
              userDataProvider: context.read<UserDataProvider>(),
              mediaRepository: context.read<IMediaRepository>(),
            ),
            update: (context, userData, playback, mediaRepo, previous) {
              final provider =
                  previous ??
                  MediaDetailProvider(
                    userDataProvider: userData,
                    playbackRepository: playback,
                    mediaRepository: mediaRepo,
                  );
              provider.updateDependencies(
                userDataProvider: userData,
                playbackRepository: playback,
                mediaRepository: mediaRepo,
              );
              return provider;
            },
            child: MediaDetailView(mediaItem: mediaItem),
          );
        },
      ),
      GoRoute(
        path: MediaLibraryCollectionView.routePath,
        builder: (context, state) {
          final libraryInfo = state.extra;
          if (libraryInfo is! MediaLibraryInfo) {
            return const _RouteErrorView(message: '媒体库数据丢失，请重新进入。');
          }
          return MediaLibraryCollectionView(libraryInfo: libraryInfo);
        },
      ),
      GoRoute(
        path: PlayerView.routePath,
        builder: (context, state) {
          final payload = state.extra;
          if (payload is PlayerViewRoutePayload) {
            return PlayerView(
              mediaItem: payload.mediaItem,
              initialPlaybackPlan: payload.initialPlaybackPlan,
            );
          }
          if (payload is! MediaItem) {
            return const _RouteErrorView(message: '播放数据丢失，请重新进入。');
          }
          return PlayerView(mediaItem: payload);
        },
      ),
      GoRoute(
        path: MobileUiSampleView.routePath,
        builder: (context, state) => const MobileUiSampleView(),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppProvider(
            mediaServiceManager: widget.mediaServiceManager,
            fileSourceStore: widget.fileSourceStore,
            initialServers: widget.initialServers,
            initialSelectedServerId: widget.initialSelectedServerId,
          ),
        ),
        // ✅ 注入接口
        // ✅ 修改点：Manager 变回普通的 Provider (因为它现在只负责存取，不负责喊话)
        Provider<IMediaServiceManager>.value(value: widget.mediaServiceManager),
        Provider<MediaConfigValidator>.value(
          value: _buildMediaConfigValidator(
            securityService: widget.securityService,
            sessionExpiredNotifier: widget.sessionExpiredNotifier,
          ),
        ),
        Provider<SecurityService>.value(value: widget.securityService),
        ChangeNotifierProvider<CapabilityProber>.value(
          value: widget.capabilityProber,
        ),
        ChangeNotifierProvider<SessionExpiredNotifier>.value(
          value: widget.sessionExpiredNotifier,
        ),

        // 1. 核心单例：共享 ApiClient
        // 找到 EmbyApiClient 的 ProxyProvider
        ProxyProvider4<
          AppProvider,
          SecurityService,
          SessionExpiredNotifier,
          CapabilityProber,
          EmbyApiClient?
        >(
          update: (context, appProvider, security, notifier, prober, previous) {
            // 💡 重点：现在我们直接从 appProvider 拿配置
            // 只要 AppProvider 因为 Stream 变动而 notifyListeners，这里就会触发更新
            final config = appProvider.selectedServer.config;

            if (config == null ||
                (config.type != MediaServiceType.emby &&
                    config.type != MediaServiceType.jellyfin)) {
              return null;
            }

            // 只有配置真的变了才重刷，避免不必要的网络请求重启
            if (previous?.config == config) return previous;

            return EmbyApiClient(
              config: config,
              securityService: security,
              sessionExpiredNotifier: notifier,
              capabilityProber: prober,
            );
          },
        ),

        // 2. 仓库工厂：根据当前配置类型创建对应的 Repository 实现
        ProxyProvider3<
          AppProvider,
          EmbyApiClient?,
          SecurityService,
          IMediaRepository
        >(
          update: (context, appProvider, apiClient, security, _) {
            final config = appProvider.selectedServer.config;
            debugPrint('[LocalMedia][main] ProxyProvider<IMediaRepository> 更新: config=${config?.type.name ?? "null"}');
            if (config == null) {
              debugPrint('[LocalMedia][main] -> config 为 null, 返回 EmptyMediaRepositoryImpl');
              return const EmptyMediaRepositoryImpl();
            }
            if (_useMockRepository) {
              debugPrint('[LocalMedia][main] -> USE_MOCK_REPOSITORY=true, 返回 MockMediaRepositoryImpl');
              return const MockMediaRepositoryImpl();
            }

            debugPrint('[LocalMedia][main] -> 调用工厂, localMediaDatabase=已注入');
            return MediaRepositoryFactory.createMediaRepository(
              config: config,
              securityService: security,
              localWatchHistoryDataSource:
                  widget.localWatchHistoryDataSource,
              embyApiClient: apiClient,
              localMediaDatabase: widget.localMediaDatabase,
              localThumbnailService: widget.localThumbnailService,
            );
          },
        ),
        ProxyProvider3<
          AppProvider,
          EmbyApiClient?,
          SecurityService,
          PlaybackRepository
        >(
          update: (context, appProvider, apiClient, security, _) {
            final config = appProvider.selectedServer.config;
            if (config == null) return const UnavailablePlaybackRepository();

            return MediaRepositoryFactory.createPlaybackRepository(
              config: config,
              securityService: security,
              localWatchHistoryDataSource:
                  widget.localWatchHistoryDataSource,
              embyApiClient: apiClient,
              localMediaDatabase: widget.localMediaDatabase,
              localThumbnailService: widget.localThumbnailService,
            );
          },
        ),
        ProxyProvider2<AppProvider, EmbyApiClient?, WatchHistoryRepository>(
          update: (context, appProvider, apiClient, _) {
            final config = appProvider.selectedServer.config;
            return MediaRepositoryFactory.createWatchHistoryRepository(
              config: config,
              securityService: widget.securityService,
              localWatchHistoryDataSource:
                  widget.localWatchHistoryDataSource,
              embyApiClient: apiClient,
            );
          },
        ),

        // 本地媒体服务
        Provider<LocalMediaDatabase>.value(value: widget.localMediaDatabase),
        Provider<LocalThumbnailService>.value(value: widget.localThumbnailService),
        ChangeNotifierProvider<LocalMediaProvider>(
          create: (_) => LocalMediaProvider(database: widget.localMediaDatabase),
        ),

        // 3. 用户进度管理
        ChangeNotifierProxyProvider2<
          IMediaServiceManager,
          WatchHistoryRepository,
          UserDataProvider
        >(
          create: (context) => UserDataProvider(
            mediaServiceManager: context.read<IMediaServiceManager>(),
            watchHistoryRepository: context.read<WatchHistoryRepository>(),
          ),
          update: (context, manager, watchHistory, previous) {
            final provider =
                previous ??
                UserDataProvider(
                  mediaServiceManager: manager,
                  watchHistoryRepository: watchHistory,
                );
            provider.updateDependencies(
              manager: manager,
              watchHistoryRepository: watchHistory,
            );
            return provider;
          },
        ),

        // 4. 媒体库管理
        ChangeNotifierProxyProvider<IMediaRepository, MediaLibraryProvider>(
          create: (context) {
            final provider = MediaLibraryProvider(
              mediaRepository: context.read<IMediaRepository>(),
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              provider.loadInitialMedia();
            });
            return provider;
          },
          update: (context, repo, previous) {
            final provider =
                previous ?? MediaLibraryProvider(mediaRepository: repo);
            provider.updateRepository(repo);
            return provider;
          },
        ),

        // 5. 数据粘合层
        ChangeNotifierProxyProvider2<
          MediaLibraryProvider,
          UserDataProvider,
          MediaWithUserDataProvider
        >(
          create: (context) => MediaWithUserDataProvider(
            mediaLibraryProvider: context.read<MediaLibraryProvider>(),
            userDataProvider: context.read<UserDataProvider>(),
          ),
          update: (context, library, user, previous) {
            // ✅ 调用更新方法，而不是简单返回 previous
            return (previous ??
                  MediaWithUserDataProvider(
                    mediaLibraryProvider: library,
                    userDataProvider: user,
                  ))
              ..updateDependencies(mediaLibrary: library, userData: user);
          },
        ),
      ],
      child: MaterialApp.router(
        title: 'MeowHub',
        debugShowCheckedModeBanner: false,
        locale: DevicePreview.locale(context),
        supportedLocales: _supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) {
          final previewChild = DevicePreview.appBuilder(context, child);
          return CapabilityProbeHost(child: previewChild);
        },
        theme: AppTheme.dark(),
        routerConfig: _router,
      ),
    );
  }
}

Future<void> _startupIncrementalScan(
  List<String> rootPaths,
  LocalMediaDatabase database,
) async {
  try {
    if (!await StoragePermissionService.hasFullStorageAccess()) {
      debugPrint('[LocalMedia][main] 启动扫描跳过: 无存储权限');
      return;
    }

    final knownFiles = await database.getKnownFiles();

    // Check if any root path exists
    var hasExistingPath = false;
    for (final path in rootPaths) {
      if (Directory(path.trim()).existsSync()) {
        hasExistingPath = true;
        break;
      }
    }
    if (!hasExistingPath) return;

    // Run quick incremental scan
    final result = await LocalMediaScanner.runInIsolate(rootPaths, knownFiles);

    if (result.hasChanges) {
      for (final file in result.newAndChanged) {
        await database.upsertScannedFile({
          'id': file.filePath.hashCode.toString(),
          'file_path': file.filePath,
          'file_name': file.fileName,
          'file_size': file.fileSize,
          'mtime': file.mtime,
          'duration_ms': file.durationMs,
          'width': file.width,
          'height': file.height,
          'media_type': file.mediaType,
          'title': file.title,
          'original_title': file.originalTitle,
          'overview': file.overview,
          'year': file.year,
          'rating': file.rating,
          'poster_path': file.posterPath,
          'backdrop_path': file.backdropPath,
          'series_id': file.seriesId,
          'season_number': file.seasonNumber,
          'episode_number': file.episodeNumber,
          'parent_folder': file.parentFolder,
          'nfo_path': file.nfoPath,
        });
      }
      for (final series in result.newSeries) {
        await database.upsertSeries({
          'id': series.id,
          'title': series.title,
          'original_title': series.originalTitle,
          'overview': series.overview,
          'poster_path': series.posterPath,
          'backdrop_path': series.backdropPath,
          'year': series.year,
          'rating': series.rating,
          'folder_path': series.folderPath,
        });
      }
      await database.deleteScannedFiles(result.deletedPaths);

      final now = DateTime.now().millisecondsSinceEpoch;
      for (final path in rootPaths) {
        await database.updateScanFolder(path, scannedAt: now);
      }
    }
  } catch (_) {
    // Silent failure on startup scan
  }
}

// --- 工厂方法（通过 MediaRepositoryFactory 静态方法，支持多后端） ---

MediaConfigValidator _buildMediaConfigValidator({
  required SecurityService securityService,
  required SessionExpiredNotifier sessionExpiredNotifier,
}) {
  return (config) async {
    if (config.type == MediaServiceType.local) {
      if (config.localPaths.isEmpty) return false;
      for (final path in config.localPaths) {
        final dir = Directory(path.trim());
        if (!await dir.exists()) return false;
      }
      return true;
    }

    if (config.type != MediaServiceType.emby &&
        config.type != MediaServiceType.jellyfin) {
      return false;
    }

    try {
      final apiClient = EmbyApiClient(
        config: config,
        securityService: securityService,
        sessionExpiredNotifier: sessionExpiredNotifier,
      );
      await apiClient.authenticate();
      await apiClient.getSystemInfo();
      return true;
    } catch (error) {
      return false;
    }
  };
}

// --- 引导辅助函数 ---

Future<_FileSourceBootstrap> _loadFileSourceBootstrap({
  required FileSourceStore fileSourceStore,
  required IMediaServiceManager mediaServiceManager,
}) async {
  var state = await fileSourceStore.load();
  if (state.isEmpty) {
    final savedConfig = mediaServiceManager.getSavedConfig();
    if (savedConfig != null) {
      final migratedServer = MediaServerInfo.fromConfig(
        config: savedConfig,
        name: _defaultSourceName(savedConfig),
      );
      state = PersistedFileSourceState(
        sources: [
          PersistedFileSource(
            id: migratedServer.id,
            name: migratedServer.name,
            config: savedConfig,
          ),
        ],
        selectedSourceId: migratedServer.id,
      );
      await fileSourceStore.save(state);
    }
  }

  final servers = state.sources
      .map(
        (source) => MediaServerInfo(
          id: source.id,
          name: source.name,
          baseUrl: source.config.normalizedServerUrl,
          type: source.config.type,
          region: source.config.type.displayName,
          config: source.config,
        ),
      )
      .toList(growable: false);

  MediaServerInfo? selectedServer;
  if (state.selectedSourceId != null) {
    for (final server in servers) {
      if (server.id == state.selectedSourceId) {
        selectedServer = server;
        break;
      }
    }
  }

  return _FileSourceBootstrap(servers: servers, selectedServer: selectedServer);
}

String _defaultSourceName(MediaServiceConfig config) {
  final host = Uri.tryParse(config.normalizedServerUrl)?.host.trim() ?? '';
  return host.isNotEmpty ? host : '${config.type.displayName} 默认源';
}

class _FileSourceBootstrap {
  const _FileSourceBootstrap({
    required this.servers,
    required this.selectedServer,
  });

  final List<MediaServerInfo> servers;
  final MediaServerInfo? selectedServer;
}

bool _isDevicePreviewEnabled() {
  if (_devicePreviewMode == 'true') {
    return true;
  }

  if (_devicePreviewMode == 'false' || kReleaseMode) {
    return false;
  }

  if (kIsWeb) {
    return true;
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };
}

class _RouteErrorView extends StatelessWidget {
  const _RouteErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MeowHub')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }
}
