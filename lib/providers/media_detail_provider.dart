import 'package:flutter/foundation.dart';

import '../domain/entities/media_item.dart';
import 'user_data_provider.dart';

class MediaDetailProvider extends ChangeNotifier {
  MediaDetailProvider({required UserDataProvider userDataProvider})
    : _userDataProvider = userDataProvider;

  UserDataProvider _userDataProvider;

  List<MediaItem> _episodes = const [];
  int _selectedIndex = 0;
  bool _isLoading = false;
  String? _loadedSeriesKey;

  List<MediaItem> get episodes => _episodes;
  int get selectedIndex => _selectedIndex;
  bool get isLoading => _isLoading;
  String? get loadedSeriesKey => _loadedSeriesKey;

  void updateUserDataProvider(UserDataProvider userDataProvider) {
    _userDataProvider = userDataProvider;
  }

  Future<void> loadEpisodes(MediaItem series) async {
    _loadedSeriesKey = null;
    _episodes = const [];
    _selectedIndex = 0;
    _isLoading = true;
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

  void selectEpisode(int index) {
    if (_episodes.isEmpty) {
      _selectedIndex = 0;
      notifyListeners();
      return;
    }

    final nextIndex = index.clamp(0, _episodes.length - 1);
    _selectedIndex = nextIndex;
    notifyListeners();
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
