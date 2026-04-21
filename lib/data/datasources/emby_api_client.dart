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
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
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
        maxStreamingBitrate ?? 1000 * 1000 * 1000;;
    final startTimeTicks = durationToEmbyTicks(startPosition);

    final playbackInfoQuery = <String, dynamic>{
      'UserId': userId,
      'StartTimeTicks': startTimeTicks.toString(),
      'IsPlayback': 'true',
      'AutoOpenLiveStream': 'true',
      'MaxStreamingBitrate': '$effectiveMaxStreamingBitrate',
      'X-Emby-Client': 'Emby Web', // 即使不改构造函数，这里建议也先填 Web 以绕过服务端限制
      'X-Emby-Device-Name': 'MeowHub Player',
      'X-Emby-Device-Id': _resolvedDeviceId,
      'X-Emby-Client-Version': '4.8.10.0', // 对齐一个标准的稳定版号
      'reqformat': 'json',
    };
    final optionalBody = <String, dynamic>{};
    void putIfPresent(String key, Object? value) {
      if (value != null) {
        optionalBody[key] = value;
      }
    }

    optionalBody['MaxStreamingBitrate'] = effectiveMaxStreamingBitrate;
    putIfPresent('RequireAvc', requireAvc);
    putIfPresent('AudioStreamIndex', audioStreamIndex);
    putIfPresent('SubtitleStreamIndex', subtitleStreamIndex);
    putIfPresent('MediaSourceId', mediaSourceId);
    putIfPresent('PlaySessionId', playSessionId);
    if (requireAvc != null) {
      playbackInfoQuery['RequireAvc'] = requireAvc.toString();
    }
    if (audioStreamIndex != null) {
      playbackInfoQuery['AudioStreamIndex'] = '$audioStreamIndex';
    }
    if (subtitleStreamIndex != null) {
      playbackInfoQuery['SubtitleStreamIndex'] = '$subtitleStreamIndex';
    }
    if (mediaSourceId != null && mediaSourceId.isNotEmpty) {
      playbackInfoQuery['MediaSourceId'] = mediaSourceId;
    }
    if (playSessionId != null && playSessionId.isNotEmpty) {
      playbackInfoQuery['PlaySessionId'] = playSessionId;
    }
    if (startPosition > Duration.zero) {
      final startTimeTicks = durationToEmbyTicks(startPosition);
      optionalBody['StartTimeTicks'] = startTimeTicks;
      playbackInfoQuery['StartTimeTicks'] = '$startTimeTicks';
    }
    final body = <String, dynamic>{
      'UserId': userId,
      'DeviceId': _resolvedDeviceId,
      'StartTimeTicks': startTimeTicks, // 确保 Body 里的 Ticks 也是正确的 int
      'EnableDirectPlay': true,
      'EnableDirectStream': true,
      'EnableTranscoding': true,
      'EnablePlaybackRemuxing': true,
      'EnableSubtitlesInManifest': true,
      'AutoOpenLiveStream': true,
      'AllowInterlacedVideoStreamCopy': true,
      'AllowVideoStreamCopy': true,
      'AllowAudioStreamCopy': true,
      'MaxAudioChannels': 8,
      'TranscodingMaxAudioChannels': 8,
      'IsPlayback': true,
      ...optionalBody,
      'DeviceProfile': _buildMediaKitDeviceProfile(
        deviceId: _resolvedDeviceId,
        maxStreamingBitrate: effectiveMaxStreamingBitrate,
    ),
    };
    final resp = await post<Map<String, dynamic>>(
      '/emby/Items/$itemId/PlaybackInfo',
      data: body,
      queryParameters: playbackInfoQuery,
      headers: {
        'X-Emby-Device-Id': _resolvedDeviceId,
        // 关键：在请求头里也补全授权信息
        'X-Emby-Authorization': 'MediaBrowser Client="Emby Web", Device="MeowHub Player", DeviceId="$_resolvedDeviceId", Version="4.8.10.0"',
      },
    );
    final data = resp.data ?? <String, dynamic>{};
    return EmbyPlaybackInfoDto.fromJson(data);
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

  Future<void> reportPlaybackProgress({
    required String itemId,
    required Duration position,
    Duration duration = Duration.zero,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    final userId = await _requireUserId();
    final body = _buildPlaybackStateBody(
      userId: userId,
      itemId: itemId,
      position: position,
      duration: duration,
      isPaused: false,
      playSessionId: playSessionId,
      mediaSourceId: mediaSourceId,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
    );
    try {
      await post<void>('/emby/Sessions/Playing/Progress', data: body);
    } on DioException catch (e) {
      if (!_isUnsupportedPlaybackEndpoint(e)) {
        rethrow;
      }
      debugPrint(
        '[Resume][Emby][Progress] fallback=legacy-user-endpoint '
        'status=${e.response?.statusCode}',
      );
      await post<void>(
        '/emby/Users/$userId/PlayingItems/$itemId',
        queryParameters: _buildLegacyPlaybackStateQuery(
          position: position,
          duration: duration,
          isPaused: false,
          playSessionId: playSessionId,
          mediaSourceId: mediaSourceId,
          audioStreamIndex: audioStreamIndex,
          subtitleStreamIndex: subtitleStreamIndex,
        ),
        data: body,
      );
    }
  }

  Future<void> reportPlaybackStopped({
    required String itemId,
    required Duration position,
    Duration duration = Duration.zero,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    final userId = await _requireUserId();
    final body = _buildPlaybackStateBody(
      userId: userId,
      itemId: itemId,
      position: position,
      duration: duration,
      isPaused: true,
      playSessionId: playSessionId,
      mediaSourceId: mediaSourceId,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
    );
    try {
      await post<void>('/emby/Sessions/Playing/Stopped', data: body);
    } on DioException catch (e) {
      if (!_isUnsupportedPlaybackEndpoint(e)) {
        rethrow;
      }
      debugPrint(
        '[Resume][Emby][Stopped] fallback=legacy-user-endpoint '
        'status=${e.response?.statusCode}',
      );
      await post<void>(
        '/emby/Users/$userId/PlayingItems/$itemId',
        queryParameters: _buildLegacyPlaybackStateQuery(
          position: position,
          duration: duration,
          isPaused: true,
          playSessionId: playSessionId,
          mediaSourceId: mediaSourceId,
          audioStreamIndex: audioStreamIndex,
          subtitleStreamIndex: subtitleStreamIndex,
        ),
        data: body,
      );
    }
  }

  Future<void> reportPlaybackStarted({
    required String itemId,
    required Duration position,
    Duration duration = Duration.zero,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    final userId = await _requireUserId();
    final body = _buildPlaybackStateBody(
      userId: userId,
      itemId: itemId,
      position: position,
      duration: duration,
      isPaused: false,
      playSessionId: playSessionId,
      mediaSourceId: mediaSourceId,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
    );
    try {
      await post<void>('/emby/Sessions/Playing', data: body);
    } on DioException catch (e) {
      if (!_isUnsupportedPlaybackEndpoint(e)) {
        rethrow;
      }
      debugPrint(
        '[Resume][Emby][Start] fallback=legacy-user-endpoint '
        'status=${e.response?.statusCode}',
      );
      await post<void>(
        '/emby/Users/$userId/PlayingItems/$itemId',
        queryParameters: _buildLegacyPlaybackStateQuery(
          position: position,
          duration: duration,
          isPaused: false,
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
  const subtitleFormats = 'srt,subrip,ass,ssa,vtt,webvtt,pgs,pgssub,sup,dvdsub,sub,idx';

  return <String, dynamic>{
    'Name': 'MeowHub media_kit',
    'Id': deviceId,
    'SupportedMediaTypes': 'Video,Audio',
    'MaxStreamingBitrate': maxStreamingBitrate,
    'MaxStaticBitrate': maxStreamingBitrate,
    'MusicStreamingTranscodingBitrate': 384000,
    'MaxStaticMusicBitrate': maxStreamingBitrate,
    'SubtitleProfiles': [
      // 关键：声明我们支持所有主流格式的“外部”加载，防止服务器强制转码烧录字幕
      {'Format': 'srt', 'Method': 'External'},
      {'Format': 'ass', 'Method': 'External'},
      {'Format': 'ssa', 'Method': 'External'},
      {'Format': 'vtt', 'Method': 'External'},
      {'Format': 'pgs', 'Method': 'Embed'}, // PGS 改为内嵌，不强制烧录
      {'Format': 'pgssub', 'Method': 'Embed'},
      {'Format': 'subrip', 'Method': 'External'},
    ],
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
      {
        'Type': 'Video',
        'Container': 'ts',
        'MimeType': 'video/mp2t',
      },
      {
        'Type': 'Video',
        'Container': 'mp4',
        'MimeType': 'video/mp4',
      },
      {
        'Type': 'Audio',
        'Container': 'aac',
        'MimeType': 'audio/aac',
      },
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
