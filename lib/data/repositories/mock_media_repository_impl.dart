import 'package:flutter/foundation.dart';

import '../../domain/entities/media_item.dart';
import '../../domain/entities/watch_history_item.dart';
import '../../domain/repositories/i_media_repository.dart';

/// Refactor reason:
/// All mock data is centralized here, making the composition root the only
/// place that decides whether the app runs against mock or remote data.
class MockMediaRepositoryImpl implements IMediaRepository {
  const MockMediaRepositoryImpl();

  static const Duration _networkDelay = Duration(milliseconds: 250);

  @override
  Future<List<MediaItem>> getMovies() async {
    if (kDebugMode) {
      debugPrint('[Diag][MockMediaRepository] getMovies');
    }
    await Future.delayed(_networkDelay);
    return _movieFixtures;
  }

  @override
  Future<List<MediaItem>> getSeries() async {
    if (kDebugMode) {
      debugPrint('[Diag][MockMediaRepository] getSeries');
    }
    await Future.delayed(_networkDelay);
    return _seriesFixtures;
  }

  @override
  Future<MediaItem> getMediaDetail(MediaItem item) async {
    if (kDebugMode) {
      debugPrint(
        '[Diag][MockMediaRepository] getMediaDetail | '
        'itemId=${item.dataSourceId}',
      );
    }
    await Future.delayed(_networkDelay);

    final detail = [
      ..._movieFixtures,
      ..._seriesFixtures,
    ].firstWhere((candidate) => candidate.id == item.id, orElse: () => item);

    return detail.copyWith(
      playableItems: item.type == MediaType.series
          ? [
              for (var index = 1; index <= 8; index++)
                MediaItem(
                  id: detail.id * 100 + index,
                  sourceId: '${detail.dataSourceId}-ep-$index',
                  title: '第 $index 集',
                  originalTitle: detail.originalTitle,
                  type: MediaType.series,
                  sourceType: detail.sourceType,
                  posterUrl: detail.posterUrl,
                  backdropUrl: detail.backdropUrl,
                  rating: detail.rating,
                  year: detail.year,
                  overview: '${detail.title} 第 $index 集',
                  playUrl: detail.playUrl,
                  parentTitle: detail.title,
                  parentIndexNumber: 1,
                  indexNumber: index,
                ),
            ]
          : [detail],
      cast: const [
        Cast(
          name: '测试主演',
          characterName: '主角',
          avatarUrl: 'https://picsum.photos/seed/mock-cast-1/120/120',
        ),
        Cast(
          name: '测试配角',
          characterName: '关键角色',
          avatarUrl: 'https://picsum.photos/seed/mock-cast-2/120/120',
        ),
      ],
    );
  }

  @override
  Future<List<MediaItem>> getPlayableItems(MediaItem item) async {
    if (kDebugMode) {
      debugPrint(
        '[Diag][MockMediaRepository] getPlayableItems | '
        'itemId=${item.dataSourceId}',
      );
    }
    final detail = await getMediaDetail(item);
    return detail.playableItems.isEmpty ? [detail] : detail.playableItems;
  }
}

final List<MediaItem> _movieFixtures = [
  MediaItem(
    id: 1001,
    title: '测试视频',
    originalTitle: 'Neon Alley',
    type: MediaType.movie,
    sourceType: WatchSourceType.local,
    posterUrl: _posterUrl('movie-1'),
    backdropUrl: _backdropUrl('movie-1'),
    rating: 8.7,
    year: 2024,
    overview: '一位落魄侦探在霓虹闪烁的旧城区追查连环失踪案。',
    isFavorite: true,
    playUrl: 'http://vjs.zencdn.net/v/oceans.mp4',
  ),
  MediaItem(
    id: 1002,
    title: 'Moonlit Harbor',
    originalTitle: 'Moonlit Harbor',
    type: MediaType.movie,
    sourceType: WatchSourceType.local,
    posterUrl: _posterUrl('movie-2'),
    backdropUrl: _backdropUrl('movie-2'),
    rating: 8.2,
    year: 2023,
    overview: '风暴夜里，一座港口小城埋藏多年的秘密逐渐浮出水面。',
    playUrl: 'http://vjs.zencdn.net/v/oceans.mp4',
  ),
];

final List<MediaItem> _seriesFixtures = [
  MediaItem(
    id: 2001,
    title: 'City of Whiskers',
    originalTitle: 'City of Whiskers',
    type: MediaType.series,
    sourceType: WatchSourceType.local,
    posterUrl: _posterUrl('series-1'),
    backdropUrl: _backdropUrl('series-1'),
    rating: 8.9,
    year: 2024,
    overview: '五位性格迥异的年轻人在都市里合租，慢慢成为彼此的家人。',
    isFavorite: true,
    playUrl: 'http://vjs.zencdn.net/v/oceans.mp4',
  ),
  MediaItem(
    id: 2002,
    title: 'Signal 404',
    originalTitle: 'Signal 404',
    type: MediaType.series,
    sourceType: WatchSourceType.local,
    posterUrl: _posterUrl('series-2'),
    backdropUrl: _backdropUrl('series-2'),
    rating: 8.3,
    year: 2023,
    overview: '一组网络安全调查员追踪神秘信号源，意外牵出跨国阴谋。',
    playUrl: 'http://vjs.zencdn.net/v/oceans.mp4',
  ),
];

String _posterUrl(String seed) {
  return 'https://picsum.photos/seed/$seed-poster/300/450';
}

String _backdropUrl(String seed) {
  return 'https://picsum.photos/seed/$seed-backdrop/1280/720';
}
