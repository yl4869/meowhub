import '../models/media_item.dart';

class MockMediaService {
  const MockMediaService();

  static const Duration _networkDelay = Duration(milliseconds: 500);

  Future<List<MediaItem>> getTrendingMovies() async {
    await Future.delayed(_networkDelay);

    return _trendingMoviesJson.map(MediaItem.fromJson).toList();
  }

  Future<List<MediaItem>> getSeriesList() async {
    await Future.delayed(_networkDelay);

    return _seriesListJson.map(MediaItem.fromJson).toList();
  }

  static final List<Map<String, dynamic>> _trendingMoviesJson = [
    {
      'id': 1001,
      'title': '测试视频',
      'originalTitle': 'Neon Alley',
      'type': 'movie',
      'posterUrl': _posterUrl('movie-1'),
      'backdropUrl': _backdropUrl('movie-1'),
      'rating': 8.7,
      'year': 2024,
      'overview': '一位落魄侦探在霓虹闪烁的旧城区追查连环失踪案。',
      'isFavorite': true,
      'playUrl': 'https://media.w3.org/2010/05/sintel/trailer.mp4',
      'cast': _cast('Neon Alley'),
    },
    {
      'id': 1002,
      'title': 'Moonlit Harbor',
      'originalTitle': 'Moonlit Harbor',
      'type': 'movie',
      'posterUrl': _posterUrl('movie-2'),
      'backdropUrl': _backdropUrl('movie-2'),
      'rating': 8.2,
      'year': 2023,
      'overview': '风暴夜里，一座港口小城埋藏多年的秘密逐渐浮出水面。',
      'isFavorite': false,
      'playUrl': 'https://example.com/play/movie-2',
      'cast': _cast('Moonlit Harbor'),
    },
    {
      'id': 1003,
      'title': 'The Last Cat Cafe',
      'originalTitle': 'The Last Cat Cafe',
      'type': 'movie',
      'posterUrl': _posterUrl('movie-3'),
      'backdropUrl': _backdropUrl('movie-3'),
      'rating': 7.9,
      'year': 2022,
      'overview': '一家即将停业的猫咪咖啡馆，让一群陌生人的人生产生交集。',
      'isFavorite': true,
      'playUrl': 'https://example.com/play/movie-3',
      'cast': _cast('The Last Cat Cafe'),
    },
    {
      'id': 1004,
      'title': 'Silent Orbit',
      'originalTitle': 'Silent Orbit',
      'type': 'movie',
      'posterUrl': _posterUrl('movie-4'),
      'backdropUrl': _backdropUrl('movie-4'),
      'rating': 8.5,
      'year': 2025,
      'overview': '深空任务中断后，宇航员必须独自修复失控的轨道站。',
      'isFavorite': false,
      'playUrl': 'https://example.com/play/movie-4',
      'cast': _cast('Silent Orbit'),
    },
    {
      'id': 1005,
      'title': 'Crimson Tracks',
      'originalTitle': 'Crimson Tracks',
      'type': 'movie',
      'posterUrl': _posterUrl('movie-5'),
      'backdropUrl': _backdropUrl('movie-5'),
      'rating': 7.8,
      'year': 2021,
      'overview': '一列深夜列车穿越雪原，车上每个人都像在隐藏真相。',
      'isFavorite': false,
      'playUrl': 'https://example.com/play/movie-5',
      'cast': _cast('Crimson Tracks'),
    },
    {
      'id': 1006,
      'title': 'Summer of Kites',
      'originalTitle': 'Summer of Kites',
      'type': 'movie',
      'posterUrl': _posterUrl('movie-6'),
      'backdropUrl': _backdropUrl('movie-6'),
      'rating': 7.6,
      'year': 2020,
      'overview': '海边小镇的一个夏天，少年们在离别前找回彼此的勇气。',
      'isFavorite': false,
      'playUrl': 'https://example.com/play/movie-6',
      'cast': _cast('Summer of Kites'),
    },
    {
      'id': 1007,
      'title': 'Glass Kingdom',
      'originalTitle': 'Glass Kingdom',
      'type': 'movie',
      'posterUrl': _posterUrl('movie-7'),
      'backdropUrl': _backdropUrl('movie-7'),
      'rating': 8.1,
      'year': 2024,
      'overview': '豪门继承之争背后，一场精心布局的骗局悄然展开。',
      'isFavorite': true,
      'playUrl': 'https://example.com/play/movie-7',
      'cast': _cast('Glass Kingdom'),
    },
    {
      'id': 1008,
      'title': 'Echoes in Rain',
      'originalTitle': 'Echoes in Rain',
      'type': 'movie',
      'posterUrl': _posterUrl('movie-8'),
      'backdropUrl': _backdropUrl('movie-8'),
      'rating': 7.7,
      'year': 2023,
      'overview': '失忆的钢琴家在一段旧录音里，听见了自己遗失的过去。',
      'isFavorite': false,
      'playUrl': 'https://example.com/play/movie-8',
      'cast': _cast('Echoes in Rain'),
    },
    {
      'id': 1009,
      'title': 'Night Market Runner',
      'originalTitle': 'Night Market Runner',
      'type': 'movie',
      'posterUrl': _posterUrl('movie-9'),
      'backdropUrl': _backdropUrl('movie-9'),
      'rating': 8.0,
      'year': 2022,
      'overview': '在灯火通明的夜市里，一名外卖骑手卷入地下情报交易。',
      'isFavorite': false,
      'playUrl': 'https://example.com/play/movie-9',
      'cast': _cast('Night Market Runner'),
    },
    {
      'id': 1010,
      'title': 'Aurora Protocol',
      'originalTitle': 'Aurora Protocol',
      'type': 'movie',
      'posterUrl': _posterUrl('movie-10'),
      'backdropUrl': _backdropUrl('movie-10'),
      'rating': 8.4,
      'year': 2025,
      'overview': '一套失控的气候系统即将引发灾难，团队必须在极夜中完成修复。',
      'isFavorite': true,
      'playUrl': 'https://example.com/play/movie-10',
      'cast': _cast('Aurora Protocol'),
    },
  ];

  static final List<Map<String, dynamic>> _seriesListJson = [
    {
      'id': 2001,
      'title': 'City of Whiskers',
      'originalTitle': 'City of Whiskers',
      'type': 'series',
      'posterUrl': _posterUrl('series-1'),
      'backdropUrl': _backdropUrl('series-1'),
      'rating': 8.9,
      'year': 2024,
      'overview': '五位性格迥异的年轻人在都市里合租，慢慢成为彼此的家人。',
      'isFavorite': true,
      'playUrl': 'https://example.com/play/series-1',
      'cast': _cast('City of Whiskers'),
    },
    {
      'id': 2002,
      'title': 'Signal 404',
      'originalTitle': 'Signal 404',
      'type': 'series',
      'posterUrl': _posterUrl('series-2'),
      'backdropUrl': _backdropUrl('series-2'),
      'rating': 8.3,
      'year': 2023,
      'overview': '一组网络安全调查员追踪神秘信号源，意外牵出跨国阴谋。',
      'isFavorite': false,
      'playUrl': 'https://example.com/play/series-2',
      'cast': _cast('Signal 404'),
    },
    {
      'id': 2003,
      'title': 'After the Typhoon',
      'originalTitle': 'After the Typhoon',
      'type': 'series',
      'posterUrl': _posterUrl('series-3'),
      'backdropUrl': _backdropUrl('series-3'),
      'rating': 7.8,
      'year': 2022,
      'overview': '台风过后的小岛重建中，一群居民重新面对彼此与自己。',
      'isFavorite': false,
      'playUrl': 'https://example.com/play/series-3',
      'cast': _cast('After the Typhoon'),
    },
    {
      'id': 2004,
      'title': 'Paper Moon Files',
      'originalTitle': 'Paper Moon Files',
      'type': 'series',
      'posterUrl': _posterUrl('series-4'),
      'backdropUrl': _backdropUrl('series-4'),
      'rating': 8.1,
      'year': 2021,
      'overview': '旧档案馆里尘封的卷宗，被一位新人管理员逐页揭开。',
      'isFavorite': true,
      'playUrl': 'https://example.com/play/series-4',
      'cast': _cast('Paper Moon Files'),
    },
    {
      'id': 2005,
      'title': 'Blue Hour Motel',
      'originalTitle': 'Blue Hour Motel',
      'type': 'series',
      'posterUrl': _posterUrl('series-5'),
      'backdropUrl': _backdropUrl('series-5'),
      'rating': 7.9,
      'year': 2024,
      'overview': '每一位入住汽车旅馆的客人，都带来一段看似普通却危险的故事。',
      'isFavorite': false,
      'playUrl': 'https://example.com/play/series-5',
      'cast': _cast('Blue Hour Motel'),
    },
  ];

  static String _posterUrl(String seed) {
    return 'https://picsum.photos/seed/$seed-poster/300/450';
  }

  static String _backdropUrl(String seed) {
    return 'https://picsum.photos/seed/$seed-backdrop/900/500';
  }

  static List<Map<String, dynamic>> _cast(String title) {
    return [
      {
        'name': '$title 主演',
        'characterName': '领衔主演',
        'avatarUrl': _posterUrl('$title-cast-1'),
      },
      {
        'name': '林知遥',
        'characterName': '关键角色',
        'avatarUrl': _posterUrl('$title-cast-2'),
      },
      {
        'name': '周以澄',
        'characterName': '特别出演',
        'avatarUrl': _posterUrl('$title-cast-3'),
      },
      {
        'name': '陈予安',
        'characterName': '友情出演',
        'avatarUrl': _posterUrl('$title-cast-4'),
      },
      {
        'name': '宋叙白',
        'characterName': '配角',
        'avatarUrl': _posterUrl('$title-cast-5'),
      },
    ];
  }
}

class MockService {
  MockService._();

  static const MockMediaService _mediaService = MockMediaService();

  static Future<List<MediaItem>> getMockMovies() {
    return _mediaService.getTrendingMovies();
  }

  static Future<List<MediaItem>> getMockSeries() {
    return _mediaService.getSeriesList();
  }
}
