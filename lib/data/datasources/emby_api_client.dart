import 'package:dio/dio.dart';
import 'package:meowhub/data/models/emby/emby_resume_item_dto.dart';

import '../../core/services/capability_prober.dart';
import '../../core/services/security_service.dart';
import '../../core/session/session_expired_notifier.dart';
import '../../core/utils/emby_ticks.dart';
import '../../domain/entities/media_service_config.dart';
import '../models/emby/emby_device_profile.dart';
import '../models/emby/emby_media_item_dto.dart';
import '../models/emby/emby_media_library_dto.dart';
import '../models/emby_auth_response.dart';
import '../network/emby_auth_interceptor.dart';
import '../models/emby/emby_playback_info_dto.dart';

/// 定义播放行为的类型
enum PlaybackAction {
  start, // 对应开始播放
  progress, // 对应进度更新
  stop, // 对应停止播放
}

const String _embyBaseItemFields =
    'Overview,OriginalTitle,RunTimeTicks,ProductionYear,CommunityRating,'
    'PremiereDate,DateCreated,People,ImageTags,BackdropImageTags,'
    'ParentThumbItemId,ParentThumbImageTag,ParentIndexNumber,IndexNumber,'
    'SeriesName,SeriesId,SeriesPrimaryImageTag,MediaSources,UserData';

/// Emby API 客户端封装。
/// 统一负责认证、基础 GET/POST、媒体库与影片列表接口访问。
class EmbyApiClient {
  // ✅ 将 config 改为 public (或者提供一个 public getter)
  final MediaServiceConfig config;

  EmbyApiClient({
    required this.config, // ✅ 使用 this.config 直接赋值
    required SecurityService securityService,
    required SessionExpiredNotifier sessionExpiredNotifier,
    CapabilityProber? capabilityProber,
    Dio? dio,
  }) : _config = config,
       _securityService = securityService,
       _capabilityProber = capabilityProber,
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
                 'User-Agent':
                     'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
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
  final CapabilityProber? _capabilityProber;
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
    try {
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
    } catch (error) {
      rethrow;
    }
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool withToken = true,
  }) async {
    if (withToken) {
      await _ensureSession();
    }

    try {
      final response = await _dio.get<T>(
        path,
        queryParameters: queryParameters,
      );
      return response;
    } catch (error) {
      rethrow;
    }
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
    try {
      final response = await _dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(headers: headers, extra: {'withToken': withToken}),
      );
      return response;
    } catch (error) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getSystemInfo() async {
    final response = await get<Map<String, dynamic>>('/emby/System/Info');
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getPublicSystemInfo() async {
    final response = await get<Map<String, dynamic>>(
      '/emby/System/Info/Public',
      withToken: false,
    );
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

  Future<List<EmbyMediaItemDto>> getSearchHints({
    required String searchTerm,
    String includeItemTypes = 'Movie,Series,Episode',
    int limit = 50,
  }) async {
    final userId = await _requireUserId();
    final response = await get<Map<String, dynamic>>(
      '/emby/Search/Hints',
      queryParameters: {
        'UserId': userId,
        'SearchTerm': searchTerm,
        'IncludeItemTypes': includeItemTypes,
        'Limit': '$limit',
        'EnableImages': true,
        'EnableImageTypes': 'Primary',
        'ImageTypeLimit': '1',
      },
    );
    final data = response.data ?? <String, dynamic>{};
    final hints = data['SearchHints'] as List<dynamic>? ?? const [];
    return hints.whereType<Map<String, dynamic>>().map((hint) {
      final normalized = Map<String, dynamic>.from(hint);
      final primaryTag = normalized.remove('PrimaryImageTag') as String?;
      if (primaryTag != null && primaryTag.isNotEmpty) {
        normalized['ImageTags'] = {'Primary': primaryTag};
      }
      final backdropTag =
          normalized.remove('BackdropImageTag') as String?;
      if (backdropTag != null && backdropTag.isNotEmpty) {
        normalized['BackdropImageTags'] = [backdropTag];
      }
      if (normalized['Series'] is String &&
          normalized['SeriesName'] == null) {
        normalized['SeriesName'] = normalized['Series'];
      }
      return EmbyMediaItemDto.fromJson(normalized);
    }).toList(growable: false);
  }

  Future<List<EmbyMediaItemDto>> getMediaItems({
    required String includeItemTypes,
    String? libraryId,
    int limit = 100,
    String? searchTerm,
  }) async {
    final userId = await _requireUserId();
    final response = await get<Map<String, dynamic>>(
      '/emby/Users/$userId/Items',
      queryParameters: {
        'UserId': userId,
        'Recursive': true,
        'IncludeItemTypes': includeItemTypes,
        if (searchTerm == null || searchTerm.isEmpty)
          'SortBy': 'DateCreated,SortName',
        if (searchTerm == null || searchTerm.isEmpty)
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
        if (searchTerm != null && searchTerm.isNotEmpty)
          'SearchTerm': searchTerm,
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
    EmbyDeviceProfile? deviceProfile,
    bool preferTranscoding = false,
  }) async {
    final userId = await _requireUserId();
    final runtimeCapabilities =
        (_capabilityProber?.snapshot ?? CapabilitySnapshot.fallback())
            .limitBitrate(maxStreamingBitrate);
    final effectiveMaxStreamingBitrate =
        runtimeCapabilities.maxStreamingBitrate;
    final resolvedProfile =
        deviceProfile ??
        EmbyProfileFactory.forCurrentPlatform(
          deviceId: _resolvedDeviceId,
          capabilities: runtimeCapabilities,
        );

    final playbackInfoQuery = {'UserId': userId};

    final body = <String, dynamic>{
      'UserId': userId,
      'DeviceId': _resolvedDeviceId,
      'ItemId': itemId,
      'MaxStreamingBitrate': effectiveMaxStreamingBitrate,
      'AudioStreamIndex': audioStreamIndex,
      'SubtitleStreamIndex': subtitleStreamIndex,
      'MediaSourceId': mediaSourceId,
      'PlaySessionId': playSessionId,
      'RequireAvc': requireAvc,
      'EnableDirectPlay': !preferTranscoding,
      'EnableDirectStream': !preferTranscoding,
      'EnableTranscoding': true,
      'EnablePlaybackRemuxing': !preferTranscoding,
      'AllowVideoStreamCopy': true,
      'AllowAudioStreamCopy': true,
      'DeviceProfile': resolvedProfile.toJson(),
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
    String? playSessionId,
  }) async {
    return buildSubtitleStreamUrl(
      itemId: itemId,
      streamIndex: streamIndex,
      mediaSourceId: mediaSourceId,
      deliveryUrl: deliveryUrl,
      codec: 'vtt',
      playSessionId: playSessionId,
    );
  }

  Future<String?> buildSubtitleStreamUrl({
    required String itemId,
    required int streamIndex,
    String? mediaSourceId,
    String? deliveryUrl,
    String? codec,
    String? playSessionId,
  }) async {
    final token =
        await _securityService.readAccessToken(
          namespace: _config.credentialNamespace,
        ) ??
        '';
    final normalizedCodec = (codec ?? 'vtt').trim().toLowerCase();
    final subtitleExtension = switch (normalizedCodec) {
      'subrip' => 'srt',
      'webvtt' => 'vtt',
      'pgs' => 'sup',
      'pgssub' => 'sup',
      final String value when value.isNotEmpty => value,
      _ => 'vtt',
    };
    final normalizedMediaSourceId = mediaSourceId?.trim();
    if (normalizedMediaSourceId != null && normalizedMediaSourceId.isNotEmpty) {
      final queryParameters = <String, String>{
        if (token.isNotEmpty) 'api_key': token,
        if (playSessionId != null && playSessionId.isNotEmpty)
          'PlaySessionId': playSessionId,
      };
      return Uri.parse(
        '$serverUrl/emby/Videos/$itemId/'
        '$normalizedMediaSourceId/Subtitles/$streamIndex/0/Stream.$subtitleExtension',
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
      'Stream.$subtitleExtension',
    );
    final queryParameters = Map<String, String>.from(uri.queryParameters);
    if (!queryParameters.containsKey('api_key') && token.isNotEmpty) {
      queryParameters['api_key'] = token;
    }
    if (!queryParameters.containsKey('PlaySessionId') &&
        playSessionId != null &&
        playSessionId.isNotEmpty) {
      queryParameters['PlaySessionId'] = playSessionId;
    }
    return uri
        .replace(
          path: rewrittenPath == uri.path
              ? '${uri.path}.$subtitleExtension'
              : rewrittenPath,
          queryParameters: queryParameters,
        )
        .toString();
  }

  Future<List<EmbyMediaItemDto>> getEpisodes(
    String seriesId, {
    int limit = 100,
    int startIndex = 0,
    int? seasonNumber,
  }) async {
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
        'SortBy': 'ParentIndexNumber,IndexNumber',
        'SortOrder': 'Ascending',
        'StartIndex': '$startIndex',
        'Limit': '$limit',
        if (seasonNumber != null) 'SeasonNumber': '$seasonNumber',
      },
    );
    final data = response.data ?? <String, dynamic>{};
    final items = data['Items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(EmbyMediaItemDto.fromJson)
        .toList(growable: false);
  }

  Future<List<EmbyMediaItemDto>> getSeasons(String seriesId) async {
    final userId = await _requireUserId();
    final response = await get<Map<String, dynamic>>(
      '/emby/Shows/$seriesId/Seasons',
      queryParameters: {
        'UserId': userId,
        'EnableImages': true,
        'EnableImageTypes': 'Primary',
        'ImageTypeLimit': '1',
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

  Future<List<EmbyResumeItemDto>> getContinueWatching() async {
    try {
      final userId = await _requireUserId();
      final queryParameters = <String, dynamic>{
        'Limit': '50',
        'StartIndex': '0',
        'EnableImages': true,
        'EnableImageTypes': 'Primary,Backdrop,Thumb',
        'ImageTypeLimit': '1',
        'EnableUserData': true,
        'IncludeItemTypes': 'Movie,Episode',
        'Fields': _embyBaseItemFields,
      };

      final response = await get<dynamic>(
        '/emby/Users/$userId/Items/Resume',
        queryParameters: queryParameters,
      );

      final rawData = response.data;
      final items = switch (rawData) {
        final Map<String, dynamic> map =>
          map['Items'] as List<dynamic>? ?? const [],
        final List<dynamic> list => list,
        _ => const <dynamic>[],
      };

      return items
          .whereType<Map<String, dynamic>>()
          .map((json) => EmbyResumeItemDto.fromJson(json, serverUrl: serverUrl))
          .toList(growable: false);
    } catch (error) {
      rethrow;
    }
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
    final normalizedPlaySessionId = playSessionId?.trim();
    if (normalizedPlaySessionId == null || normalizedPlaySessionId.isEmpty) {
      return;
    }
    final userId = await _requireUserId();
    // 1. 构造统一的 Body
    final body = _buildPlaybackStateBody(
      userId: userId,
      itemId: itemId,
      position: position,
      duration: duration,
      isPaused: false,
      playSessionId: normalizedPlaySessionId,
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
      await post<void>(
        '/emby/Users/$userId/PlayingItems/$itemId',
        queryParameters: _buildLegacyPlaybackStateQuery(
          position: position,
          duration: duration,
          isPaused: false,
          playSessionId: normalizedPlaySessionId,
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
    try {
      if (await _hasUsableSession()) {
        return;
      }

      await authenticate();
    } catch (error) {
      rethrow;
    }
  }

  Future<String> _requireUserId() async {
    try {
      await _ensureSession();
      final userId = await _securityService.readUserId(
        namespace: _config.credentialNamespace,
      );
      if (userId != null && userId.isNotEmpty) {
        return userId;
      }
      throw Exception('Emby 登录后未能获取到用户 ID');
    } catch (error) {
      rethrow;
    }
  }

  Future<bool> _hasUsableSession() async {
    try {
      final accessToken = await _securityService.readAccessToken(
        namespace: _config.credentialNamespace,
      );
      final userId = await _securityService.readUserId(
        namespace: _config.credentialNamespace,
      );
      final result =
          accessToken?.isNotEmpty == true && userId?.isNotEmpty == true;
      return result;
    } catch (error) {
      rethrow;
    }
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
