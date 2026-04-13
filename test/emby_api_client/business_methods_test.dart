// test/emby_api_client/business_methods_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';

import 'package:meowhub/data/datasources/emby_api_client.dart';
import 'package:meowhub/domain/entities/media_service_config.dart';
import '../mocks/mock_classes.dart';

void main() {
  late MockSecurityService mockSecurityService;
  late MockSessionExpiredNotifier mockNotifier;
  late MockDio mockDio;
  late EmbyApiClient client;

  setUp(() {
    mockSecurityService = MockSecurityService();
    mockNotifier = MockSessionExpiredNotifier();
    mockDio = MockDio();
  });

  group('业务方法测试', () {
    test('获取媒体库', () async {
      when(() => mockSecurityService.readUserId())
          .thenAnswer((_) async => 'user-123');
      when(() => mockSecurityService.readAccessToken())
          .thenAnswer((_) async => 'token-123');

      final mockResponse = MockResponse<Map<String, dynamic>>(
        data: {
          'Items': [
            {
              'Name': 'Movies',
              'Id': 'library-1',
              'CollectionType': 'movies',
            },
            {
              'Name': 'TV Shows',
              'Id': 'library-2',
              'CollectionType': 'tvshows',
            },
          ],
        },
      );

      when(() => mockDio.get<Map<String, dynamic>>(
        '/emby/Users/user-123/Views',
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
      )).thenAnswer((_) async => mockResponse);

      final config = MediaServiceConfig(
        type: MediaServiceType.emby,
        serverUrl: 'http://test.com',
        deviceId: 'test-device',
      );

      client = EmbyApiClient(
        config: config,
        securityService: mockSecurityService,
        sessionExpiredNotifier: mockNotifier,
        dio: mockDio,
      );

      final result = await client.getMediaLibraries();

      expect(result.items, hasLength(2));
      expect(result.items[0].name, 'Movies');
    });

    test('获取电影列表', () async {
      when(() => mockSecurityService.readUserId())
          .thenAnswer((_) async => 'user-123');
      when(() => mockSecurityService.readAccessToken())
          .thenAnswer((_) async => 'token-123');

      final mockResponse = MockResponse<Map<String, dynamic>>(
        data: {
          'Items': [
            {
              'Name': 'Movie 1',
              'Id': 'movie-1',
              'Type': 'Movie',
              'RunTimeTicks': 7200000000,  // 2小时
              'CommunityRating': 8.5,
              'ImageTags': {'Primary': 'tag1'},
            },
          ],
          'TotalRecordCount': 1,
        },
      );

      when(() => mockDio.get<Map<String, dynamic>>(
        '/emby/Users/user-123/Items',
        queryParameters: {
          'Recursive': 'true',
          'IncludeItemTypes': 'Movie',
          'SortBy': 'DateCreated,SortName',
          'SortOrder': 'Descending',
          'Fields': 'PrimaryImageAspectRatio,ImageTags,Overview',
          'Limit': '100',
        },
        options: any(named: 'options'),
      )).thenAnswer((_) async => mockResponse);

      final config = MediaServiceConfig(
        type: MediaServiceType.emby,
        serverUrl: 'http://test.com',
        deviceId: 'test-device',
      );

      client = EmbyApiClient(
        config: config,
        securityService: mockSecurityService,
        sessionExpiredNotifier: mockNotifier,
        dio: mockDio,
      );

      final result = await client.getMovieItems();

      expect(result.items, hasLength(1));
      expect(result.items[0].name, 'Movie 1');
      expect(result.totalRecordCount, 1);
    });

    test('更新播放进度', () async {
      when(() => mockSecurityService.readUserId())
          .thenAnswer((_) async => 'user-123');
      when(() => mockSecurityService.readAccessToken())
          .thenAnswer((_) async => 'token-123');

      final mockResponse = MockResponse<void>(
        data: null,
        headers: {'content-type': 'application/json'},
      );

      when(() => mockDio.post<void>(
        '/emby/Users/user-123/PlayingItems/movie-123',
        queryParameters: {'PositionTicks': '600000000'},
        options: any(named: 'options'),
      )).thenAnswer((_) async => mockResponse);

      final config = MediaServiceConfig(
        type: MediaServiceType.emby,
        serverUrl: 'http://test.com',
        deviceId: 'test-device',
      );

      client = EmbyApiClient(
        config: config,
        securityService: mockSecurityService,
        sessionExpiredNotifier: mockNotifier,
        dio: mockDio,
      );

      await client.updatePlaybackProgress(
        itemId: 'movie-123',
        position: const Duration(minutes: 10),  // 10分钟 = 600秒 = 600000000 ticks
      );

      // 验证调用
      verify(() => mockDio.post<void>(
        '/emby/Users/user-123/PlayingItems/movie-123',
        queryParameters: {'PositionTicks': '600000000'},
        options: any(named: 'options'),
      )).called(1);
    });
  });
}
