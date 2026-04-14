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
import 'data/repositories/empty_media_repository_impl.dart';
import 'data/repositories/emby_media_repository_impl.dart';
import 'data/repositories/mock_media_repository_impl.dart';
import 'domain/entities/media_item.dart';
import 'domain/entities/media_service_config.dart';
import 'domain/repositories/i_media_repository.dart';
import 'domain/repositories/media_service_manager.dart';
import 'providers/app_provider.dart';
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
  final preferences = await SharedPreferences.getInstance();
  final securityService = SecurityService();
  final sessionExpiredNotifier = SessionExpiredNotifier();
  final fileSourceStore = FileSourceStore();

  final mediaServiceManager = MediaServiceManager(
    preferences: preferences,
    securityService: securityService,
    sessionExpiredNotifier: sessionExpiredNotifier,
  );
  await mediaServiceManager.initialize();
  final fileSourceBootstrap = await _loadFileSourceBootstrap(
    fileSourceStore: fileSourceStore,
    mediaServiceManager: mediaServiceManager,
  );

  final selectedServer = fileSourceBootstrap.selectedServer;
  if (selectedServer?.config case final selectedConfig?) {
    final currentConfig = mediaServiceManager.getSavedConfig();
    if (currentConfig?.credentialNamespace !=
        selectedConfig.credentialNamespace) {
      try {
        await mediaServiceManager.setConfig(selectedConfig);
      } catch (_) {
        // Fall back to an empty library when persisted credentials are incomplete.
      }
    }
  }

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
  });

  final SharedPreferences preferences;
  final SecurityService securityService;
  final MediaServiceManager mediaServiceManager;
  final FileSourceStore fileSourceStore;
  final List<MediaServerInfo> initialServers;
  final String? initialSelectedServerId;
  final SessionExpiredNotifier sessionExpiredNotifier;

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
            return const _RouteErrorView(message: '没有接收到作品详情数据，请从首页重新进入。');
          }

          return MediaDetailView(mediaItem: mediaItem);
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
            return const _RouteErrorView(message: '没有接收到播放页所需的作品数据，请从详情页重新进入。');
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
        ChangeNotifierProvider<MediaServiceManager>.value(
          value: widget.mediaServiceManager,
        ),
        ChangeNotifierProxyProvider<MediaServiceManager, UserDataProvider>(
          create: (context) => UserDataProvider(
            mediaServiceManager: context.read<MediaServiceManager>(),
          ),
          update: (context, manager, previous) {
            final provider =
                previous ?? UserDataProvider(mediaServiceManager: manager);
            provider.updateMediaServiceManager(manager);
            return provider;
          },
        ),
        Provider<SecurityService>.value(value: widget.securityService),
        ChangeNotifierProvider<SessionExpiredNotifier>.value(
          value: widget.sessionExpiredNotifier,
        ),
        ProxyProvider3<
          MediaServiceManager,
          SecurityService,
          SessionExpiredNotifier,
          IMediaRepository
        >(
          update:
              (context, manager, security, sessionExpiredNotifier, previous) {
                return _buildMediaRepository(
                  mediaServiceManager: manager,
                  securityService: security,
                  sessionExpiredNotifier: sessionExpiredNotifier,
                );
              },
        ),
        ChangeNotifierProxyProvider<IMediaRepository, MediaLibraryProvider>(
          create: (context) => MediaLibraryProvider(
            mediaRepository: context.read<IMediaRepository>(),
          )..loadInitialMovies(),
          update: (context, mediaRepository, previous) {
            final provider =
                previous ??
                MediaLibraryProvider(mediaRepository: mediaRepository);
            provider.updateRepository(mediaRepository);
            return provider;
          },
        ),
        ChangeNotifierProxyProvider2<
          MediaLibraryProvider,
          UserDataProvider,
          MediaWithUserDataProvider
        >(
          create: (context) => MediaWithUserDataProvider(
            mediaLibraryProvider: context.read<MediaLibraryProvider>(),
            userDataProvider: context.read<UserDataProvider>(),
          ),
          update: (context, mediaLibrary, userData, previous) =>
              previous ??
              MediaWithUserDataProvider(
                mediaLibraryProvider: mediaLibrary,
                userDataProvider: userData,
              ),
        ),
      ],
      child: MaterialApp.router(
        title: 'MeowHub',
        debugShowCheckedModeBanner: false,
        // DevicePreview 1.3.1 still asserts this flag in debug mode.
        // ignore: deprecated_member_use
        useInheritedMediaQuery: true,
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

/// Refactor reason:
/// Dependency injection is centralized in the composition root, so providers
/// consume abstractions and never decide mock/remote behavior themselves.
IMediaRepository _buildMediaRepository({
  required MediaServiceManager mediaServiceManager,
  required SecurityService securityService,
  required SessionExpiredNotifier sessionExpiredNotifier,
}) {
  if (_useMockRepository) {
    return const MockMediaRepositoryImpl();
  }

  final config = mediaServiceManager.getSavedConfig();
  if (config == null || config.type != MediaServiceType.emby) {
    return const EmptyMediaRepositoryImpl();
  }
  final apiClient = EmbyApiClient(
    config: config,
    securityService: securityService,
    sessionExpiredNotifier: sessionExpiredNotifier,
  );

  return EmbyMediaRepositoryImpl(
    apiClient: apiClient,
    securityService: securityService,
  );
}

Future<_FileSourceBootstrap> _loadFileSourceBootstrap({
  required FileSourceStore fileSourceStore,
  required MediaServiceManager mediaServiceManager,
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
  selectedServer ??= servers.isNotEmpty ? servers.first : null;

  return _FileSourceBootstrap(servers: servers, selectedServer: selectedServer);
}

String _defaultSourceName(MediaServiceConfig config) {
  final host = Uri.tryParse(config.normalizedServerUrl)?.host.trim() ?? '';
  if (host.isNotEmpty) {
    return host;
  }
  return '${config.type.displayName} 默认源';
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
