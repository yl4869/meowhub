import 'package:flutter/foundation.dart';

import '../models/media_item.dart';
import '../services/mock_media_service.dart';

class MovieState {
  const MovieState({
    this.movies = const [],
    this.series = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final List<MediaItem> movies;
  final List<MediaItem> series;
  final bool isLoading;
  final String? errorMessage;

  MovieState copyWith({
    List<MediaItem>? movies,
    List<MediaItem>? series,
    bool? isLoading,
    Object? errorMessage = _sentinel,
  }) {
    return MovieState(
      movies: movies ?? this.movies,
      series: series ?? this.series,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

class MovieProvider extends ChangeNotifier {
  MovieProvider({
    Future<List<MediaItem>> Function()? fetchMovies,
    Future<List<MediaItem>> Function()? fetchSeries,
  }) : _fetchMovies = fetchMovies ?? MockService.getMockMovies,
       _fetchSeries = fetchSeries ?? MockService.getMockSeries;

  final Future<List<MediaItem>> Function() _fetchMovies;
  final Future<List<MediaItem>> Function() _fetchSeries;

  MovieState _state = const MovieState();

  MovieState get state => _state;

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
      final results = await Future.wait([_fetchMovies(), _fetchSeries()]);
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
