import 'dart:async';

import 'package:flutter/foundation.dart';
import '../domain/entities/media_item.dart';
import '../domain/entities/playback_plan.dart';
import '../domain/entities/season_info.dart';
import '../domain/repositories/i_media_repository.dart';
import '../domain/repositories/playback_repository.dart';
import 'user_data_provider.dart';

class MediaDetailProvider extends ChangeNotifier {
  MediaDetailProvider({
    required UserDataProvider userDataProvider,
    required PlaybackRepository playbackRepository,
    required IMediaRepository mediaRepository,
  }) : _userDataProvider = userDataProvider,
       _playbackRepository = playbackRepository,
       _mediaRepository = mediaRepository;

  UserDataProvider _userDataProvider;
  PlaybackRepository _playbackRepository;
  IMediaRepository _mediaRepository;

  List<MediaItem> _episodes = const [];
  final Map<String, PlaybackPlan> _playbackPlansByItemKey = {};
  int _selectedIndex = 0;
  bool _isLoading = false;
  bool _isLoadingPlaybackConfig = false;
  String? _loadedSeriesKey;
  PlaybackPlan? _selectedPlaybackPlan;
  String? _selectedPlaybackItemKey;
  int _playbackRequestToken = 0;

  List<SeasonInfo> _seasons = const [];
  int _selectedSeasonIndex = 0;
  bool _isLoadingSeasons = false;

  List<MediaItem> get episodes => _episodes;
  int get selectedIndex => _selectedIndex;
  bool get isLoading => _isLoading;
  bool get isLoadingPlaybackConfig => _isLoadingPlaybackConfig;
  String? get loadedSeriesKey => _loadedSeriesKey;
  PlaybackPlan? get selectedPlaybackPlan => _selectedPlaybackPlan;
  String? get selectedPlaybackItemKey => _selectedPlaybackItemKey;

  List<SeasonInfo> get seasons => _seasons;
  int get selectedSeasonIndex => _selectedSeasonIndex;
  bool get isLoadingSeasons => _isLoadingSeasons;

  MediaItem? get selectedEpisode {
    if (_episodes.isEmpty) {
      return null;
    }
    return _episodes[_selectedIndex.clamp(0, _episodes.length - 1)];
  }

  List<PlaybackStream> get selectedAudioStreams =>
      _selectedPlaybackPlan?.audioStreams ?? const [];

  List<PlaybackStream> get selectedSubtitleStreams =>
      _selectedPlaybackPlan?.subtitleStreams ?? const [];

  String? get selectedMediaSourceId => _selectedPlaybackPlan?.mediaSourceId;

  void updateDependencies({
    required UserDataProvider userDataProvider,
    required PlaybackRepository playbackRepository,
    required IMediaRepository mediaRepository,
  }) {
    final repositoryChanged = !identical(
      _playbackRepository,
      playbackRepository,
    );
    _userDataProvider = userDataProvider;
    _playbackRepository = playbackRepository;
    _mediaRepository = mediaRepository;
    if (!repositoryChanged) {
      return;
    }
    _playbackPlansByItemKey.clear();
    final item = selectedEpisode;
    _selectedPlaybackItemKey = item?.mediaKey;
    _selectedPlaybackPlan = null;
    _isLoadingPlaybackConfig = false;
  }

  Future<void> loadSeasons(MediaItem series) async {
    _loadedSeriesKey = null;
    _seasons = const [];
    _episodes = const [];
    _selectedSeasonIndex = 0;
    _selectedIndex = 0;
    _playbackPlansByItemKey.clear();
    _isLoading = true;
    _isLoadingSeasons = true;
    _isLoadingPlaybackConfig = false;
    _selectedPlaybackPlan = null;
    _selectedPlaybackItemKey = null;
    notifyListeners();

    try {
      final id = series.seriesId ?? series.dataSourceId;
      _seasons = await _mediaRepository.getSeasons(id);
      _isLoadingSeasons = false;
      _loadedSeriesKey = series.mediaKey;

      if (_seasons.isNotEmpty) {
        _selectedSeasonIndex = _resolveInitialSeasonIndex(
          _seasons,
          series.parentIndexNumber,
        );
        await _loadEpisodesForCurrentSeason(
          initialEpisodeNumber: _selectedSeasonIndex ==
                  _resolveInitialSeasonIndex(_seasons, series.parentIndexNumber)
              ? series.indexNumber
              : null,
        );
      }
    } catch (_) {
      _isLoadingSeasons = false;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> selectSeason(int index) async {
    if (_seasons.isEmpty || index == _selectedSeasonIndex) return;

    _selectedSeasonIndex = index.clamp(0, _seasons.length - 1);
    _episodes = const [];
    _selectedIndex = 0;
    _playbackPlansByItemKey.clear();
    _selectedPlaybackPlan = null;
    _selectedPlaybackItemKey = null;
    _isLoading = true;
    notifyListeners();

    await _loadEpisodesForCurrentSeason();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadEpisodesForCurrentSeason({
    int? initialEpisodeNumber,
  }) async {
    if (_seasons.isEmpty) return;

    final season = _seasons[_selectedSeasonIndex];
    try {
      final episodes = await _mediaRepository.getEpisodesForSeason(
        _loadedSeriesKey != null
            ? (_episodes.isNotEmpty
                  ? _episodes.first.seriesId
                  : season.seriesId) ??
                season.seriesId
            : season.seriesId,
        season.indexNumber,
      );

      _episodes = episodes;
      _selectedIndex = _resolveInitialEpisodeIndex(
        episodes,
        initialEpisodeNumber,
      );

      if (episodes.isNotEmpty) {
        unawaited(ensurePlaybackInfoForSelectedEpisode());
      }
    } catch (_) {
      _episodes = const [];
    }
  }

  int _resolveInitialSeasonIndex(
    List<SeasonInfo> seasons,
    int? preferredSeasonNumber,
  ) {
    if (preferredSeasonNumber != null) {
      final idx = seasons.indexWhere(
        (s) => s.indexNumber == preferredSeasonNumber,
      );
      if (idx >= 0) return idx;
    }
    return 0;
  }

  int _resolveInitialEpisodeIndex(
    List<MediaItem> episodes,
    int? preferredEpisodeNumber,
  ) {
    if (preferredEpisodeNumber != null) {
      final idx = episodes.indexWhere(
        (e) => e.indexNumber == preferredEpisodeNumber,
      );
      if (idx >= 0) return idx;
    }
    return _resolveLastPlayedEpisodeIndex(episodes);
  }

  Future<void> loadEpisodes(
    MediaItem series, {
    int? initialSelectedIndex,
  }) async {
    _loadedSeriesKey = null;
    _episodes = const [];
    _seasons = const [];
    _playbackPlansByItemKey.clear();
    _selectedIndex = 0;
    _selectedSeasonIndex = 0;
    _isLoading = true;
    _isLoadingSeasons = false;
    _isLoadingPlaybackConfig = false;
    _selectedPlaybackPlan = null;
    _selectedPlaybackItemKey = null;
    notifyListeners();

    final playableItems = series.playableItems.isEmpty
        ? <MediaItem>[series]
        : List<MediaItem>.from(series.playableItems);

    _episodes = playableItems;
    _selectedIndex =
        initialSelectedIndex?.clamp(0, playableItems.length - 1) ??
        _resolveLastPlayedEpisodeIndex(playableItems);
    _loadedSeriesKey = series.mediaKey;

    _isLoading = false;
    notifyListeners();
    unawaited(ensurePlaybackInfoForSelectedEpisode());
  }

  Future<void> ensurePlaybackInfoForSelectedEpisode() async {
    final item = selectedEpisode;
    if (item == null) {
      _selectedPlaybackItemKey = null;
      _selectedPlaybackPlan = null;
      _isLoadingPlaybackConfig = false;
      notifyListeners();
      return;
    }

    final cachedPlan = _playbackPlansByItemKey[item.mediaKey];
    if (cachedPlan != null) {
      _selectedPlaybackItemKey = item.mediaKey;
      _selectedPlaybackPlan = cachedPlan;
      _isLoadingPlaybackConfig = false;
      notifyListeners();
      return;
    }

    await _prefetchPlaybackInfo(
      item,
      audioStreamIndex: null,
      subtitleStreamIndex: null,
    );
  }

  Future<void> _prefetchPlaybackInfo(
    MediaItem item, {
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    final requestToken = ++_playbackRequestToken;
    _selectedPlaybackItemKey = item.mediaKey;
    _selectedPlaybackPlan = null;
    _isLoadingPlaybackConfig = true;
    notifyListeners();

    try {
      final plan = await _playbackRepository.getPlaybackPlan(
        item,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      );
      if (requestToken != _playbackRequestToken ||
          _selectedPlaybackItemKey != item.mediaKey) {
        return;
      }
      _playbackPlansByItemKey[item.mediaKey] = plan;
      _selectedPlaybackPlan = plan;
      _isLoadingPlaybackConfig = false;
      notifyListeners();
    } catch (e) {
      if (requestToken != _playbackRequestToken ||
          _selectedPlaybackItemKey != item.mediaKey) {
        return;
      }
      _selectedPlaybackPlan = null;
      _isLoadingPlaybackConfig = false;
      notifyListeners();
    }
  }

  void selectEpisode(int index) {
    if (_episodes.isEmpty) return;

    final nextIndex = index.clamp(0, _episodes.length - 1);
    if (_selectedIndex != nextIndex) {
      _selectedIndex = nextIndex;
      final itemKey = _episodes[_selectedIndex].mediaKey;
      _selectedPlaybackItemKey = itemKey;
      _selectedPlaybackPlan = _playbackPlansByItemKey[itemKey];
      _isLoadingPlaybackConfig = false;
      notifyListeners();
      unawaited(ensurePlaybackInfoForSelectedEpisode());
    }
  }

  PlaybackPlan? playbackPlanForItem(MediaItem item) {
    return _playbackPlansByItemKey[item.mediaKey];
  }

  PlaybackStream? selectedAudioStreamByIndex(int? index) {
    if (index == null) {
      return null;
    }
    for (final stream in selectedAudioStreams) {
      if (stream.index == index) {
        return stream;
      }
    }
    return null;
  }

  PlaybackStream? selectedSubtitleStreamByIndex(int? index) {
    if (index == null || index < 0) {
      return null;
    }
    for (final stream in selectedSubtitleStreams) {
      if (stream.index == index) {
        return stream;
      }
    }
    return null;
  }

  int _resolveLastPlayedEpisodeIndex(List<MediaItem> playableItems) {
    var lastPlayedIndex = 0;
    for (var index = 0; index < playableItems.length; index++) {
      final progress = _userDataProvider.playbackProgressForItem(
        playableItems[index],
      );
      if (progress != null && progress.position > Duration.zero) {
        lastPlayedIndex = index;
      }
    }
    return lastPlayedIndex;
  }
}
