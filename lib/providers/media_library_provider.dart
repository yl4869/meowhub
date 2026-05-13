import 'dart:async';

import 'package:flutter/widgets.dart';

import '../domain/entities/media_item.dart';
import '../domain/entities/media_library_info.dart';
import '../domain/entities/scan_progress.dart';
import '../domain/repositories/i_media_repository.dart';
import '../domain/repositories/i_media_maintainer.dart';

class MediaLibraryState {
  const MediaLibraryState({
    this.libraries = const [],
    this.continueWatching = const [],
    this.recentlyAdded = const [],
    this.libraryItems = const {},
    this.isLoading = false,
    this.isLoadingMore = false,
    this.errorMessage,
    this.libraryTotalCounts = const {},
    this.scanProgress = const ScanProgress(),
  });

  final List<MediaLibraryInfo> libraries;
  final List<MediaItem> continueWatching;
  final List<MediaItem> recentlyAdded;
  final Map<String, List<MediaItem>> libraryItems;
  final bool isLoading;
  final bool isLoadingMore;
  final String? errorMessage;
  final Map<String, int> libraryTotalCounts;
  final ScanProgress scanProgress;

  MediaLibraryState copyWith({
    List<MediaLibraryInfo>? libraries,
    List<MediaItem>? continueWatching,
    List<MediaItem>? recentlyAdded,
    Map<String, List<MediaItem>>? libraryItems,
    bool? isLoading,
    bool? isLoadingMore,
    Object? errorMessage = _sentinel,
    Map<String, int>? libraryTotalCounts,
    ScanProgress? scanProgress,
  }) {
    return MediaLibraryState(
      libraries: libraries ?? this.libraries,
      continueWatching: continueWatching ?? this.continueWatching,
      recentlyAdded: recentlyAdded ?? this.recentlyAdded,
      libraryItems: libraryItems ?? this.libraryItems,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
      libraryTotalCounts: libraryTotalCounts ?? this.libraryTotalCounts,
      scanProgress: scanProgress ?? this.scanProgress,
    );
  }
}

class MediaLibraryProvider extends ChangeNotifier {
  MediaLibraryProvider({
    required IMediaRepository mediaRepository,
    IMediaMaintainer? mediaMaintainer,
  }) : _mediaRepository = mediaRepository {
    _subscribeToMaintainer(mediaMaintainer);
  }

  static const int _initialPageSize = 20;
  static const int _loadMorePageSize = 60;

  IMediaRepository _mediaRepository;

  MediaLibraryState _state = const MediaLibraryState();

  int _fetchGeneration = 0;
  StreamSubscription<ScanProgress>? _scanSubscription;

  MediaLibraryState get state => _state;

  void _subscribeToMaintainer(IMediaMaintainer? maintainer) {
    _scanSubscription?.cancel();
    if (maintainer == null) return;
    _state = _state.copyWith(scanProgress: maintainer.currentProgress);
    _scanSubscription = maintainer.progressStream.listen((progress) {
      _state = _state.copyWith(scanProgress: progress);
      notifyListeners();
    });
  }

  void updateRepository(IMediaRepository mediaRepository) {
    if (identical(_mediaRepository, mediaRepository)) {
      return;
    }

    _mediaRepository = mediaRepository;
    _state = const MediaLibraryState();
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) => fetchAll());
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
    final generation = ++_fetchGeneration;
    _state = _state.copyWith(isLoading: true, errorMessage: null);
    notifyListeners();

    try {
      final libraries = await _mediaRepository.getMediaLibraries();
      if (generation != _fetchGeneration) return;

      final continueWatching = await _mediaRepository.getRecentWatching(limit: 12);
      if (generation != _fetchGeneration) return;

      final recentlyAdded = await _mediaRepository.getItems(
        includeItemTypes: 'Movie,Series',
        sortBy: 'DateCreated',
        sortOrder: 'Descending',
        limit: 8,
      );
      if (generation != _fetchGeneration) return;

      final libraryItems = <String, List<MediaItem>>{};
      final libraryTotalCounts = <String, int>{};
      for (final lib in libraries) {
        if (generation != _fetchGeneration) return;
        final items = await _mediaRepository.getItems(
          libraryId: lib.id,
          includeItemTypes: _itemTypesForCollection(lib.collectionType),
          limit: _initialPageSize,
        );
        libraryItems[lib.id] = items;
        libraryTotalCounts[lib.id] = items.length;
      }
      if (generation != _fetchGeneration) return;

      _state = _state.copyWith(
        libraries: libraries,
        continueWatching: continueWatching,
        recentlyAdded: recentlyAdded,
        libraryItems: libraryItems,
        isLoading: false,
        errorMessage: null,
        isLoadingMore: false,
        libraryTotalCounts: libraryTotalCounts,
      );
    } catch (error) {
      if (generation != _fetchGeneration) return;
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: '媒体库加载失败了，下拉刷新试试。',
      );
    }

    notifyListeners();
  }

  Future<void> fetchMoreItems(String libraryId) async {
    if (_state.isLoadingMore) return;

    final currentItems = _state.libraryItems[libraryId];
    if (currentItems == null) return;

    final lib = _state.libraries.where((l) => l.id == libraryId).firstOrNull;
    if (lib == null) return;

    final totalSoFar = _state.libraryTotalCounts[libraryId] ?? currentItems.length;
    final startIndex = currentItems.length;

    final generation = ++_fetchGeneration;
    _state = _state.copyWith(isLoadingMore: true);
    notifyListeners();

    try {
      final moreItems = await _mediaRepository.getItems(
        libraryId: libraryId,
        includeItemTypes: _itemTypesForCollection(lib.collectionType),
        limit: _loadMorePageSize,
        startIndex: startIndex,
      );
      if (generation != _fetchGeneration) return;

      if (moreItems.isEmpty) {
        _state = _state.copyWith(isLoadingMore: false);
        notifyListeners();
        return;
      }

      final updatedItems = <String, List<MediaItem>>{};
      for (final entry in _state.libraryItems.entries) {
        if (entry.key == libraryId) {
          updatedItems[entry.key] = [...entry.value, ...moreItems];
        } else {
          updatedItems[entry.key] = entry.value;
        }
      }

      _state = _state.copyWith(
        libraryItems: updatedItems,
        isLoadingMore: false,
        libraryTotalCounts: {
          ..._state.libraryTotalCounts,
          libraryId: totalSoFar + moreItems.length,
        },
      );
    } catch (_) {
      if (generation != _fetchGeneration) return;
      _state = _state.copyWith(isLoadingMore: false);
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
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
