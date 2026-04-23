import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/services/security_service.dart';
import '../../core/session/session_expired_notifier.dart';
import '../../core/utils/emby_ticks.dart';
import '../../domain/entities/media_service_config.dart';
import '../models/emby/emby_media_item_dto.dart';
import '../models/emby/emby_media_library_dto.dart';
import '../models/emby_auth_response.dart';
import '../network/emby_auth_interceptor.dart';
import '../models/emby/emby_playback_info_dto.dart';

/// 定义播放行为的类型
enum PlaybackAction { 
  start,    // 对应开始播放
  progress, // 对应进度更新
  stop      // 对应停止播放
}

const String _embyBaseItemFields =
    'Overview,OriginalTitle,RunTimeTicks,ProductionYear,CommunityRating,'
    'PremiereDate,DateCreated,People,ImageTags,BackdropImageTags,'
    'ParentThumbItemId,ParentThumbImageTag,ParentIndexNumber,IndexNumber,'
    'SeriesName,SeriesId,SeriesPrimaryImageTag,MediaSources,UserData';

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
                 // 关键修改 A：将 User-Agent 伪装成浏览器
                 'User-Agent':
                     'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                 // 关键修改 B：完全模仿网页端的 Authorization 格式
                 'X-Emby-Authorization':
                     'MediaBrowser Client="Emby Web", Device="Firefox", DeviceId="${_normalizeDeviceId(config.deviceId)}", Version="4.8.10.0"',
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
        'UserId': userId,
        'Recursive': true,
        'IncludeItemTypes': includeItemTypes,
        'SortBy': 'DateCreated,SortName',
        'SortOrder': 'Descending',
        'EnableImages': true,
        'EnableImageTypes': 'Primary,Backdrop,Thumb',
        'ImageTypeLimit': '1',
        'EnableUserData': true,
        'EnableTotalRecordCount': true,
        'Fields': _embyBaseItemFields,
        'StartIndex': '0',
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
      queryParameters: {
        'UserId': userId,
        'EnableImages': true,
        'EnableImageTypes': 'Primary,Backdrop,Thumb',
        'ImageTypeLimit': '1',
        'EnableUserData': true,
        'Fields': _embyBaseItemFields,
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
    String? playSessionId,
    Duration startPosition = Duration.zero,
  }) async {
    final userId = await _requireUserId();
    final effectiveMaxStreamingBitrate =
        maxStreamingBitrate ?? 1000 * 1000 * 1000;
    final startTimeTicks = durationToEmbyTicks(startPosition);

    // 1. 【极致精简】Query 只保留 UserId
    // 其余标识符已经在 Dio 的拦截器或 Header 中处理了
    final playbackInfoQuery = {
      'UserId': userId,
      'reqformat': 'json',
    };
    
    // 2. 【统一管控】所有参数全部放入 Body
    final body = <String, dynamic>{
      'UserId': userId,
      'DeviceId': _resolvedDeviceId,
      'ItemId': itemId,
      'StartTimeTicks': startTimeTicks,
      'MaxStreamingBitrate': effectiveMaxStreamingBitrate,
      'AudioStreamIndex': audioStreamIndex,
      'SubtitleStreamIndex': subtitleStreamIndex,
      'MediaSourceId': mediaSourceId,
      'PlaySessionId': playSessionId,
      'RequireAvc': requireAvc ?? true,
      // 这里的布尔值开关，统一在这里声明，清晰明了
      'EnableDirectPlay': true,
      'EnableDirectStream': true,
      'EnableTranscoding': true,
      'EnablePlaybackRemuxing': true,
      'AllowVideoStreamCopy': true,
      'AllowAudioStreamCopy': true,
      'SubtitleMethod': 'External', // 强制外挂，避开烧录
      'DeviceProfile': _buildMediaKitDeviceProfile(
        deviceId: _resolvedDeviceId,
        maxStreamingBitrate: effectiveMaxStreamingBitrate,
      ),
    };

    final resp = await post<Map<String, dynamic>>(
      '/emby/Items/$itemId/PlaybackInfo',
      data: body,
      queryParameters: playbackInfoQuery,
    );

    return EmbyPlaybackInfoDto.fromJson(resp.data ?? {});
  }

  Future<String?> buildSubtitleVttUrl({
    required String itemId,
    required int streamIndex,
    String? mediaSourceId,
    String? deliveryUrl,
  }) async {
    final token =
        await _securityService.readAccessToken(
          namespace: _config.credentialNamespace,
        ) ??
        '';
    final normalizedMediaSourceId = mediaSourceId?.trim();
    if (normalizedMediaSourceId != null && normalizedMediaSourceId.isNotEmpty) {
      final queryParameters = <String, String>{
        if (token.isNotEmpty) 'api_key': token,
      };
      return Uri.parse(
        '$serverUrl/emby/Videos/$itemId/'
        '$normalizedMediaSourceId/Subtitles/$streamIndex/0/Stream.vtt',
      ).replace(queryParameters: queryParameters).toString();
    }

    final rawDeliveryUrl = deliveryUrl?.trim();
    if (rawDeliveryUrl == null || rawDeliveryUrl.isEmpty) {
      return null;
    }
    final isAbsolute =
        rawDeliveryUrl.startsWith('http://') ||
        rawDeliveryUrl.startsWith('https://');
    final base = isAbsolute ? rawDeliveryUrl : '$serverUrl$rawDeliveryUrl';
    final uri = Uri.parse(base);
    final rewrittenPath = uri.path.replaceFirst(
      RegExp(r'Stream\.[^/?.]+$'),
      'Stream.vtt',
    );
    final queryParameters = Map<String, String>.from(uri.queryParameters);
    if (!queryParameters.containsKey('api_key') && token.isNotEmpty) {
      queryParameters['api_key'] = token;
    }
    return uri
        .replace(
          path: rewrittenPath == uri.path ? '${uri.path}.vtt' : rewrittenPath,
          queryParameters: queryParameters,
        )
        .toString();
  }

  Future<List<EmbyMediaItemDto>> getEpisodes(String seriesId) async {
    final userId = await _requireUserId();
    final response = await get<Map<String, dynamic>>(
      '/emby/Shows/$seriesId/Episodes',
      queryParameters: {
        'UserId': userId,
        'EnableImages': true,
        'EnableImageTypes': 'Primary,Backdrop,Thumb',
        'ImageTypeLimit': '1',
        'EnableUserData': true,
        'Fields': _embyBaseItemFields,
      },
    );
    final data = response.data ?? <String, dynamic>{};
    final items = data['Items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(EmbyMediaItemDto.fromJson)
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getRecentlyWatchedItems() async {
    final userId = await _requireUserId();
    debugPrint(
      '[Recent][Emby][Request] userId=$userId path=/emby/Users/$userId/Items',
    );
    try {
      return await _fetchRecentlyWatchedItems(
        userId: userId,
        queryParameters: <String, dynamic>{
          'UserId': userId,
          'Limit': '20',
          'StartIndex': '0',
          'Recursive': true,
          'SortBy': 'DatePlayed',
          'SortOrder': 'Descending',
          'EnableImages': true,
          'EnableImageTypes': 'Primary,Backdrop,Thumb',
          'ImageTypeLimit': '1',
          'EnableUserData': true,
          'EnableTotalRecordCount': true,
          'IncludeItemTypes': 'Movie,Episode',
          'Fields': _embyBaseItemFields,
        },
      );
    } on DioException catch (e) {
      debugPrint(
        '[Recent][Emby][Error] userId=$userId '
        'status=${e.response?.statusCode} '
        'message=${e.message}',
      );
      debugPrint(
        '[Recent][Emby][ErrorBody] userId=$userId body=${e.response?.data}',
      );
      rethrow;
    } catch (e) {
      debugPrint('[Recent][Emby][Error] userId=$userId error=$e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRecentlyWatchedItems({
    required String userId,
    required Map<String, dynamic> queryParameters,
  }) async {
    final response = await get<Map<String, dynamic>>(
      '/emby/Users/$userId/Items',
      queryParameters: queryParameters,
    );
    final data = response.data ?? <String, dynamic>{};
    final items = data['Items'] as List<dynamic>? ?? const [];
    debugPrint(
      '[Recent][Emby][Response] userId=$userId count=${items.length} query=$queryParameters',
    );
    return items.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<void> reportPlaybackAction({
  required PlaybackAction action,
  required String itemId,
  required Duration position,
  Duration duration = Duration.zero,
  String? playSessionId,
  String? mediaSourceId,
  int? audioStreamIndex,
  int? subtitleStreamIndex,
}) async {
  final userId = await _requireUserId();
  final isStopped = action == PlaybackAction.stop;
  
  // 1. 构造统一的 Body
  final body = _buildPlaybackStateBody(
    userId: userId,
    itemId: itemId,
    position: position,
    duration: duration,
    isPaused: isStopped, // 只有停止时设为 true
    playSessionId: playSessionId,
    mediaSourceId: mediaSourceId,
    audioStreamIndex: audioStreamIndex,
    subtitleStreamIndex: subtitleStreamIndex,
  );

  // 2. 根据动作确定 URL 路径
  // start -> /emby/Sessions/Playing
  // progress -> /emby/Sessions/Playing/Progress
  // stop -> /emby/Sessions/Playing/Stopped
  final String subPath = switch (action) {
    PlaybackAction.start => '',
    PlaybackAction.progress => '/Progress',
    PlaybackAction.stop => '/Stopped',
  };
  final primaryPath = '/emby/Sessions/Playing$subPath';

  try {
    await post<void>(primaryPath, data: body);
  } on DioException catch (e) {
    if (!_isUnsupportedPlaybackEndpoint(e)) rethrow;
    
    // 3. 统一的降级处理（针对旧版 Emby/Jellyfin）
    debugPrint('[Playback] Fallback to legacy endpoint for $action');
    await post<void>(
      '/emby/Users/$userId/PlayingItems/$itemId',
      queryParameters: _buildLegacyPlaybackStateQuery(
        position: position,
        duration: duration,
        isPaused: isStopped,
        playSessionId: playSessionId,
        mediaSourceId: mediaSourceId,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      ),
      data: body,
    );
  }
}

  Map<String, dynamic> _buildPlaybackStateBody({
    required String userId,
    required String itemId,
    required Duration position,
    required Duration duration,
    required bool isPaused,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    final body = <String, dynamic>{
      'UserId': userId,
      'ItemId': itemId,
      'PositionTicks': durationToEmbyTicks(position),
      'CanSeek': true,
      'IsPaused': isPaused,
      'IsMuted': false,
      'PlaybackRate': 1,
      'RepeatMode': 'RepeatNone',
      'VolumeLevel': 100,
    };
    if (duration > Duration.zero) {
      body['RunTimeTicks'] = durationToEmbyTicks(duration);
    }
    if (playSessionId != null && playSessionId.isNotEmpty) {
      body['PlaySessionId'] = playSessionId;
    }
    if (mediaSourceId != null && mediaSourceId.isNotEmpty) {
      body['MediaSourceId'] = mediaSourceId;
    }
    if (audioStreamIndex != null) {
      body['AudioStreamIndex'] = audioStreamIndex;
    }
    if (subtitleStreamIndex != null) {
      body['SubtitleStreamIndex'] = subtitleStreamIndex;
    }
    return body;
  }

  Map<String, dynamic> _buildLegacyPlaybackStateQuery({
    required Duration position,
    required Duration duration,
    required bool isPaused,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    final query = <String, dynamic>{
      'PositionTicks': durationToEmbyTicks(position).toString(),
      'CanSeek': 'true',
      'IsPaused': isPaused.toString(),
    };
    if (duration > Duration.zero) {
      query['RunTimeTicks'] = durationToEmbyTicks(duration).toString();
    }
    if (playSessionId != null && playSessionId.isNotEmpty) {
      query['PlaySessionId'] = playSessionId;
    }
    if (mediaSourceId != null && mediaSourceId.isNotEmpty) {
      query['MediaSourceId'] = mediaSourceId;
    }
    if (audioStreamIndex != null) {
      query['AudioStreamIndex'] = '$audioStreamIndex';
    }
    if (subtitleStreamIndex != null) {
      query['SubtitleStreamIndex'] = '$subtitleStreamIndex';
    }
    return query;
  }

  bool _isUnsupportedPlaybackEndpoint(DioException error) {
    final statusCode = error.response?.statusCode;
    return statusCode == 400 ||
        statusCode == 404 ||
        statusCode == 405 ||
        statusCode == 501;
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
  const subtitleFormats =
      'srt,subrip,ass,ssa,vtt,webvtt,pgs,pgssub,sup,dvdsub,sub,idx';

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
    'DirectStreamProfiles': [
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
      _buildTimestampSafeTranscodingProfile(
        container: 'ts',
        protocol: 'hls',
        context: 'Streaming',
        videoCodec: 'h264,hevc,av1,vp9',
        audioCodec: 'aac,ac3,eac3,mp3,opus,flac',
        manifestSubtitles: 'vtt',
      ),
      _buildTimestampSafeTranscodingProfile(
        container: 'ts',
        protocol: 'http',
        context: 'Streaming',
        videoCodec: 'h264,hevc,av1,vp9',
        audioCodec: 'aac,ac3,eac3,mp3,opus,flac',
      ),
      _buildTimestampSafeTranscodingProfile(
        container: 'mp4',
        protocol: 'http',
        context: 'Static',
        videoCodec: 'h264,hevc,av1',
        audioCodec: 'aac,ac3,eac3,mp3,opus',
      ),
      {
        'Type': 'Audio',
        'Container': 'aac',
        'Protocol': 'http',
        'Context': 'Streaming',
        'AudioCodec': 'aac,mp3,opus,flac',
      },
    ],
    'ResponseProfiles': [
      {'Type': 'Video', 'Container': 'ts', 'MimeType': 'video/mp2t'},
      {'Type': 'Video', 'Container': 'mp4', 'MimeType': 'video/mp4'},
      {'Type': 'Audio', 'Container': 'aac', 'MimeType': 'audio/aac'},
    ],
    'ContainerProfiles': [
      {
        'Type': 'Video',
        'Container': 'matroska,webm',
        'Conditions': [
          {
            'Condition': 'EqualsAny',
            'Property': 'NumVideoStreams',
            'Value': '1',
            'IsRequired': false,
          },
        ],
      },
    ],
    'CodecProfiles': [
      {
        'Type': 'Video',
        'Codec': 'h264,hevc,av1,vp9',
        'Conditions': [
          {
            'Condition': 'LessThanEqual',
            'Property': 'VideoBitDepth',
            'Value': '10',
            'IsRequired': false,
          },
        ],
      },
      {
        'Type': 'VideoAudio',
        'Codec': 'aac,ac3,eac3,mp3,opus,flac',
        'Conditions': [
          {
            'Condition': 'LessThanEqual',
            'Property': 'AudioChannels',
            'Value': '8',
            'IsRequired': false,
          },
        ],
      },
    ],
    'SubtitleProfiles': [
      {'Format': 'subrip', 'Method': 'External'},
      {'Format': 'srt', 'Method': 'External'},
      {'Format': 'ass', 'Method': 'External'},
      {'Format': 'ssa', 'Method': 'External'},
      {'Format': 'vtt', 'Method': 'External'},
      {'Format': 'webvtt', 'Method': 'External'},
      {'Format': 'pgs', 'Method': 'External'},
      {'Format': 'pgssub', 'Method': 'External'},
      {'Format': 'sup', 'Method': 'External'},
      {'Format': 'dvdsub', 'Method': 'External'},
      {'Format': 'sub', 'Method': 'External'},
      {'Format': 'idx', 'Method': 'External'},
    ],
    'SupportedSubtitles': subtitleFormats,
  };
}

Map<String, dynamic> _buildTimestampSafeTranscodingProfile({
  required String container,
  required String protocol,
  required String context,
  required String videoCodec,
  required String audioCodec,
  String? manifestSubtitles,
}) {
  return <String, dynamic>{
    'Type': 'Video',
    'Container': container,
    'Protocol': protocol,
    'Context': context,
    'VideoCodec': videoCodec,
    'AudioCodec': audioCodec,
    // 关键修改 A：声明支持自动寻址，触发 FFmpeg 的 -ss
    'TranscodeSeekInfo': 'Auto',
    // 关键修改 B：必须为 true，让服务器移除 -start_at_zero
    'CopyTimestamps': true,
    'BreakOnNonKeyFrames': true, // 提高切片效率
    'MinSegments': 1,
    'SegmentLength': 3,
    // 关键修改 C：必须为 false，解决之前的 500 错误
    'EnableMpegtsM2TsMode': false,
    'ManifestSubtitles': manifestSubtitles,
  };
}
