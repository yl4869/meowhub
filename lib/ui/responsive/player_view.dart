import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/media_item.dart';
import '../../providers/app_provider.dart';
import '../../providers/user_data_provider.dart';
import '../atoms/meow_video_player.dart';
import '../mobile/player/mobile_player_screen.dart';
import '../tablet/player/tablet_player_screen.dart';
import 'responsive_layout_builder.dart';

class PlayerView extends StatefulWidget {
  const PlayerView({super.key, required this.mediaItem});

  static const String routePath = '/player/:id';

  static String locationFor(int id) => '/player/$id';

  final MediaItem mediaItem;

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView> {
  late final UserDataProvider _userDataProvider;
  late final Duration _initialPosition;
  MeowVideoPlaybackStatus? _latestStatus;
  Duration _lastSavedPosition = Duration.zero;
  Duration _lastSavedDuration = Duration.zero;
  bool _completedPlayback = false;

  @override
  void initState() {
    super.initState();
    _userDataProvider = context.read<UserDataProvider>();
    final savedProgress = _userDataProvider.playbackProgressForItem(
      widget.mediaItem,
    );
    _initialPosition = savedProgress?.position ?? Duration.zero;
    _lastSavedPosition = savedProgress?.position ?? Duration.zero;
    _lastSavedDuration = savedProgress?.duration ?? Duration.zero;
  }

  @override
  void dispose() {
    final latestStatus = _latestStatus;
    if (!_completedPlayback &&
        latestStatus != null &&
        latestStatus.isInitialized &&
        latestStatus.position > Duration.zero) {
      _persistPlaybackProgress(latestStatus);
    }
    super.dispose();
  }

  void _handlePlaybackStatusChanged(MeowVideoPlaybackStatus status) {
    _latestStatus = status;

    if (!status.isInitialized || status.duration <= Duration.zero) {
      return;
    }

    if (status.isCompleted) {
      if (!_completedPlayback) {
        _completedPlayback = true;
        _lastSavedPosition = Duration.zero;
        _lastSavedDuration = Duration.zero;
        _userDataProvider.clearPlaybackProgressForItem(widget.mediaItem);
      }
      return;
    }

    _completedPlayback = false;

    if (_shouldPersistPlaybackProgress(status)) {
      _persistPlaybackProgress(status);
    }
  }

  bool _shouldPersistPlaybackProgress(MeowVideoPlaybackStatus status) {
    if (status.position <= Duration.zero &&
        _lastSavedPosition <= Duration.zero) {
      return false;
    }

    final positionDelta =
        (status.position.inMilliseconds - _lastSavedPosition.inMilliseconds)
            .abs();
    final durationChanged = status.duration != _lastSavedDuration;

    if (!status.isPlaying) {
      return positionDelta >= 600 || durationChanged;
    }

    return positionDelta >= 2000 || durationChanged;
  }

  void _persistPlaybackProgress(MeowVideoPlaybackStatus status) {
    _userDataProvider.updatePlaybackProgressForItem(
      widget.mediaItem,
      position: status.position,
      duration: status.duration,
    );
    _lastSavedPosition = status.position;
    _lastSavedDuration = status.duration;
  }

  @override
  Widget build(BuildContext context) {
    final selectedServer = context.select<AppProvider, MediaServerInfo>(
      (provider) => provider.selectedServer,
    );
    final savedProgress = context
        .select<UserDataProvider, MediaPlaybackProgress?>(
          (provider) => provider.playbackProgressForItem(widget.mediaItem),
        );

    return ResponsiveLayoutBuilder(
      mobileBuilder: (context, maxWidth) {
        return MobilePlayerScreen(
          mediaItem: widget.mediaItem,
          selectedServer: selectedServer,
          savedProgress: savedProgress,
          initialPosition: _initialPosition,
          onPlaybackStatusChanged: _handlePlaybackStatusChanged,
        );
      },
      tabletBuilder: (context, maxWidth) {
        return TabletPlayerScreen(
          maxWidth: maxWidth,
          mediaItem: widget.mediaItem,
          selectedServer: selectedServer,
          savedProgress: savedProgress,
          initialPosition: _initialPosition,
          onPlaybackStatusChanged: _handlePlaybackStatusChanged,
        );
      },
    );
  }
}
