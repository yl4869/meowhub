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
       _resolvedDeviceId = _normalizeDeviceId(config.deviceId),
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
                     'MediaBrowser Client="MeowHub", Device="MeowHub", DeviceId="${_normalizeDeviceId(config.deviceId)}", Version="1.0.0"',
                 'X-Emby-Device-Id': _normalizeDeviceId(config.deviceId),
               },
             ),
           ) {
    _dio.interceptors.add(
      EmbyAuthInterceptor(
        securityService: securityService,
        sessionExpiredNotifier: sessionExpiredNotifier,
        namespace: config.credentialNamespace,
        deviceId: _normalizeDeviceId(config.deviceId),
      ),
    );
  }

  final MediaServiceConfig _config;
  final SecurityService _securityService;
  final String _resolvedDeviceId;
  final Dio _dio;
  Future<void>? _ongoingAuthentication;
  static final Map<String, Future<void>> _sharedAuthentications = {};

  String get serverUrl => _config.normalizedServerUrl;
  String get securityNamespace => _config.credentialNamespace;

  Future<void> authenticate() async {
    if (await _hasUsableSession()) {
      return;
    }

    final existingAuth = _ongoingAuthentication;
    if (existingAuth != null) {
      return existingAuth;
    }

    final sharedAuth =
        _sharedAuthentications[_config.credentialNamespace] ??
        _performAuthentication();
    _sharedAuthentications[_config.credentialNamespace] = sharedAuth;
    final authFuture = sharedAuth;
    _ongoingAuthentication = authFuture;

    try {
      await authFuture;
    } finally {
      if (identical(_ongoingAuthentication, authFuture)) {
        _ongoingAuthentication = null;
      }
      if (identical(
        _sharedAuthentications[_config.credentialNamespace],
        authFuture,
      )) {
        _sharedAuthentications.remove(_config.credentialNamespace);
      }
    }
  }

  Future<void> _performAuthentication() async {
    final username = _config.username?.trim();
    final password =
        (await _securityService.readPassword(
          namespace: _config.credentialNamespace,
        )) ??
        _config.password?.trim();
    if (username == null ||
        username.isEmpty ||
        password == null ||
        password.isEmpty) {
      throw Exception('Emby 登录需要用户名和密码');
    }
    debugPrint('[EmbyAuth] 开始认证 namespace=${_config.credentialNamespace}');

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
      _securityService.writeAccessToken(
        accessToken,
        namespace: _config.credentialNamespace,
      ),
      _securityService.writeUserId(
        userId,
        namespace: _config.credentialNamespace,
      ),
      _securityService.writePassword(
        password,
        namespace: _config.credentialNamespace,
      ),
    ]);

    debugPrint('[EmbyAuth] 认证成功 userId=$userId');
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
    Map<String, dynamic>? headers,
  }) async {
    if (withToken) {
      await _ensureSession();
    }
    debugPrint("DebugInfo：输出post");
    return _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: Options(headers: headers, extra: {'withToken': withToken}),
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
        'EnableUserData': true,
        'Fields':
            'Overview,RunTimeTicks,ProductionYear,CommunityRating,PremiereDate,ImageTags,BackdropImageTags,ParentIndexNumber,IndexNumber,SeriesName,SeriesId,UserData',
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
            'Overview,OriginalTitle,RunTimeTicks,ProductionYear,CommunityRating,PremiereDate,ImageTags,BackdropImageTags,People,ParentIndexNumber,IndexNumber,SeriesName,SeriesId,UserData',
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
    final effectiveMaxStreamingBitrate =
        maxStreamingBitrate ?? 200 * 1000 * 1000;
    final optionalBody = <String, dynamic>{};
    void putIfPresent(String key, Object? value) {
      if (value != null) {
        optionalBody[key] = value;
      }
    }

    putIfPresent('MaxStreamingBitrate', maxStreamingBitrate);
    putIfPresent('RequireAvc', requireAvc);
    putIfPresent('AudioStreamIndex', audioStreamIndex);
    putIfPresent('SubtitleStreamIndex', subtitleStreamIndex);
    putIfPresent('MediaSourceId', mediaSourceId);
    final body = <String, dynamic>{
      'UserId': userId,
      'DeviceId': _resolvedDeviceId,
      'EnableDirectPlay': true,
      'EnableDirectStream': true,
      'EnableTranscoding': true,
      'AllowInterlacedVideoStreamCopy': true,
      'AllowVideoStreamCopy': true,
      'AllowAudioStreamCopy': true,
      'IsPlayback': true,
      ...optionalBody,
      'DeviceProfile': _buildMediaKitDeviceProfile(
        deviceId: _resolvedDeviceId,
        maxStreamingBitrate: effectiveMaxStreamingBitrate,
      ),
    };
    debugPrint("getPlaybackInfo: the post is /emby/Items/$itemId/PlaybackInfo");
    final resp = await post<Map<String, dynamic>>(
      '/emby/Items/$itemId/PlaybackInfo',
      data: body,
      headers: {'X-Emby-Device-Id': _resolvedDeviceId},
    );
    debugPrint("getPlaybackInfo: the get data is $resp.data");
    final data = resp.data ?? <String, dynamic>{};
    // Debug: Print basic structure of PlaybackInfo to verify subtitle availability
    if (kDebugMode) {
      try {
        final sources = (data['MediaSources'] as List?) ?? const [];
        debugPrint('[PlaybackInfo] sources=${sources.length} for item=$itemId');
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
            '[PlaybackInfo]  - sourceId=${sid?.toString() ?? ''} '
            'streams=${streams.length} subs=$subsCount',
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
        'EnableUserData': true,
        'Fields':
            'Overview,OriginalTitle,RunTimeTicks,ProductionYear,CommunityRating,PremiereDate,ImageTags,BackdropImageTags,ParentIndexNumber,IndexNumber,SeriesName,SeriesId,UserData',
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
            'Overview,RunTimeTicks,ProductionYear,ParentIndexNumber,IndexNumber,SeriesName,SeriesId,PrimaryImageAspectRatio,SeriesPrimaryImageTag,ImageTags,BackdropImageTags,UserData',
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
    if (await _hasUsableSession()) {
      return;
    }

    await authenticate();
  }

  Future<String> _requireUserId() async {
    await _ensureSession();
    var userId = await _securityService.readUserId(
      namespace: _config.credentialNamespace,
    );
    if (userId != null && userId.isNotEmpty) {
      return userId;
    }
    if (userId == null || userId.isEmpty) {
      throw Exception('Emby 登录后未能获取到用户 ID');
    }

    return userId;
  }

  Future<bool> _hasUsableSession() async {
    final accessToken = await _securityService.readAccessToken(
      namespace: _config.credentialNamespace,
    );
    final userId = await _securityService.readUserId(
      namespace: _config.credentialNamespace,
    );
    return accessToken?.isNotEmpty == true && userId?.isNotEmpty == true;
  }

  void dispose() {
    _dio.close();
  }
}

String _normalizeDeviceId(String? deviceId) {
  final normalized = deviceId?.trim();
  if (normalized == null || normalized.isEmpty) {
    return 'meowhub-device';
  }
  return normalized;
}

Map<String, dynamic> _buildMediaKitDeviceProfile({
  required String deviceId,
  required int maxStreamingBitrate,
}) {
  const videoContainers =
      'mp4,m4v,mov,mkv,webm,ts,m2ts,mpegts,mpeg,mpg,avi,asf,wmv,flv,ogv,3gp';
  const videoCodecs =
      'h264,hevc,av1,vp8,vp9,mpeg1video,mpeg2video,mpeg4,msmpeg4v3,vc1,wmv3,mjpeg,prores,theora';
  const audioCodecs =
      'aac,alac,ac3,eac3,dts,flac,mp2,mp3,opus,pcm_alaw,pcm_mulaw,pcm_s16le,pcm_s24le,truehd,vorbis,wavpack,wmav2';
  const audioContainers = 'aac,m4a,mp3,flac,ogg,oga,opus,wav,webma,wma';

  return <String, dynamic>{
    'Name': 'MeowHub media_kit',
    'Id': deviceId,
    'SupportedMediaTypes': 'Video,Audio',
    'MaxStreamingBitrate': maxStreamingBitrate,
    'MaxStaticBitrate': maxStreamingBitrate,
    'MusicStreamingTranscodingBitrate': 384000,
    'MaxStaticMusicBitrate': maxStreamingBitrate,
    'DirectPlayProfiles': [
      {
        'Type': 'Video',
        'Container': videoContainers,
        'VideoCodec': videoCodecs,
        'AudioCodec': audioCodecs,
      },
      {
        'Type': 'Audio',
        'Container': audioContainers,
        'AudioCodec': audioCodecs,
      },
    ],
    'TranscodingProfiles': [
      {
        'Type': 'Video',
        'Container': 'ts',
        'Protocol': 'hls',
        'Context': 'Streaming',
        'VideoCodec': 'h264,hevc,av1,vp9',
        'AudioCodec': 'aac,ac3,eac3,mp3,opus,flac',
        'TranscodeSeekInfo': 'Auto',
        'ManifestSubtitles': 'vtt',
        'CopyTimestamps': true,
      },
      {
        'Type': 'Video',
        'Container': 'ts',
        'Protocol': 'http',
        'Context': 'Streaming',
        'VideoCodec': 'h264,hevc,av1,vp9',
        'AudioCodec': 'aac,ac3,eac3,mp3,opus,flac',
        'TranscodeSeekInfo': 'Auto',
        'CopyTimestamps': true,
      },
      {
        'Type': 'Video',
        'Container': 'mp4',
        'Protocol': 'http',
        'Context': 'Static',
        'VideoCodec': 'h264,hevc,av1',
        'AudioCodec': 'aac,ac3,eac3,mp3,opus',
        'TranscodeSeekInfo': 'Auto',
        'CopyTimestamps': true,
      },
      {
        'Type': 'Audio',
        'Container': 'aac',
        'Protocol': 'http',
        'Context': 'Streaming',
        'AudioCodec': 'aac,mp3,opus,flac',
      },
    ],
    'SubtitleProfiles': [
      {'Format': 'subrip', 'Method': 'External'},
      {'Format': 'subrip', 'Method': 'Embed'},
      {'Format': 'srt', 'Method': 'External'},
      {'Format': 'srt', 'Method': 'Embed'},
      {'Format': 'ass', 'Method': 'External'},
      {'Format': 'ass', 'Method': 'Embed'},
      {'Format': 'ssa', 'Method': 'External'},
      {'Format': 'ssa', 'Method': 'Embed'},
      {'Format': 'vtt', 'Method': 'External'},
      {'Format': 'vtt', 'Method': 'Hls'},
      {'Format': 'webvtt', 'Method': 'External'},
      {'Format': 'webvtt', 'Method': 'Hls'},
      {'Format': 'pgs', 'Method': 'Embed'},
      {'Format': 'pgssub', 'Method': 'Embed'},
      {'Format': 'sup', 'Method': 'Embed'},
      {'Format': 'dvdsub', 'Method': 'Embed'},
      {'Format': 'sub', 'Method': 'Embed'},
      {'Format': 'idx', 'Method': 'Embed'},
    ],
  };
}
