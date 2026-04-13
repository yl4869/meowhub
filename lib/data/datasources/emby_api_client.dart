import 'package:dio/dio.dart';

import '../../core/services/security_service.dart';
import '../../core/session/session_expired_notifier.dart';
import '../../domain/entities/media_service_config.dart';
import '../models/emby_auth_response.dart';
import '../models/emby_library_response.dart';
import '../network/emby_auth_interceptor.dart';

/// Emby API 客户端封装。
/// 统一负责认证、基础 GET/POST、媒体库与影片列表接口访问。
class EmbyApiClient {
  EmbyApiClient({
    required MediaServiceConfig config,
    required SecurityService securityService,
    required SessionExpiredNotifier sessionExpiredNotifier,
    Dio? dio,
  }) : _config = config,
       _securityService = securityService,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: config.normalizedServerUrl,
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 20),
               headers: {
                 'Content-Type': 'application/json',
                 'X-Emby-Authorization':
                     'MediaBrowser Client="MeowHub", Device="MeowHub", DeviceId="${config.deviceId?.trim().isNotEmpty == true ? config.deviceId!.trim() : 'meowhub-device'}", Version="1.0.0"',
               },
             ),
           ) {
    _dio.interceptors.add(
      EmbyAuthInterceptor(
        securityService: securityService,
        sessionExpiredNotifier: sessionExpiredNotifier,
      ),
    );
  }

  final MediaServiceConfig _config;
  final SecurityService _securityService;
  final Dio _dio;

  Future<void> authenticate() async {
    final username = _config.username?.trim();
    final password =
        (await _securityService.readPassword()) ?? _config.password?.trim();

    if (username == null ||
        username.isEmpty ||
        password == null ||
        password.isEmpty) {
      throw Exception('Emby 登录需要用户名和密码');
    }

    final response = await post<Map<String, dynamic>>(
      '/emby/Users/AuthenticateByName',
      data: {'Username': username, 'Pw': password},
      withToken: false,
    );

    final data = response.data ?? <String, dynamic>{};
    final authResponse = EmbyAuthResponse.fromJson(data);
    final accessToken = authResponse.accessToken;
    final userId = authResponse.user.id;

    if (accessToken.isEmpty || userId.isEmpty) {
      throw Exception('Emby 登录成功但未返回有效的 AccessToken 或 UserId');
    }

    await Future.wait([
      _securityService.writeAccessToken(accessToken),
      _securityService.writeUserId(userId),
      _securityService.writePassword(password),
    ]);
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool withToken = true,
  }) async {
    if (withToken) {
      await _ensureSession();
    }

    return _dio.get<T>(path, queryParameters: queryParameters);
  }

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool withToken = true,
  }) async {
    if (withToken) {
      await _ensureSession();
    }

    return _dio.post<T>(path, data: data, queryParameters: queryParameters);
  }

  Future<Map<String, dynamic>> getSystemInfo() async {
    final response = await get<Map<String, dynamic>>('/emby/System/Info');
    return response.data ?? <String, dynamic>{};
  }

  Future<EmbyLibraryResponse> getMediaLibraries() async {
    final userId = await _requireUserId();
    final response = await get<Map<String, dynamic>>(
      '/emby/Users/$userId/Views',
    );
    final data = response.data ?? <String, dynamic>{};
    return EmbyLibraryResponse.fromJson(data);
  }

  Future<EmbyMovieListResponse> getMovieItems({
    String? libraryId,
    int limit = 100,
  }) async {
    final userId = await _requireUserId();
    final response = await get<Map<String, dynamic>>(
      '/emby/Users/$userId/Items',
      queryParameters: {
        'Recursive': true,
        'IncludeItemTypes': 'Movie',
        'SortBy': 'DateCreated,SortName',
        'SortOrder': 'Descending',
        'Fields': 'PrimaryImageAspectRatio,ImageTags,Overview',
        'Limit': '$limit',
        if (libraryId != null && libraryId.isNotEmpty) 'ParentId': libraryId,
      },
    );
    final data = response.data ?? <String, dynamic>{};
    return EmbyMovieListResponse.fromJson(data);
  }

  Future<List<Map<String, dynamic>>> getResumeItems() async {
    final userId = await _requireUserId();
    final response = await get<Map<String, dynamic>>(
      '/emby/Users/$userId/Items/ResumeItems',
      queryParameters: const {
        'Limit': '100',
        'Fields':
            'PrimaryImageAspectRatio,SeriesPrimaryImageTag,ImageTags,BackdropImageTags',
      },
    );
    final data = response.data ?? <String, dynamic>{};
    final items = data['Items'] as List<dynamic>? ?? const [];
    return items.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<void> updatePlaybackProgress({
    required String itemId,
    required Duration position,
  }) async {
    final userId = await _requireUserId();
    await post<void>(
      '/emby/Users/$userId/PlayingItems/$itemId',
      queryParameters: {
        'PositionTicks': (position.inMilliseconds * 10000).round().toString(),
      },
    );
  }

  Future<void> _ensureSession() async {
    final accessToken = await _securityService.readAccessToken();
    final userId = await _securityService.readUserId();

    if (accessToken?.isNotEmpty == true && userId?.isNotEmpty == true) {
      return;
    }

    await authenticate();
  }

  Future<String> _requireUserId() async {
    var userId = await _securityService.readUserId();
    if (userId != null && userId.isNotEmpty) {
      return userId;
    }

    await authenticate();
    userId = await _securityService.readUserId();
    if (userId == null || userId.isEmpty) {
      throw Exception('Emby 登录后未能获取到用户 ID');
    }

    return userId;
  }

  void dispose() {
    _dio.close();
  }
}
