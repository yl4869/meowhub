import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/persistence/file_source_store.dart';
import 'core/services/security_service.dart';
import 'core/session/session_expired_notifier.dart';
import 'data/datasources/emby_api_client.dart';
import 'data/datasources/emby_watch_history_remote_data_source.dart';
import 'data/datasources/local_watch_history_data_source.dart';
import 'data/repositories/empty_media_repository_impl.dart';
import 'data/repositories/emby_media_repository_impl.dart';
import 'data/repositories/emby_playback_repository_impl.dart';
import 'data/repositories/mock_media_repository_impl.dart';
import 'data/repositories/watch_history_repository_impl.dart';
import 'data/repositories/media_service_manager_impl.dart'; // ✅ 唯一实现类
import 'domain/entities/media_item.dart';
import 'domain/entities/media_service_config.dart';
import 'domain/entities/playback_plan.dart';
import 'domain/repositories/i_media_repository.dart';
import 'domain/repositories/i_media_service_manager.dart'; // ✅ 唯一接口
import 'domain/repositories/playback_repository.dart';
import 'domain/repositories/watch_history_repository.dart';
import 'providers/app_provider.dart';
import 'providers/media_detail_provider.dart';
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
  final securityService = SecurityService();
  final sessionExpiredNotifier = SessionExpiredNotifier();
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
    if (currentConfig?.credentialNamespace != selectedConfig.credentialNamespace) {
      try {
        await mediaServiceManager.setConfig(selectedConfig);
      } catch (_) {}
    }
  }

  // 5. 启动应用
  runApp(
    DevicePreview(
      enabled: _isDevicePreviewEnabled(),
      defaultDevice: Devices.ios.iPhone13,
      availableLocales: _supportedLocales,
      builder: (context) => MeowHubApp(
        preferences: preferences,
        securityService: securityService,
        mediaServiceManager: mediaServiceManager,
        fileSourceStore: fileSourceStore,
        initialServers: fileSourceBootstrap.servers,
        initialSelectedServerId: fileSourceBootstrap.selectedServer?.id,
        sessionExpiredNotifier: sessionExpiredNotifier,
        localWatchHistoryDataSource: localWatchHistoryDataSource,
      ),
    ),
  );
}

class MeowHubApp extends StatefulWidget {
  const MeowHubApp({
    super.key,
    required this.preferences,
    required this.securityService,
    required this.mediaServiceManager,
    required this.fileSourceStore,
    required this.initialServers,
    required this.initialSelectedServerId,
    required this.sessionExpiredNotifier,
    required this.localWatchHistoryDataSource, // 👈 增加这一项
  });

  final SharedPreferences preferences;
  final SecurityService securityService;
  final IMediaServiceManager mediaServiceManager; // ✅ 统一使用接口
  final FileSourceStore fileSourceStore;
  final List<MediaServerInfo> initialServers;
  final String? initialSelectedServerId;
  final SessionExpiredNotifier sessionExpiredNotifier;
  // ✅ 2. 必须在这里声明成员变量，否则外部传入的数据没地方存！
  final LocalWatchHistoryDataSource localWatchHistoryDataSource;

  @override
  State<MeowHubApp> createState() => _MeowHubAppState();
}

class _MeowHubAppState extends State<MeowHubApp> {
  late final GoRouter _router = GoRouter(
    initialLocation: HomeView.routePath,
    refreshListenable: widget.sessionExpiredNotifier,
    redirect: (context, state) {
      final isLoginRoute = state.matchedLocation == MediaServiceConfigScreen.routePath;
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

          return ChangeNotifierProxyProvider2<UserDataProvider, PlaybackRepository, MediaDetailProvider>(
            create: (context) => MediaDetailProvider(
              playbackRepository: context.read<PlaybackRepository>(),
              userDataProvider: context.read<UserDataProvider>(),
            ),
            update: (context, userData, playback, previous) {
              final provider = previous ?? MediaDetailProvider(userDataProvider: userData, playbackRepository: playback);
              provider.updateDependencies(userDataProvider: userData, playbackRepository: playback);
              return provider;
            },
            child: MediaDetailView(mediaItem: mediaItem),
          );
        },
      ),
      GoRoute(
        path: MediaLibraryCollectionView.routePath,
        builder: (context, state) {
          final typeParam = state.pathParameters['type'];
          final mediaType = MediaType.fromValue(typeParam);
          return MediaLibraryCollectionView(mediaType: mediaType);
        },
      ),
      GoRoute(
        path: PlayerView.routePath,
        builder: (context, state) {
          final mediaItem = state.extra;
          if (mediaItem is! MediaItem) {
            return const _RouteErrorView(message: '播放数据丢失，请重新进入。');
          }
          return PlayerView(mediaItem: mediaItem);
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
        Provider<IMediaServiceManager>.value(value: widget.mediaServiceManager),
        Provider<SecurityService>.value(value: widget.securityService),
        ChangeNotifierProvider<SessionExpiredNotifier>.value(value: widget.sessionExpiredNotifier),

        // 1. 核心单例：共享 ApiClient
        ProxyProvider3<IMediaServiceManager, SecurityService, SessionExpiredNotifier, EmbyApiClient?>(
          update: (context, manager, security, notifier, previous) {
            final config = manager.getSavedConfig();
            if (config == null || config.type != MediaServiceType.emby) return null;
            // 只有当配置发生实质性变化时才重新构建
            return previous?.config == config 
                ? previous 
                : EmbyApiClient(config: config, securityService: security, sessionExpiredNotifier: notifier);
          },
        ),

        // 2. 各种仓库，均使用共享 ApiClient
        ProxyProvider2<EmbyApiClient?, SecurityService, IMediaRepository>(
          update: (context, apiClient, security, _) => _buildMediaRepository(apiClient: apiClient, securityService: security),
        ),
        ProxyProvider2<EmbyApiClient?, SecurityService, PlaybackRepository>(
          update: (context, apiClient, security, _) => _buildPlaybackRepository(apiClient: apiClient, securityService: security),
        ),
        ProxyProvider<EmbyApiClient?, WatchHistoryRepository>(
          update: (context, apiClient, _) => _buildWatchHistoryRepository(
            apiClient: apiClient,
          localDataSource: widget.localWatchHistoryDataSource, // ✅ 补上这一行
          ),
        ),

        // 3. 用户进度管理
        ChangeNotifierProxyProvider2<IMediaServiceManager, WatchHistoryRepository, UserDataProvider>(
          create: (context) => UserDataProvider(
            mediaServiceManager: context.read<IMediaServiceManager>(),
            watchHistoryRepository: context.read<WatchHistoryRepository>(),
          ),
          update: (context, manager, watchHistory, previous) {
            final provider = previous ?? UserDataProvider(mediaServiceManager: manager, watchHistoryRepository: watchHistory);
            provider.updateDependencies(manager: manager, watchHistoryRepository: watchHistory);
            return provider;
          },
        ),
        
        // 4. 媒体库管理
        ChangeNotifierProxyProvider<IMediaRepository, MediaLibraryProvider>(
          create: (context) => MediaLibraryProvider(mediaRepository: context.read<IMediaRepository>())..loadInitialMovies(),
          update: (context, repo, previous) {
            final provider = previous ?? MediaLibraryProvider(mediaRepository: repo);
            provider.updateRepository(repo);
            return provider;
          },
        ),

        // 5. 数据粘合层
        ChangeNotifierProxyProvider2<MediaLibraryProvider, UserDataProvider, MediaWithUserDataProvider>(
  create: (context) => MediaWithUserDataProvider(
    mediaLibraryProvider: context.read<MediaLibraryProvider>(),
    userDataProvider: context.read<UserDataProvider>(),
  ),
  update: (context, library, user, previous) {
    // ✅ 调用更新方法，而不是简单返回 previous
    return (previous ?? MediaWithUserDataProvider(
      mediaLibraryProvider: library,
      userDataProvider: user,
    ))..updateDependencies(mediaLibrary: library, userData: user);
  },
),
      ],
      child: MaterialApp.router(
        title: 'MeowHub',
        debugShowCheckedModeBanner: false,
        useInheritedMediaQuery: true, // DevicePreview 兼容
        locale: DevicePreview.locale(context),
        supportedLocales: _supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: DevicePreview.appBuilder,
        theme: AppTheme.dark(),
        routerConfig: _router,
      ),
    );
  }
}

// --- 工厂方法（保持纯净） ---

IMediaRepository _buildMediaRepository({required EmbyApiClient? apiClient, required SecurityService securityService}) {
  if (_useMockRepository) return const MockMediaRepositoryImpl();
  if (apiClient == null) return const EmptyMediaRepositoryImpl();
  return EmbyMediaRepositoryImpl(apiClient: apiClient, securityService: securityService);
}

PlaybackRepository _buildPlaybackRepository({required EmbyApiClient? apiClient, required SecurityService securityService}) {
  if (apiClient == null) return const _UnavailablePlaybackRepository();
  return EmbyPlaybackRepositoryImpl(apiClient: apiClient, securityService: securityService);
}

// 找到 main.dart 底部附近这个函数进行修改
WatchHistoryRepository _buildWatchHistoryRepository({
  required EmbyApiClient? apiClient,
  required LocalWatchHistoryDataSource localDataSource, // 👈 接收外部传入的单例
  }) {
  if (apiClient == null) {
    return WatchHistoryRepositoryImpl(
      embyRemoteDataSource: MockEmbyWatchHistoryRemoteDataSource(), 
      localDataSource: localDataSource, // ✅ 使用同一个实例
    );
  }

  return WatchHistoryRepositoryImpl(
    embyRemoteDataSource: EmbyWatchHistoryRemoteDataSourceImpl(
      apiClient: apiClient,
    ),
    localDataSource: localDataSource, // ✅ 使用同一个实例
  );
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
      final migratedServer = MediaServerInfo.fromConfig(config: savedConfig, name: _defaultSourceName(savedConfig));
      state = PersistedFileSourceState(
        sources: [PersistedFileSource(id: migratedServer.id, name: migratedServer.name, config: savedConfig)],
        selectedSourceId: migratedServer.id,
      );
      await fileSourceStore.save(state);
    }
  }

  final servers = state.sources.map((source) => MediaServerInfo(
    id: source.id,
    name: source.name,
    baseUrl: source.config.normalizedServerUrl,
    type: source.config.type,
    region: source.config.type.displayName,
    config: source.config,
  )).toList(growable: false);

  MediaServerInfo? selectedServer;
  if (state.selectedSourceId != null) {
    for (final server in servers) {
      if (server.id == state.selectedSourceId) {
        selectedServer = server;
        break;
      }
    }
  }
  selectedServer ??= servers.isNotEmpty ? servers.first : null;

  return _FileSourceBootstrap(servers: servers, selectedServer: selectedServer);
}

String _defaultSourceName(MediaServiceConfig config) {
  final host = Uri.tryParse(config.normalizedServerUrl)?.host.trim() ?? '';
  return host.isNotEmpty ? host : '${config.type.displayName} 默认源';
}

// ... _FileSourceBootstrap, _UnavailablePlaybackRepository, _isDevicePreviewEnabled, _RouteErrorView 类保持不变 ...

class _FileSourceBootstrap {
  const _FileSourceBootstrap({
    required this.servers,
    required this.selectedServer,
  });

  final List<MediaServerInfo> servers;
  final MediaServerInfo? selectedServer;
}

class _UnavailablePlaybackRepository implements PlaybackRepository {
  const _UnavailablePlaybackRepository();

  @override
  Future<PlaybackPlan> getPlaybackPlan(
    MediaItem item, {
    int? maxStreamingBitrate,
    bool? requireAvc,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    String? playSessionId,
    Duration startPosition = Duration.zero,
  }) {
    throw StateError(
      'Playback repository is unavailable for current media service',
    );
  }
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
