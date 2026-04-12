import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'data/datasources/emby_watch_history_remote_data_source.dart';
import 'data/datasources/local_watch_history_data_source.dart';
import 'data/repositories/watch_history_repository_impl.dart';
import 'domain/entities/watch_history_item.dart';
import 'models/media_item.dart';
import 'providers/app_provider.dart';
import 'providers/movie_provider.dart';
import 'theme/app_theme.dart';
import 'ui/mobile/sample/mobile_ui_sample_view.dart';
import 'ui/responsive/home_view.dart';
import 'ui/responsive/media_detail_view.dart';
import 'ui/responsive/player_view.dart';

const List<Locale> _supportedLocales = [Locale('zh', 'CN'), Locale('en', 'US')];

const String _devicePreviewMode = String.fromEnvironment(
  'DEVICE_PREVIEW',
  defaultValue: 'auto',
);

final _watchHistoryRepository = WatchHistoryRepositoryImpl(
  embyRemoteDataSource: MockEmbyWatchHistoryRemoteDataSource(
    initialHistory: [
      WatchHistoryItem(
        id: '1002',
        title: 'Moonlit Harbor',
        poster: '',
        position: Duration(minutes: 34, seconds: 12),
        duration: Duration(hours: 1, minutes: 52, seconds: 18),
        updatedAt: DateTime(2026, 4, 12, 20, 30),
        sourceType: WatchSourceType.emby,
      ),
      WatchHistoryItem(
        id: '1007',
        title: 'Glass Kingdom',
        poster: '',
        position: Duration(minutes: 12, seconds: 5),
        duration: Duration(hours: 2, minutes: 6, seconds: 40),
        updatedAt: DateTime(2026, 4, 11, 21, 10),
        sourceType: WatchSourceType.emby,
      ),
    ],
  ),
  localDataSource: InMemoryLocalWatchHistoryDataSource(),
);

final GoRouter _router = GoRouter(
  initialLocation: HomeView.routePath,
  routes: [
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

void main() {
  runApp(
    DevicePreview(
      enabled: _isDevicePreviewEnabled(),
      defaultDevice: Devices.ios.iPhone13,
      availableLocales: _supportedLocales,
      builder: (context) => const MeowHubApp(),
    ),
  );
}

class MeowHubApp extends StatelessWidget {
  const MeowHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppProvider(
            watchHistoryRepository: _watchHistoryRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => MovieProvider()..loadInitialMovies(),
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
