import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/services/security_service.dart';
import '../../core/session/session_expired_notifier.dart';
import '../../domain/entities/media_service_config.dart';
import '../models/emby/emby_media_item_dto.dart';
import '../models/emby/emby_media_library_dto.dart';
import '../models/emby_auth_response.dart';
import '../network/emby_auth_interceptor.dart';
import '../models/emby/emby_playback_info_dto.dart';

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
  Future<void>? _ongoingAuthentication;

  String get serverUrl => _config.normalizedServerUrl;

  Future<void> authenticate() async {
    final existingAuth = _ongoingAuthentication;
    if (existingAuth != null) {
      return existingAuth;
    }

    final authFuture = _performAuthentication();
    _ongoingAuthentication = authFuture;

    try {
      await authFuture;
    } finally {
      if (identical(_ongoingAuthentication, authFuture)) {
        _ongoingAuthentication = null;
      }
    }
  }

  Future<void> _performAuthentication() async {
    final username = _config.username?.trim();
    final password =
        (await _securityService.readPassword()) ?? _config.password?.trim();
    debugPrint("进行登录测试");
    if (username == null ||
        username.isEmpty ||
        password == null ||
        password.isEmpty) {
      throw Exception('Emby 登录需要用户名和密码');
    }
    debugPrint("登录的用户名$username, 登录的密码$password");

    final response = await post<Map<String, dynamic>>(
      '/emby/Users/AuthenticateByName',
      data: {'Username': username, 'Pw': password},
      withToken: false,
    );

    final data = response.data ?? <String, dynamic>{};
    final authResponse = EmbyAuthResponse.fromJson(data);
    final accessToken = authResponse.accessToken;
    final userId = authResponse.user.id;

    debugPrint("登录的useID为$userId");

    debugPrint("获取的数据为$data");

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
    debugPrint("DebugInfo：输出post");
    return _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: Options(extra: {'withToken': withToken}),
    );
  }

  Future<Map<String, dynamic>> getSystemInfo() async {
    final response = await get<Map<String, dynamic>>('/emby/System/Info');
    return response.data ?? <String, dynamic>{};
  }

  Future<EmbyMediaLibraryListDto> getMediaLibraries() async {
    final userId = await _requireUserId();
    final response = await get<Map<String, dynamic>>(
      '/emby/Users/$userId/Views',
    );
    final data = response.data ?? <String, dynamic>{};
    final items = data['Items'] as List<dynamic>? ?? const [];
    return EmbyMediaLibraryListDto(
      items: items
          .whereType<Map<String, dynamic>>()
          .map(EmbyMediaLibraryDto.fromJson)
          .toList(growable: false),
      totalRecordCount:
          (data['TotalRecordCount'] as num?)?.toInt() ?? items.length,
      startIndex: (data['StartIndex'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<EmbyMediaItemDto>> getMediaItems({
    required String includeItemTypes,
    String? libraryId,
    int limit = 100,
  }) async {
    final userId = await _requireUserId();
    final response = await get<Map<String, dynamic>>(
      '/emby/Users/$userId/Items',
      queryParameters: {
        'Recursive': true,
        'IncludeItemTypes': includeItemTypes,
        'SortBy': 'DateCreated,SortName',
        'SortOrder': 'Descending',
        'Fields': 'PrimaryImageAspectRatio,ImageTags,Overview',
        'Limit': '$limit',
        if (libraryId != null && libraryId.isNotEmpty) 'ParentId': libraryId,
      },
    );
    final data = response.data ?? <String, dynamic>{};
    final items = data['Items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(EmbyMediaItemDto.fromJson)
        .toList(growable: false);
  }

  Future<EmbyMediaItemListDto> getMovieItems({
    String? libraryId,
    int limit = 100,
  }) async {
    debugPrint('📡 MeowHub: 正在从真实的 Emby 获取电影列表...');
    final items = await getMediaItems(
      includeItemTypes: 'Movie',
      libraryId: libraryId,
      limit: limit,
    );
    return EmbyMediaItemListDto(
      items: items,
      totalRecordCount: items.length,
      startIndex: 0,
    );
  }

  Future<EmbyMediaItemDto> getMediaItemDetail(String itemId) async {
    final userId = await _requireUserId();
    final response = await get<Map<String, dynamic>>(
      '/emby/Users/$userId/Items/$itemId',
      queryParameters: const {
        'Fields':
            'Overview,OriginalTitle,PrimaryImageAspectRatio,ImageTags,BackdropImageTags,People',
      },
    );
    final data = response.data ?? <String, dynamic>{};
    return EmbyMediaItemDto.fromJson(data);
  }

  Future<EmbyPlaybackInfoDto> getPlaybackInfo({
    required String itemId,
    int? maxStreamingBitrate,
    bool? requireAvc,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    String? mediaSourceId,
  }) async {
    final userId = await _requireUserId();
    final body = <String, dynamic>{
      'UserId': userId,
      if (maxStreamingBitrate != null)
        'MaxStreamingBitrate': maxStreamingBitrate,
      if (requireAvc != null) 'RequireAvc': requireAvc,
      if (audioStreamIndex != null) 'AudioStreamIndex': audioStreamIndex,
      if (subtitleStreamIndex != null)
        'SubtitleStreamIndex': subtitleStreamIndex,
      if (mediaSourceId != null) 'MediaSourceId': mediaSourceId,
    };
    debugPrint("getPlaybackInfo: the post is /emby/Items/$itemId/PlaybackInfo");
    final resp = await post<Map<String, dynamic>>(
      '/emby/Items/$itemId/PlaybackInfo',
      data: body,
    );
    debugPrint("getPlaybackInfo: the get data is $resp.data");
    final data = resp.data ?? <String, dynamic>{};
    // Debug: Print basic structure of PlaybackInfo to verify subtitle availability
    if (kDebugMode) {
      try {
        final sources = (data['MediaSources'] as List?) ?? const [];
        debugPrint(
          '[PlaybackInfo] sources=${sources.length} for item=$itemId',
        );
        for (final s in sources.whereType<Map<String, dynamic>>()) {
          final streams = (s['MediaStreams'] as List?) ?? const [];
          final subsCount = streams
              .where(
                (e) =>
                    e is Map &&
                    (e['Type']?.toString().toLowerCase() == 'subtitle'),
              )
              .length;
          final sid = s['Id'];
          debugPrint(
            '[PlaybackInfo]  - sourceId=' +
                (sid?.toString() ?? '') +
                ' streams=' +
                streams.length.toString() +
                ' subs=' +
                subsCount.toString(),
          );
        }
      } catch (e) {
        debugPrint('[PlaybackInfo] debug print error: \$e');
      }
    }
    return EmbyPlaybackInfoDto.fromJson(data);
  }

  Future<List<EmbyMediaItemDto>> getEpisodes(String seriesId) async {
    await _requireUserId();
    final response = await get<Map<String, dynamic>>(
      '/emby/Shows/$seriesId/Episodes',
      queryParameters: const {
        'Fields':
            'Overview,OriginalTitle,PrimaryImageAspectRatio,ImageTags,BackdropImageTags,ParentIndexNumber,IndexNumber,SeriesName',
      },
    );
    final data = response.data ?? <String, dynamic>{};
    final items = data['Items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(EmbyMediaItemDto.fromJson)
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getResumeItems() async {
    final userId = await _requireUserId();
    final response = await get<Map<String, dynamic>>(
      '/emby/Users/$userId/Items/ResumeItems',
      queryParameters: const {
        'Limit': '5',
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
