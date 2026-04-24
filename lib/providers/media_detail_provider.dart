import 'package:flutter/foundation.dart';
import '../domain/entities/media_item.dart';
import '../domain/entities/playback_plan.dart';
import '../domain/repositories/playback_repository.dart';
import 'user_data_provider.dart';

class MediaDetailProvider extends ChangeNotifier {
  MediaDetailProvider({
    required UserDataProvider userDataProvider,
    required PlaybackRepository playbackRepository,
  }) : _userDataProvider = userDataProvider,
       _playbackRepository = playbackRepository;

  UserDataProvider _userDataProvider;
  PlaybackRepository _playbackRepository;

  List<MediaItem> _episodes = const [];
  int _selectedIndex = 0;
  bool _isLoading = false;
  bool _isLoadingPlaybackConfig = false;
  String? _loadedSeriesKey;
  PlaybackPlan? _selectedPlaybackPlan;
  String? _selectedPlaybackItemKey;
  int _playbackRequestToken = 0;

  List<MediaItem> get episodes => _episodes;
  int get selectedIndex => _selectedIndex;
  bool get isLoading => _isLoading;
  bool get isLoadingPlaybackConfig => _isLoadingPlaybackConfig;
  String? get loadedSeriesKey => _loadedSeriesKey;
  PlaybackPlan? get selectedPlaybackPlan => _selectedPlaybackPlan;
  String? get selectedPlaybackItemKey => _selectedPlaybackItemKey;

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
  }) {
    _userDataProvider = userDataProvider;
    _playbackRepository = playbackRepository;
  }

  Future<void> loadEpisodes(MediaItem series) async {
    _loadedSeriesKey = null;
    _episodes = const [];
    _selectedIndex = 0;
    _isLoading = true;
    _isLoadingPlaybackConfig = false;
    _selectedPlaybackPlan = null;
    _selectedPlaybackItemKey = null;
    notifyListeners();

    final playableItems = series.playableItems.isEmpty
        ? <MediaItem>[series]
        : List<MediaItem>.from(series.playableItems);

    _episodes = playableItems;
    _selectedIndex = _resolveLastPlayedEpisodeIndex(playableItems);
    _loadedSeriesKey = series.mediaKey;

    _isLoading = false;
    notifyListeners();
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

    await _prefetchPlaybackInfo(
      item,
      // 详情页这里只是为了加载完整的音轨/字幕选项，不应带当前选择，
      // 否则 Emby 可能按已选字幕裁剪返回结果，导致 SRT 等轨道不出现在列表里。
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
      _selectedPlaybackPlan = plan;
      if (kDebugMode) {
        final subtitleSummary = plan.subtitleStreams
            .map(
              (stream) =>
                  '{index=${stream.index}, codec=${stream.codec ?? ''}, '
                  'title=${stream.title}, text=${stream.isTextSubtitleStream}, '
                  'external=${stream.isExternal}}',
            )
            .join(', ');
        debugPrint(
          '[Diag][MediaDetailProvider] playback_prefetch:success | '
          'itemId=${item.dataSourceId}, subtitleCount=${plan.subtitleStreams.length}, '
          'subtitles=[$subtitleSummary]',
        );
      }
      _isLoadingPlaybackConfig = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[MediaDetailProvider] Prefetch failed: $e');
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
      _selectedPlaybackPlan = null;
      _selectedPlaybackItemKey = _episodes[_selectedIndex].mediaKey;
      _isLoadingPlaybackConfig = false;
      notifyListeners();
    }
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
