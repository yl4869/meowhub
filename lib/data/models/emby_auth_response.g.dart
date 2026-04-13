// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'emby_auth_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EmbyAuthResponse _$EmbyAuthResponseFromJson(Map<String, dynamic> json) =>
    EmbyAuthResponse(
      user: EmbyAuthUser.fromJson(json['User'] as Map<String, dynamic>),
      sessionInfo: json['SessionInfo'] == null
          ? null
          : EmbySessionInfo.fromJson(
              json['SessionInfo'] as Map<String, dynamic>,
            ),
      accessToken: json['AccessToken'] as String,
      serverId: json['ServerId'] as String?,
    );

Map<String, dynamic> _$EmbyAuthResponseToJson(EmbyAuthResponse instance) =>
    <String, dynamic>{
      'User': instance.user.toJson(),
      'SessionInfo': instance.sessionInfo?.toJson(),
      'AccessToken': instance.accessToken,
      'ServerId': instance.serverId,
    };

EmbyAuthUser _$EmbyAuthUserFromJson(Map<String, dynamic> json) => EmbyAuthUser(
  name: json['Name'] as String,
  serverId: json['ServerId'] as String?,
  prefix: json['Prefix'] as String?,
  dateCreated: json['DateCreated'] == null
      ? null
      : DateTime.parse(json['DateCreated'] as String),
  id: json['Id'] as String,
  hasPassword: json['HasPassword'] as bool? ?? false,
  hasConfiguredPassword: json['HasConfiguredPassword'] as bool? ?? false,
  lastLoginDate: json['LastLoginDate'] == null
      ? null
      : DateTime.parse(json['LastLoginDate'] as String),
  lastActivityDate: json['LastActivityDate'] == null
      ? null
      : DateTime.parse(json['LastActivityDate'] as String),
  configuration: json['Configuration'] == null
      ? null
      : EmbyUserConfiguration.fromJson(
          json['Configuration'] as Map<String, dynamic>,
        ),
  policy: json['Policy'] == null
      ? null
      : EmbyUserPolicy.fromJson(json['Policy'] as Map<String, dynamic>),
  hasConfiguredEasyPassword:
      json['HasConfiguredEasyPassword'] as bool? ?? false,
);

Map<String, dynamic> _$EmbyAuthUserToJson(EmbyAuthUser instance) =>
    <String, dynamic>{
      'Name': instance.name,
      'ServerId': instance.serverId,
      'Prefix': instance.prefix,
      'DateCreated': instance.dateCreated?.toIso8601String(),
      'Id': instance.id,
      'HasPassword': instance.hasPassword,
      'HasConfiguredPassword': instance.hasConfiguredPassword,
      'LastLoginDate': instance.lastLoginDate?.toIso8601String(),
      'LastActivityDate': instance.lastActivityDate?.toIso8601String(),
      'Configuration': instance.configuration?.toJson(),
      'Policy': instance.policy?.toJson(),
      'HasConfiguredEasyPassword': instance.hasConfiguredEasyPassword,
    };

EmbyUserConfiguration _$EmbyUserConfigurationFromJson(
  Map<String, dynamic> json,
) => EmbyUserConfiguration(
  audioLanguagePreference: json['AudioLanguagePreference'] as String?,
  playDefaultAudioTrack: json['PlayDefaultAudioTrack'] as bool? ?? false,
  subtitleLanguagePreference: json['SubtitleLanguagePreference'] as String?,
  displayMissingEpisodes: json['DisplayMissingEpisodes'] as bool? ?? false,
  subtitleMode: json['SubtitleMode'] as String?,
  orderedViews:
      (json['OrderedViews'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
  latestItemsExcludes:
      (json['LatestItemsExcludes'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
  myMediaExcludes:
      (json['MyMediaExcludes'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
  hidePlayedInLatest: json['HidePlayedInLatest'] as bool? ?? false,
  hidePlayedInMoreLikeThis: json['HidePlayedInMoreLikeThis'] as bool? ?? false,
  hidePlayedInSuggestions: json['HidePlayedInSuggestions'] as bool? ?? false,
  rememberAudioSelections: json['RememberAudioSelections'] as bool? ?? false,
  rememberSubtitleSelections:
      json['RememberSubtitleSelections'] as bool? ?? false,
  enableNextEpisodeAutoPlay:
      json['EnableNextEpisodeAutoPlay'] as bool? ?? false,
  resumeRewindSeconds: (json['ResumeRewindSeconds'] as num?)?.toInt() ?? 0,
  introSkipMode: json['IntroSkipMode'] as String?,
  enableLocalPassword: json['EnableLocalPassword'] as bool? ?? false,
);

Map<String, dynamic> _$EmbyUserConfigurationToJson(
  EmbyUserConfiguration instance,
) => <String, dynamic>{
  'AudioLanguagePreference': instance.audioLanguagePreference,
  'PlayDefaultAudioTrack': instance.playDefaultAudioTrack,
  'SubtitleLanguagePreference': instance.subtitleLanguagePreference,
  'DisplayMissingEpisodes': instance.displayMissingEpisodes,
  'SubtitleMode': instance.subtitleMode,
  'OrderedViews': instance.orderedViews,
  'LatestItemsExcludes': instance.latestItemsExcludes,
  'MyMediaExcludes': instance.myMediaExcludes,
  'HidePlayedInLatest': instance.hidePlayedInLatest,
  'HidePlayedInMoreLikeThis': instance.hidePlayedInMoreLikeThis,
  'HidePlayedInSuggestions': instance.hidePlayedInSuggestions,
  'RememberAudioSelections': instance.rememberAudioSelections,
  'RememberSubtitleSelections': instance.rememberSubtitleSelections,
  'EnableNextEpisodeAutoPlay': instance.enableNextEpisodeAutoPlay,
  'ResumeRewindSeconds': instance.resumeRewindSeconds,
  'IntroSkipMode': instance.introSkipMode,
  'EnableLocalPassword': instance.enableLocalPassword,
};

EmbyUserPolicy _$EmbyUserPolicyFromJson(
  Map<String, dynamic> json,
) => EmbyUserPolicy(
  isAdministrator: json['IsAdministrator'] as bool? ?? false,
  isHidden: json['IsHidden'] as bool? ?? false,
  isHiddenRemotely: json['IsHiddenRemotely'] as bool? ?? false,
  isHiddenFromUnusedDevices:
      json['IsHiddenFromUnusedDevices'] as bool? ?? false,
  isDisabled: json['IsDisabled'] as bool? ?? false,
  lockedOutDate: (json['LockedOutDate'] as num?)?.toInt() ?? 0,
  allowTagOrRating: json['AllowTagOrRating'] as bool? ?? false,
  blockedTags:
      (json['BlockedTags'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
  isTagBlockingModeInclusive:
      json['IsTagBlockingModeInclusive'] as bool? ?? false,
  includeTags:
      (json['IncludeTags'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
  enableUserPreferenceAccess:
      json['EnableUserPreferenceAccess'] as bool? ?? false,
  accessSchedules:
      (json['AccessSchedules'] as List<dynamic>?)
          ?.map((e) => EmbyAccessSchedule.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
  blockUnratedItems:
      (json['BlockUnratedItems'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
  enableRemoteControlOfOtherUsers:
      json['EnableRemoteControlOfOtherUsers'] as bool? ?? false,
  enableSharedDeviceControl:
      json['EnableSharedDeviceControl'] as bool? ?? false,
  enableRemoteAccess: json['EnableRemoteAccess'] as bool? ?? false,
  enableLiveTvManagement: json['EnableLiveTvManagement'] as bool? ?? false,
  enableLiveTvAccess: json['EnableLiveTvAccess'] as bool? ?? false,
  enableMediaPlayback: json['EnableMediaPlayback'] as bool? ?? false,
  enableAudioPlaybackTranscoding:
      json['EnableAudioPlaybackTranscoding'] as bool? ?? false,
  enableVideoPlaybackTranscoding:
      json['EnableVideoPlaybackTranscoding'] as bool? ?? false,
  enablePlaybackRemuxing: json['EnablePlaybackRemuxing'] as bool? ?? false,
  enableContentDeletion: json['EnableContentDeletion'] as bool? ?? false,
  restrictedFeatures:
      (json['RestrictedFeatures'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
  enableContentDeletionFromFolders:
      (json['EnableContentDeletionFromFolders'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
  enableContentDownloading: json['EnableContentDownloading'] as bool? ?? false,
  enableSubtitleDownloading:
      json['EnableSubtitleDownloading'] as bool? ?? false,
  enableSubtitleManagement: json['EnableSubtitleManagement'] as bool? ?? false,
  enableSyncTranscoding: json['EnableSyncTranscoding'] as bool? ?? false,
  enableMediaConversion: json['EnableMediaConversion'] as bool? ?? false,
  enabledChannels:
      (json['EnabledChannels'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
  enableAllChannels: json['EnableAllChannels'] as bool? ?? false,
  enabledFolders:
      (json['EnabledFolders'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
  enableAllFolders: json['EnableAllFolders'] as bool? ?? false,
  invalidLoginAttemptCount:
      (json['InvalidLoginAttemptCount'] as num?)?.toInt() ?? 0,
  enablePublicSharing: json['EnablePublicSharing'] as bool? ?? false,
  remoteClientBitrateLimit:
      (json['RemoteClientBitrateLimit'] as num?)?.toInt() ?? 0,
  authenticationProviderId: json['AuthenticationProviderId'] as String?,
  excludedSubFolders:
      (json['ExcludedSubFolders'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
  simultaneousStreamLimit:
      (json['SimultaneousStreamLimit'] as num?)?.toInt() ?? 0,
  enabledDevices:
      (json['EnabledDevices'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
  enableAllDevices: json['EnableAllDevices'] as bool? ?? false,
  allowCameraUpload: json['AllowCameraUpload'] as bool? ?? false,
  allowSharingPersonalItems:
      json['AllowSharingPersonalItems'] as bool? ?? false,
);

Map<String, dynamic> _$EmbyUserPolicyToJson(
  EmbyUserPolicy instance,
) => <String, dynamic>{
  'IsAdministrator': instance.isAdministrator,
  'IsHidden': instance.isHidden,
  'IsHiddenRemotely': instance.isHiddenRemotely,
  'IsHiddenFromUnusedDevices': instance.isHiddenFromUnusedDevices,
  'IsDisabled': instance.isDisabled,
  'LockedOutDate': instance.lockedOutDate,
  'AllowTagOrRating': instance.allowTagOrRating,
  'BlockedTags': instance.blockedTags,
  'IsTagBlockingModeInclusive': instance.isTagBlockingModeInclusive,
  'IncludeTags': instance.includeTags,
  'EnableUserPreferenceAccess': instance.enableUserPreferenceAccess,
  'AccessSchedules': instance.accessSchedules.map((e) => e.toJson()).toList(),
  'BlockUnratedItems': instance.blockUnratedItems,
  'EnableRemoteControlOfOtherUsers': instance.enableRemoteControlOfOtherUsers,
  'EnableSharedDeviceControl': instance.enableSharedDeviceControl,
  'EnableRemoteAccess': instance.enableRemoteAccess,
  'EnableLiveTvManagement': instance.enableLiveTvManagement,
  'EnableLiveTvAccess': instance.enableLiveTvAccess,
  'EnableMediaPlayback': instance.enableMediaPlayback,
  'EnableAudioPlaybackTranscoding': instance.enableAudioPlaybackTranscoding,
  'EnableVideoPlaybackTranscoding': instance.enableVideoPlaybackTranscoding,
  'EnablePlaybackRemuxing': instance.enablePlaybackRemuxing,
  'EnableContentDeletion': instance.enableContentDeletion,
  'RestrictedFeatures': instance.restrictedFeatures,
  'EnableContentDeletionFromFolders': instance.enableContentDeletionFromFolders,
  'EnableContentDownloading': instance.enableContentDownloading,
  'EnableSubtitleDownloading': instance.enableSubtitleDownloading,
  'EnableSubtitleManagement': instance.enableSubtitleManagement,
  'EnableSyncTranscoding': instance.enableSyncTranscoding,
  'EnableMediaConversion': instance.enableMediaConversion,
  'EnabledChannels': instance.enabledChannels,
  'EnableAllChannels': instance.enableAllChannels,
  'EnabledFolders': instance.enabledFolders,
  'EnableAllFolders': instance.enableAllFolders,
  'InvalidLoginAttemptCount': instance.invalidLoginAttemptCount,
  'EnablePublicSharing': instance.enablePublicSharing,
  'RemoteClientBitrateLimit': instance.remoteClientBitrateLimit,
  'AuthenticationProviderId': instance.authenticationProviderId,
  'ExcludedSubFolders': instance.excludedSubFolders,
  'SimultaneousStreamLimit': instance.simultaneousStreamLimit,
  'EnabledDevices': instance.enabledDevices,
  'EnableAllDevices': instance.enableAllDevices,
  'AllowCameraUpload': instance.allowCameraUpload,
  'AllowSharingPersonalItems': instance.allowSharingPersonalItems,
};

EmbyAccessSchedule _$EmbyAccessScheduleFromJson(Map<String, dynamic> json) =>
    EmbyAccessSchedule(
      dayOfWeek: json['DayOfWeek'] as String?,
      startHour: (json['StartHour'] as num?)?.toDouble(),
      endHour: (json['EndHour'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$EmbyAccessScheduleToJson(EmbyAccessSchedule instance) =>
    <String, dynamic>{
      'DayOfWeek': instance.dayOfWeek,
      'StartHour': instance.startHour,
      'EndHour': instance.endHour,
    };

EmbySessionInfo _$EmbySessionInfoFromJson(Map<String, dynamic> json) =>
    EmbySessionInfo(
      playState: json['PlayState'] == null
          ? null
          : EmbyPlayState.fromJson(json['PlayState'] as Map<String, dynamic>),
      additionalUsers:
          (json['AdditionalUsers'] as List<dynamic>?)
              ?.map((e) => EmbySessionUser.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      remoteEndPoint: json['RemoteEndPoint'] as String?,
      protocol: json['Protocol'] as String?,
      playableMediaTypes:
          (json['PlayableMediaTypes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      playlistIndex: (json['PlaylistIndex'] as num?)?.toInt() ?? 0,
      playlistLength: (json['PlaylistLength'] as num?)?.toInt() ?? 0,
      id: json['Id'] as String?,
      serverId: json['ServerId'] as String?,
      userId: json['UserId'] as String?,
      userName: json['UserName'] as String?,
      client: json['Client'] as String?,
      lastActivityDate: json['LastActivityDate'] == null
          ? null
          : DateTime.parse(json['LastActivityDate'] as String),
      deviceName: json['DeviceName'] as String?,
      internalDeviceId: (json['InternalDeviceId'] as num?)?.toInt(),
      deviceId: json['DeviceId'] as String?,
      applicationVersion: json['ApplicationVersion'] as String?,
      supportedCommands:
          (json['SupportedCommands'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      supportsRemoteControl: json['SupportsRemoteControl'] as bool? ?? false,
    );

Map<String, dynamic> _$EmbySessionInfoToJson(
  EmbySessionInfo instance,
) => <String, dynamic>{
  'PlayState': instance.playState?.toJson(),
  'AdditionalUsers': instance.additionalUsers.map((e) => e.toJson()).toList(),
  'RemoteEndPoint': instance.remoteEndPoint,
  'Protocol': instance.protocol,
  'PlayableMediaTypes': instance.playableMediaTypes,
  'PlaylistIndex': instance.playlistIndex,
  'PlaylistLength': instance.playlistLength,
  'Id': instance.id,
  'ServerId': instance.serverId,
  'UserId': instance.userId,
  'UserName': instance.userName,
  'Client': instance.client,
  'LastActivityDate': instance.lastActivityDate?.toIso8601String(),
  'DeviceName': instance.deviceName,
  'InternalDeviceId': instance.internalDeviceId,
  'DeviceId': instance.deviceId,
  'ApplicationVersion': instance.applicationVersion,
  'SupportedCommands': instance.supportedCommands,
  'SupportsRemoteControl': instance.supportsRemoteControl,
};

EmbyPlayState _$EmbyPlayStateFromJson(Map<String, dynamic> json) =>
    EmbyPlayState(
      canSeek: json['CanSeek'] as bool? ?? false,
      isPaused: json['IsPaused'] as bool? ?? false,
      isMuted: json['IsMuted'] as bool? ?? false,
      repeatMode: json['RepeatMode'] as String?,
      sleepTimerMode: json['SleepTimerMode'] as String?,
      subtitleOffset: (json['SubtitleOffset'] as num?)?.toInt() ?? 0,
      shuffle: json['Shuffle'] as bool? ?? false,
      playbackRate: json['PlaybackRate'] as num? ?? 1,
    );

Map<String, dynamic> _$EmbyPlayStateToJson(EmbyPlayState instance) =>
    <String, dynamic>{
      'CanSeek': instance.canSeek,
      'IsPaused': instance.isPaused,
      'IsMuted': instance.isMuted,
      'RepeatMode': instance.repeatMode,
      'SleepTimerMode': instance.sleepTimerMode,
      'SubtitleOffset': instance.subtitleOffset,
      'Shuffle': instance.shuffle,
      'PlaybackRate': instance.playbackRate,
    };

EmbySessionUser _$EmbySessionUserFromJson(Map<String, dynamic> json) =>
    EmbySessionUser(
      userId: json['UserId'] as String?,
      userName: json['UserName'] as String?,
    );

Map<String, dynamic> _$EmbySessionUserToJson(EmbySessionUser instance) =>
    <String, dynamic>{'UserId': instance.userId, 'UserName': instance.userName};
