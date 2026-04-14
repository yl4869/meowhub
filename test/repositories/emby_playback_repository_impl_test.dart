import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:meowhub/core/session/session_expired_notifier.dart';
import 'package:meowhub/data/datasources/emby_api_client.dart';
import 'package:meowhub/data/models/emby/emby_playback_info_dto.dart';
import 'package:meowhub/data/repositories/emby_playback_repository_impl.dart';
import 'package:meowhub/domain/entities/media_item.dart';
import 'package:meowhub/domain/entities/media_service_config.dart';

import '../mocks/mock_classes.dart';

class _FakeEmbyApiClient extends EmbyApiClient {
  _FakeEmbyApiClient({
    required super.config,
    required super.securityService,
    required super.sessionExpiredNotifier,
    required this.onGetPlaybackInfo,
  });

  final Future<EmbyPlaybackInfoDto> Function({
    required String itemId,
    int? maxStreamingBitrate,
    bool? requireAvc,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    String? mediaSourceId,
  })
  onGetPlaybackInfo;

  @override
  Future<EmbyPlaybackInfoDto> getPlaybackInfo({
    required String itemId,
    int? maxStreamingBitrate,
    bool? requireAvc,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    String? mediaSourceId,
  }) {
    return onGetPlaybackInfo(
      itemId: itemId,
      maxStreamingBitrate: maxStreamingBitrate,
      requireAvc: requireAvc,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      mediaSourceId: mediaSourceId,
    );
  }
}

void main() {
  late MockSecurityService securityService;
  late MediaServiceConfig config;
  late MediaItem item;

  setUp(() {
    EmbyPlaybackRepositoryImpl.clearPlaybackPlanCache();
    securityService = MockSecurityService();
    config = const MediaServiceConfig(
      type: MediaServiceType.emby,
      serverUrl: 'http://localhost:8096',
      username: 'demo',
      password: 'demo',
      deviceId: 'test-device',
    );
    item = const MediaItem(
      id: 1,
      title: 'Episode 1',
      originalTitle: 'Episode 1',
      type: MediaType.series,
      sourceId: 'ep-1',
      parentTitle: 'Season 1',
      indexNumber: 1,
    );
    when(
      () => securityService.readAccessToken(namespace: any(named: 'namespace')),
    ).thenAnswer((_) async => 'token');
  });

  test('同参数 PlaybackPlan 请求会复用进行中的请求和短时缓存', () async {
    final completer = Completer<EmbyPlaybackInfoDto>();
    var requestCount = 0;
    final apiClient = _FakeEmbyApiClient(
      config: config,
      securityService: securityService,
      sessionExpiredNotifier: SessionExpiredNotifier(),
      onGetPlaybackInfo:
          ({
            required String itemId,
            int? maxStreamingBitrate,
            bool? requireAvc,
            int? audioStreamIndex,
            int? subtitleStreamIndex,
            String? mediaSourceId,
          }) {
            requestCount += 1;
            return completer.future;
          },
    );
    final repo = EmbyPlaybackRepositoryImpl(
      apiClient: apiClient,
      securityService: securityService,
    );

    final futureA = repo.getPlaybackPlan(
      item,
      maxStreamingBitrate: 10 * 1000 * 1000,
      requireAvc: true,
    );
    final futureB = repo.getPlaybackPlan(
      item,
      maxStreamingBitrate: 10 * 1000 * 1000,
      requireAvc: true,
    );

    expect(requestCount, 1);

    completer.complete(
      const EmbyPlaybackInfoDto(
        playSessionId: 'session-1',
        mediaSources: [
          EmbyMediaSourceDto(
            id: 'source-1',
            supportsDirectPlay: true,
            mediaStreams: [
              EmbyMediaStreamDto(
                index: 0,
                type: 'Audio',
                displayTitle: 'Main Audio',
              ),
              EmbyMediaStreamDto(
                index: 1,
                type: 'Subtitle',
                displayTitle: 'Chinese',
                isTextSubtitleStream: true,
                deliveryUrl: '/emby/subtitles/1/stream.srt',
              ),
            ],
          ),
        ],
      ),
    );

    final planA = await futureA;
    final planB = await futureB;
    final cachedPlan = await repo.getPlaybackPlan(
      item,
      maxStreamingBitrate: 10 * 1000 * 1000,
      requireAvc: true,
    );

    expect(planA.url, planB.url);
    expect(planA.url, cachedPlan.url);
    expect(planA.subtitleStreams, isNotEmpty);
    expect(requestCount, 1);
  });
}
