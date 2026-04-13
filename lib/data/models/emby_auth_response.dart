import 'package:json_annotation/json_annotation.dart';

part 'emby_auth_response.g.dart';

@JsonSerializable(explicitToJson: true)
class EmbyAuthResponse {
  const EmbyAuthResponse({
    required this.user,
    this.sessionInfo,
    required this.accessToken,
    this.serverId,
  });

  @JsonKey(name: 'User')
  final EmbyAuthUser user;

  @JsonKey(name: 'SessionInfo')
  final EmbySessionInfo? sessionInfo;

  @JsonKey(name: 'AccessToken')
  final String accessToken;

  @JsonKey(name: 'ServerId')
  final String? serverId;

  factory EmbyAuthResponse.fromJson(Map<String, dynamic> json) =>
      _$EmbyAuthResponseFromJson(json);

  Map<String, dynamic> toJson() => _$EmbyAuthResponseToJson(this);
}

@JsonSerializable(explicitToJson: true)
class EmbyAuthUser {
  const EmbyAuthUser({
    required this.name,
    this.serverId,
    this.prefix,
    this.dateCreated,
    required this.id,
    this.hasPassword = false,
    this.hasConfiguredPassword = false,
    this.lastLoginDate,
    this.lastActivityDate,
    this.configuration,
    this.policy,
    this.hasConfiguredEasyPassword = false,
  });

  @JsonKey(name: 'Name')
  final String name;

  @JsonKey(name: 'ServerId')
  final String? serverId;

  @JsonKey(name: 'Prefix')
  final String? prefix;

  @JsonKey(name: 'DateCreated')
  final DateTime? dateCreated;

  @JsonKey(name: 'Id')
  final String id;

  @JsonKey(name: 'HasPassword', defaultValue: false)
  final bool hasPassword;

  @JsonKey(name: 'HasConfiguredPassword', defaultValue: false)
  final bool hasConfiguredPassword;

  @JsonKey(name: 'LastLoginDate')
  final DateTime? lastLoginDate;

  @JsonKey(name: 'LastActivityDate')
  final DateTime? lastActivityDate;

  @JsonKey(name: 'Configuration')
  final EmbyUserConfiguration? configuration;

  @JsonKey(name: 'Policy')
  final EmbyUserPolicy? policy;

  @JsonKey(name: 'HasConfiguredEasyPassword', defaultValue: false)
  final bool hasConfiguredEasyPassword;

  factory EmbyAuthUser.fromJson(Map<String, dynamic> json) =>
      _$EmbyAuthUserFromJson(json);

  Map<String, dynamic> toJson() => _$EmbyAuthUserToJson(this);
}

@JsonSerializable(explicitToJson: true)
class EmbyUserConfiguration {
  const EmbyUserConfiguration({
    this.audioLanguagePreference,
    this.playDefaultAudioTrack = false,
    this.subtitleLanguagePreference,
    this.displayMissingEpisodes = false,
    this.subtitleMode,
    this.orderedViews = const [],
    this.latestItemsExcludes = const [],
    this.myMediaExcludes = const [],
    this.hidePlayedInLatest = false,
    this.hidePlayedInMoreLikeThis = false,
    this.hidePlayedInSuggestions = false,
    this.rememberAudioSelections = false,
    this.rememberSubtitleSelections = false,
    this.enableNextEpisodeAutoPlay = false,
    this.resumeRewindSeconds = 0,
    this.introSkipMode,
    this.enableLocalPassword = false,
  });

  @JsonKey(name: 'AudioLanguagePreference')
  final String? audioLanguagePreference;

  @JsonKey(name: 'PlayDefaultAudioTrack', defaultValue: false)
  final bool playDefaultAudioTrack;

  @JsonKey(name: 'SubtitleLanguagePreference')
  final String? subtitleLanguagePreference;

  @JsonKey(name: 'DisplayMissingEpisodes', defaultValue: false)
  final bool displayMissingEpisodes;

  @JsonKey(name: 'SubtitleMode')
  final String? subtitleMode;

  @JsonKey(name: 'OrderedViews', defaultValue: <String>[])
  final List<String> orderedViews;

  @JsonKey(name: 'LatestItemsExcludes', defaultValue: <String>[])
  final List<String> latestItemsExcludes;

  @JsonKey(name: 'MyMediaExcludes', defaultValue: <String>[])
  final List<String> myMediaExcludes;

  @JsonKey(name: 'HidePlayedInLatest', defaultValue: false)
  final bool hidePlayedInLatest;

  @JsonKey(name: 'HidePlayedInMoreLikeThis', defaultValue: false)
  final bool hidePlayedInMoreLikeThis;

  @JsonKey(name: 'HidePlayedInSuggestions', defaultValue: false)
  final bool hidePlayedInSuggestions;

  @JsonKey(name: 'RememberAudioSelections', defaultValue: false)
  final bool rememberAudioSelections;

  @JsonKey(name: 'RememberSubtitleSelections', defaultValue: false)
  final bool rememberSubtitleSelections;

  @JsonKey(name: 'EnableNextEpisodeAutoPlay', defaultValue: false)
  final bool enableNextEpisodeAutoPlay;

  @JsonKey(name: 'ResumeRewindSeconds', defaultValue: 0)
  final int resumeRewindSeconds;

  @JsonKey(name: 'IntroSkipMode')
  final String? introSkipMode;

  @JsonKey(name: 'EnableLocalPassword', defaultValue: false)
  final bool enableLocalPassword;

  factory EmbyUserConfiguration.fromJson(Map<String, dynamic> json) =>
      _$EmbyUserConfigurationFromJson(json);

  Map<String, dynamic> toJson() => _$EmbyUserConfigurationToJson(this);
}

@JsonSerializable(explicitToJson: true)
class EmbyUserPolicy {
  const EmbyUserPolicy({
    this.isAdministrator = false,
    this.isHidden = false,
    this.isHiddenRemotely = false,
    this.isHiddenFromUnusedDevices = false,
    this.isDisabled = false,
    this.lockedOutDate = 0,
    this.allowTagOrRating = false,
    this.blockedTags = const [],
    this.isTagBlockingModeInclusive = false,
    this.includeTags = const [],
    this.enableUserPreferenceAccess = false,
    this.accessSchedules = const [],
    this.blockUnratedItems = const [],
    this.enableRemoteControlOfOtherUsers = false,
    this.enableSharedDeviceControl = false,
    this.enableRemoteAccess = false,
    this.enableLiveTvManagement = false,
    this.enableLiveTvAccess = false,
    this.enableMediaPlayback = false,
    this.enableAudioPlaybackTranscoding = false,
    this.enableVideoPlaybackTranscoding = false,
    this.enablePlaybackRemuxing = false,
    this.enableContentDeletion = false,
    this.restrictedFeatures = const [],
    this.enableContentDeletionFromFolders = const [],
    this.enableContentDownloading = false,
    this.enableSubtitleDownloading = false,
    this.enableSubtitleManagement = false,
    this.enableSyncTranscoding = false,
    this.enableMediaConversion = false,
    this.enabledChannels = const [],
    this.enableAllChannels = false,
    this.enabledFolders = const [],
    this.enableAllFolders = false,
    this.invalidLoginAttemptCount = 0,
    this.enablePublicSharing = false,
    this.remoteClientBitrateLimit = 0,
    this.authenticationProviderId,
    this.excludedSubFolders = const [],
    this.simultaneousStreamLimit = 0,
    this.enabledDevices = const [],
    this.enableAllDevices = false,
    this.allowCameraUpload = false,
    this.allowSharingPersonalItems = false,
  });

  @JsonKey(name: 'IsAdministrator', defaultValue: false)
  final bool isAdministrator;

  @JsonKey(name: 'IsHidden', defaultValue: false)
  final bool isHidden;

  @JsonKey(name: 'IsHiddenRemotely', defaultValue: false)
  final bool isHiddenRemotely;

  @JsonKey(name: 'IsHiddenFromUnusedDevices', defaultValue: false)
  final bool isHiddenFromUnusedDevices;

  @JsonKey(name: 'IsDisabled', defaultValue: false)
  final bool isDisabled;

  @JsonKey(name: 'LockedOutDate', defaultValue: 0)
  final int lockedOutDate;

  @JsonKey(name: 'AllowTagOrRating', defaultValue: false)
  final bool allowTagOrRating;

  @JsonKey(name: 'BlockedTags', defaultValue: <String>[])
  final List<String> blockedTags;

  @JsonKey(name: 'IsTagBlockingModeInclusive', defaultValue: false)
  final bool isTagBlockingModeInclusive;

  @JsonKey(name: 'IncludeTags', defaultValue: <String>[])
  final List<String> includeTags;

  @JsonKey(name: 'EnableUserPreferenceAccess', defaultValue: false)
  final bool enableUserPreferenceAccess;

  @JsonKey(name: 'AccessSchedules', defaultValue: <EmbyAccessSchedule>[])
  final List<EmbyAccessSchedule> accessSchedules;

  @JsonKey(name: 'BlockUnratedItems', defaultValue: <String>[])
  final List<String> blockUnratedItems;

  @JsonKey(name: 'EnableRemoteControlOfOtherUsers', defaultValue: false)
  final bool enableRemoteControlOfOtherUsers;

  @JsonKey(name: 'EnableSharedDeviceControl', defaultValue: false)
  final bool enableSharedDeviceControl;

  @JsonKey(name: 'EnableRemoteAccess', defaultValue: false)
  final bool enableRemoteAccess;

  @JsonKey(name: 'EnableLiveTvManagement', defaultValue: false)
  final bool enableLiveTvManagement;

  @JsonKey(name: 'EnableLiveTvAccess', defaultValue: false)
  final bool enableLiveTvAccess;

  @JsonKey(name: 'EnableMediaPlayback', defaultValue: false)
  final bool enableMediaPlayback;

  @JsonKey(name: 'EnableAudioPlaybackTranscoding', defaultValue: false)
  final bool enableAudioPlaybackTranscoding;

  @JsonKey(name: 'EnableVideoPlaybackTranscoding', defaultValue: false)
  final bool enableVideoPlaybackTranscoding;

  @JsonKey(name: 'EnablePlaybackRemuxing', defaultValue: false)
  final bool enablePlaybackRemuxing;

  @JsonKey(name: 'EnableContentDeletion', defaultValue: false)
  final bool enableContentDeletion;

  @JsonKey(name: 'RestrictedFeatures', defaultValue: <String>[])
  final List<String> restrictedFeatures;

  @JsonKey(name: 'EnableContentDeletionFromFolders', defaultValue: <String>[])
  final List<String> enableContentDeletionFromFolders;

  @JsonKey(name: 'EnableContentDownloading', defaultValue: false)
  final bool enableContentDownloading;

  @JsonKey(name: 'EnableSubtitleDownloading', defaultValue: false)
  final bool enableSubtitleDownloading;

  @JsonKey(name: 'EnableSubtitleManagement', defaultValue: false)
  final bool enableSubtitleManagement;

  @JsonKey(name: 'EnableSyncTranscoding', defaultValue: false)
  final bool enableSyncTranscoding;

  @JsonKey(name: 'EnableMediaConversion', defaultValue: false)
  final bool enableMediaConversion;

  @JsonKey(name: 'EnabledChannels', defaultValue: <String>[])
  final List<String> enabledChannels;

  @JsonKey(name: 'EnableAllChannels', defaultValue: false)
  final bool enableAllChannels;

  @JsonKey(name: 'EnabledFolders', defaultValue: <String>[])
  final List<String> enabledFolders;

  @JsonKey(name: 'EnableAllFolders', defaultValue: false)
  final bool enableAllFolders;

  @JsonKey(name: 'InvalidLoginAttemptCount', defaultValue: 0)
  final int invalidLoginAttemptCount;

  @JsonKey(name: 'EnablePublicSharing', defaultValue: false)
  final bool enablePublicSharing;

  @JsonKey(name: 'RemoteClientBitrateLimit', defaultValue: 0)
  final int remoteClientBitrateLimit;

  @JsonKey(name: 'AuthenticationProviderId')
  final String? authenticationProviderId;

  @JsonKey(name: 'ExcludedSubFolders', defaultValue: <String>[])
  final List<String> excludedSubFolders;

  @JsonKey(name: 'SimultaneousStreamLimit', defaultValue: 0)
  final int simultaneousStreamLimit;

  @JsonKey(name: 'EnabledDevices', defaultValue: <String>[])
  final List<String> enabledDevices;

  @JsonKey(name: 'EnableAllDevices', defaultValue: false)
  final bool enableAllDevices;

  @JsonKey(name: 'AllowCameraUpload', defaultValue: false)
  final bool allowCameraUpload;

  @JsonKey(name: 'AllowSharingPersonalItems', defaultValue: false)
  final bool allowSharingPersonalItems;

  factory EmbyUserPolicy.fromJson(Map<String, dynamic> json) =>
      _$EmbyUserPolicyFromJson(json);

  Map<String, dynamic> toJson() => _$EmbyUserPolicyToJson(this);
}

@JsonSerializable()
class EmbyAccessSchedule {
  const EmbyAccessSchedule({
    this.dayOfWeek,
    this.startHour,
    this.endHour,
  });

  @JsonKey(name: 'DayOfWeek')
  final String? dayOfWeek;

  @JsonKey(name: 'StartHour')
  final double? startHour;

  @JsonKey(name: 'EndHour')
  final double? endHour;

  factory EmbyAccessSchedule.fromJson(Map<String, dynamic> json) =>
      _$EmbyAccessScheduleFromJson(json);

  Map<String, dynamic> toJson() => _$EmbyAccessScheduleToJson(this);
}

@JsonSerializable(explicitToJson: true)
class EmbySessionInfo {
  const EmbySessionInfo({
    this.playState,
    this.additionalUsers = const [],
    this.remoteEndPoint,
    this.protocol,
    this.playableMediaTypes = const [],
    this.playlistIndex = 0,
    this.playlistLength = 0,
    this.id,
    this.serverId,
    this.userId,
    this.userName,
    this.client,
    this.lastActivityDate,
    this.deviceName,
    this.internalDeviceId,
    this.deviceId,
    this.applicationVersion,
    this.supportedCommands = const [],
    this.supportsRemoteControl = false,
  });

  @JsonKey(name: 'PlayState')
  final EmbyPlayState? playState;

  @JsonKey(name: 'AdditionalUsers', defaultValue: <EmbySessionUser>[])
  final List<EmbySessionUser> additionalUsers;

  @JsonKey(name: 'RemoteEndPoint')
  final String? remoteEndPoint;

  @JsonKey(name: 'Protocol')
  final String? protocol;

  @JsonKey(name: 'PlayableMediaTypes', defaultValue: <String>[])
  final List<String> playableMediaTypes;

  @JsonKey(name: 'PlaylistIndex', defaultValue: 0)
  final int playlistIndex;

  @JsonKey(name: 'PlaylistLength', defaultValue: 0)
  final int playlistLength;

  @JsonKey(name: 'Id')
  final String? id;

  @JsonKey(name: 'ServerId')
  final String? serverId;

  @JsonKey(name: 'UserId')
  final String? userId;

  @JsonKey(name: 'UserName')
  final String? userName;

  @JsonKey(name: 'Client')
  final String? client;

  @JsonKey(name: 'LastActivityDate')
  final DateTime? lastActivityDate;

  @JsonKey(name: 'DeviceName')
  final String? deviceName;

  @JsonKey(name: 'InternalDeviceId')
  final int? internalDeviceId;

  @JsonKey(name: 'DeviceId')
  final String? deviceId;

  @JsonKey(name: 'ApplicationVersion')
  final String? applicationVersion;

  @JsonKey(name: 'SupportedCommands', defaultValue: <String>[])
  final List<String> supportedCommands;

  @JsonKey(name: 'SupportsRemoteControl', defaultValue: false)
  final bool supportsRemoteControl;

  factory EmbySessionInfo.fromJson(Map<String, dynamic> json) =>
      _$EmbySessionInfoFromJson(json);

  Map<String, dynamic> toJson() => _$EmbySessionInfoToJson(this);
}

@JsonSerializable()
class EmbyPlayState {
  const EmbyPlayState({
    this.canSeek = false,
    this.isPaused = false,
    this.isMuted = false,
    this.repeatMode,
    this.sleepTimerMode,
    this.subtitleOffset = 0,
    this.shuffle = false,
    this.playbackRate = 1,
  });

  @JsonKey(name: 'CanSeek', defaultValue: false)
  final bool canSeek;

  @JsonKey(name: 'IsPaused', defaultValue: false)
  final bool isPaused;

  @JsonKey(name: 'IsMuted', defaultValue: false)
  final bool isMuted;

  @JsonKey(name: 'RepeatMode')
  final String? repeatMode;

  @JsonKey(name: 'SleepTimerMode')
  final String? sleepTimerMode;

  @JsonKey(name: 'SubtitleOffset', defaultValue: 0)
  final int subtitleOffset;

  @JsonKey(name: 'Shuffle', defaultValue: false)
  final bool shuffle;

  @JsonKey(name: 'PlaybackRate', defaultValue: 1)
  final num playbackRate;

  factory EmbyPlayState.fromJson(Map<String, dynamic> json) =>
      _$EmbyPlayStateFromJson(json);

  Map<String, dynamic> toJson() => _$EmbyPlayStateToJson(this);
}

@JsonSerializable()
class EmbySessionUser {
  const EmbySessionUser({
    this.userId,
    this.userName,
  });

  @JsonKey(name: 'UserId')
  final String? userId;

  @JsonKey(name: 'UserName')
  final String? userName;

  factory EmbySessionUser.fromJson(Map<String, dynamic> json) =>
      _$EmbySessionUserFromJson(json);

  Map<String, dynamic> toJson() => _$EmbySessionUserToJson(this);
}
