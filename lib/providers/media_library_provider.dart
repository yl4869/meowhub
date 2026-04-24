import 'package:flutter/foundation.dart';

import '../core/utils/app_diagnostics.dart';
import '../domain/entities/media_item.dart';
import '../domain/repositories/i_media_repository.dart';

class MediaLibraryState {
  const MediaLibraryState({
    this.movies = const [],
    this.series = const [],
    this.recentWatching = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final List<MediaItem> movies;
  final List<MediaItem> series;
  final List<MediaItem> recentWatching;
  final bool isLoading;
  final String? errorMessage;

  MediaLibraryState copyWith({
    List<MediaItem>? movies,
    List<MediaItem>? series,
    List<MediaItem>? recentWatching,
    bool? isLoading,
    Object? errorMessage = _sentinel,
  }) {
    return MediaLibraryState(
      movies: movies ?? this.movies,
      series: series ?? this.series,
      recentWatching: recentWatching ?? this.recentWatching,
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

  IMediaRepository _mediaRepository;

  MediaLibraryState _state = const MediaLibraryState();

  MediaLibraryState get state => _state;

  Map<String, Object?> debugSnapshot() {
    return <String, Object?>{
      'repository': _mediaRepository.runtimeType.toString(),
      'movies': _state.movies.length,
      'series': _state.series.length,
      'recentWatching': _state.recentWatching.length,
      'isLoading': _state.isLoading,
      'errorMessage': _state.errorMessage,
    };
  }

  void debugPrintSnapshot([String reason = 'manual']) {
    if (kDebugMode) {
      debugPrint(
        '[Diag][MediaLibraryProvider] snapshot:$reason | ${debugSnapshot()}',
      );
    }
  }

  void updateRepository(IMediaRepository mediaRepository) {
    if (identical(_mediaRepository, mediaRepository)) {
      if (kDebugMode) {
        debugPrint(
          '[Diag][MediaLibraryProvider] updateRepository:noop | '
          'repository=${mediaRepository.runtimeType}',
        );
      }
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[Diag][MediaLibraryProvider] updateRepository | '
        'from=${_mediaRepository.runtimeType}, to=${mediaRepository.runtimeType}',
      );
    }
    _mediaRepository = mediaRepository;
    _state = const MediaLibraryState();
    notifyListeners();
    loadInitialMovies();
  }

  Future<void> loadInitialMovies() async {
    if (_state.isLoading) {
      if (kDebugMode) {
        debugPrint(
          '[Diag][MediaLibraryProvider] loadInitialMovies:skip_loading | '
          '${debugSnapshot()}',
        );
      }
      return;
    }
    if (kDebugMode) {
      debugPrint(
        '[Diag][MediaLibraryProvider] loadInitialMovies:start | '
        '${debugSnapshot()}',
      );
    }
    await fetchMovies(showLoading: true);
  }

  Future<void> refreshMovies() async {
    await fetchMovies();
  }

  Future<void> fetchMovies({bool showLoading = false}) async {
    if (kDebugMode) {
      debugPrint(
        '[Diag][MediaLibraryProvider] fetchMovies:start | '
        '${{
          ...debugSnapshot(),
          'showLoading': showLoading,
        }}',
      );
    }
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
      if (kDebugMode) {
        debugPrint(
          '[Diag][MediaLibraryProvider] fetchMovies:success | '
          '${debugSnapshot()}',
        );
      }
    } catch (error, stackTrace) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: '影片加载失败了，下拉刷新试试。',
      );
      if (kDebugMode) {
        debugPrint(
          '[Diag][MediaLibraryProvider] fetchMovies:failed | '
          'repository=${_mediaRepository.runtimeType}, '
          'showLoading=$showLoading, '
          'error=${AppDiagnostics.summarizeError(error)}',
        );
        debugPrint(stackTrace.toString());
      }
    }

    notifyListeners();
  }
}

const Object _sentinel = Object();
