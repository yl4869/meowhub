import 'package:flutter/foundation.dart';

import '../domain/entities/media_item.dart';
import '../domain/repositories/i_media_repository.dart';

class MediaLibraryState {
  const MediaLibraryState({
    this.movies = const [],
    this.series = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final List<MediaItem> movies;
  final List<MediaItem> series;
  final bool isLoading;
  final String? errorMessage;

  MediaLibraryState copyWith({
    List<MediaItem>? movies,
    List<MediaItem>? series,
    bool? isLoading,
    Object? errorMessage = _sentinel,
  }) {
    return MediaLibraryState(
      movies: movies ?? this.movies,
      series: series ?? this.series,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

class MediaLibraryProvider extends ChangeNotifier {
  /// Refactor reason:
  /// Provider now depends only on the repository abstraction and exposes
  /// entity-only state, keeping state management free from transport details.
  MediaLibraryProvider({required IMediaRepository mediaRepository})
    : _mediaRepository = mediaRepository;

  final IMediaRepository _mediaRepository;

  MediaLibraryState _state = const MediaLibraryState();

  MediaLibraryState get state => _state;

  Future<void> loadInitialMovies() async {
    if (_state.isLoading) {
      return;
    }
    await fetchMovies(showLoading: true);
  }

  Future<void> refreshMovies() async {
    await fetchMovies();
  }

  Future<void> fetchMovies({bool showLoading = false}) async {
    _state = _state.copyWith(isLoading: true, errorMessage: null);
    notifyListeners();

    try {
      final results = await Future.wait([
        _mediaRepository.getMovies(),
        _mediaRepository.getSeries(),
      ]);
      final movies = results[0];
      final series = results[1];
      _state = _state.copyWith(
        movies: movies,
        series: series,
        isLoading: false,
        errorMessage: null,
      );
    } catch (_) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: '影片加载失败了，下拉刷新试试。',
      );
    }

    notifyListeners();
  }
}

const Object _sentinel = Object();
