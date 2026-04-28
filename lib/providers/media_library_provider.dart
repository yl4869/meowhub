import 'package:flutter/foundation.dart';

import '../domain/entities/media_item.dart';
import '../domain/entities/media_library_info.dart';
import '../domain/repositories/i_media_repository.dart';

class MediaLibraryState {
  const MediaLibraryState({
    this.libraries = const [],
    this.continueWatching = const [],
    this.recentlyAdded = const [],
    this.libraryItems = const {},
    this.isLoading = false,
    this.errorMessage,
  });

  final List<MediaLibraryInfo> libraries;
  final List<MediaItem> continueWatching;
  final List<MediaItem> recentlyAdded;
  final Map<String, List<MediaItem>> libraryItems;
  final bool isLoading;
  final String? errorMessage;

  MediaLibraryState copyWith({
    List<MediaLibraryInfo>? libraries,
    List<MediaItem>? continueWatching,
    List<MediaItem>? recentlyAdded,
    Map<String, List<MediaItem>>? libraryItems,
    bool? isLoading,
    Object? errorMessage = _sentinel,
  }) {
    return MediaLibraryState(
      libraries: libraries ?? this.libraries,
      continueWatching: continueWatching ?? this.continueWatching,
      recentlyAdded: recentlyAdded ?? this.recentlyAdded,
      libraryItems: libraryItems ?? this.libraryItems,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

class MediaLibraryProvider extends ChangeNotifier {
  MediaLibraryProvider({required IMediaRepository mediaRepository})
    : _mediaRepository = mediaRepository;

  IMediaRepository _mediaRepository;

  MediaLibraryState _state = const MediaLibraryState();

  MediaLibraryState get state => _state;

  void updateRepository(IMediaRepository mediaRepository) {
    if (identical(_mediaRepository, mediaRepository)) {
      return;
    }

    _mediaRepository = mediaRepository;
    _state = const MediaLibraryState();
    notifyListeners();
    fetchAll();
  }

  Future<void> loadInitialMedia() async {
    if (_state.isLoading) {
      return;
    }
    await fetchAll(showLoading: true);
  }

  Future<void> refreshMedia() async {
    await fetchAll();
  }

  Future<void> fetchAll({bool showLoading = false}) async {
    _state = _state.copyWith(isLoading: true, errorMessage: null);
    notifyListeners();

    try {
      final libraries = await _mediaRepository.getMediaLibraries();

      final results = await Future.wait([
        _mediaRepository.getRecentWatching(limit: 50),
        _mediaRepository.getItems(
          includeItemTypes: 'Movie,Series',
          sortBy: 'DateCreated',
          sortOrder: 'Descending',
          limit: 10,
        ),
        ...libraries.map(
          (lib) => _mediaRepository.getItems(
            libraryId: lib.id,
            includeItemTypes: _itemTypesForCollection(lib.collectionType),
            limit: 10000,
          ),
        ),
      ]);

      final continueWatching = results[0];
      final recentlyAdded = results[1];

      final libraryItems = <String, List<MediaItem>>{};
      for (var i = 0; i < libraries.length; i++) {
        libraryItems[libraries[i].id] = results[2 + i];
      }

      _state = _state.copyWith(
        libraries: libraries,
        continueWatching: continueWatching,
        recentlyAdded: recentlyAdded,
        libraryItems: libraryItems,
        isLoading: false,
        errorMessage: null,
      );
    } catch (error) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: '媒体库加载失败了，下拉刷新试试。',
      );
    }

    notifyListeners();
  }
}

String _itemTypesForCollection(String collectionType) {
  return switch (collectionType.toLowerCase()) {
    'movies' => 'Movie',
    'tvshows' => 'Series',
    'music' => 'Audio',
    'photos' => 'Photo',
    'homevideos' => 'Video',
    'books' => 'Book',
    'mixed' => 'Movie,Series,Audio,Photo',
    _ => 'Movie,Series',
  };
}

const Object _sentinel = Object();
