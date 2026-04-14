import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/services/security_service.dart';
import 'core/session/session_expired_notifier.dart';
import 'data/datasources/emby_api_client.dart';
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
import 'ui/responsive/player_view.dart';
import 'ui/screens/media_service_config_screen.dart';

// 在 main.dart 的顶部或 build 逻辑之前定义
const _hardcodedEmbyConfig = MediaServiceConfig(
  type: MediaServiceType.emby,
  serverUrl: 'http://172.22.73.65:8096', // 你的服务器地址
  username: 'yunlang', // 你的用户名
  password: 'Asadashino', // 填入你的真实密码
  // 使用 GUID 格式的 DeviceId 避免服务器解析 500
  deviceId: '7fb3a52c-d922-4a0d-852a-9e69397621f3',
);

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

  final mediaServiceManager = MediaServiceManager(
    preferences: preferences,
    securityService: securityService,
    sessionExpiredNotifier: sessionExpiredNotifier,
  );
  await mediaServiceManager.initialize();
  // Ensure MediaServiceManager has a valid config so PlayerView can build PlaybackPlan.
  // In dev, we use the hardcoded Emby config; in production this is set via the login screen.
  await mediaServiceManager.setConfig(_hardcodedEmbyConfig);
  final mediaRepository = _buildMediaRepository(
    mediaServiceManager: mediaServiceManager,
    securityService: securityService,
    sessionExpiredNotifier: sessionExpiredNotifier,
  );

  runApp(
    DevicePreview(
      enabled: _isDevicePreviewEnabled(),
      defaultDevice: Devices.ios.iPhone13,
      availableLocales: _supportedLocales,
      builder: (context) => MeowHubApp(
        preferences: preferences,
        securityService: securityService,
        mediaServiceManager: mediaServiceManager,
        mediaRepository: mediaRepository,
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
    required this.mediaRepository,
    required this.sessionExpiredNotifier,
  });

  final SharedPreferences preferences;
  final SecurityService securityService;
  final MediaServiceManager mediaServiceManager;
  final IMediaRepository mediaRepository;
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
          create: (_) =>
              AppProvider(mediaServiceManager: widget.mediaServiceManager),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              UserDataProvider(mediaServiceManager: widget.mediaServiceManager),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              MediaLibraryProvider(mediaRepository: widget.mediaRepository)
                ..loadInitialMovies(),
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
        Provider<MediaServiceManager>.value(value: widget.mediaServiceManager),
        Provider<IMediaRepository>.value(value: widget.mediaRepository),
        Provider<SecurityService>.value(value: widget.securityService),
        ChangeNotifierProvider<SessionExpiredNotifier>.value(
          value: widget.sessionExpiredNotifier,
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

  const config = _hardcodedEmbyConfig;

  // 3. 实例化真正的 Emby 客户端
  final apiClient = EmbyApiClient(
    config: config,
    securityService: securityService,
    sessionExpiredNotifier: sessionExpiredNotifier,
  );

  debugPrint('🚀 MeowHub: 已启用硬编码 Emby 配置');

  return EmbyMediaRepositoryImpl(
    apiClient: apiClient,
    securityService: securityService,
  );
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
