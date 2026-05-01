/// Pure string/regex utilities for parsing media filenames.
///
/// Shared between [LocalMediaScanner] (dart:io) and the SAF scanner path so
/// filename heuristics are defined in one place.  No `dart:io` dependency —
/// usable from isolates and platform-channel flows alike.
class MediaFileNameParser {
  const MediaFileNameParser._();

  // ---- constants -----------------------------------------------------------

  static const videoExtensions = {
    '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.ts', '.m4v',
  };

  static const imageNames = {
    'poster.jpg', 'poster.png', 'folder.jpg', 'folder.png',
    'cover.jpg', 'cover.png', 'default.jpg', 'default.png',
  };

  static const fanartNames = {
    'fanart.jpg', 'fanart.png', 'backdrop.jpg', 'backdrop.png',
    'background.jpg', 'background.png',
  };

  static const seasonFolderPattern = r'^[Ss](?:eason)?[_\s.-]*(\d{1,2})$';
  static const tvEpisodePattern = r'[Ss](\d{1,2})[Ee](\d{1,2})';
  static const epPattern = r'(?:^|[. _\-\[\(])[Ee][Pp](\d{1,3})(?:$|[. _\-\]\)])';
  static const ePattern = r'(?:^|[. _\-\[\(])[Ee](\d{1,3})(?:$|[. _\-\]\)])';
  static const chineseEpisodePattern = r'第\s*(\d{1,3})\s*[集話话回]';
  static const bareNumberPattern = r'^(\d{1,3})$';
  static const yearPattern = r'[[({.](\d{4})[\])}.]';

  static const qualityTags = [
    '1080p', '720p', '480p', '2160p', '4k', '4K',
    'web-dl', 'WEB-DL', 'bluray', 'BLURAY', 'BluRay',
    'h264', 'H264', 'h265', 'H265', 'x264', 'x265',
    'hevc', 'HEVC', 'aac', 'AAC', 'dts', 'DTS',
    'ddp', 'dd+', 'atmos', 'ATMOS',
    'remux', 'REMUX', 'proper', 'PROPER',
    'extended', 'EXTENDED', "directors", "DIRECTORS",
    'imax', 'IMAX',
  ];

  // ---- extension helpers ---------------------------------------------------

  static String extension(String path) {
    final dot = path.lastIndexOf('.');
    return dot >= 0 ? path.substring(dot) : '';
  }

  static String basenameWithoutExtension(String path) {
    // Works for both POSIX paths and bare filenames.
    final lastSep = path.contains('/')
        ? path.lastIndexOf('/')
        : (path.contains('\\') ? path.lastIndexOf('\\') : -1);
    final name = lastSep >= 0 ? path.substring(lastSep + 1) : path;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  // ---- filename parsing ----------------------------------------------------

  /// Parsed result from [parseFilename].
  static MediaParsedFilename parseFilename(String fileName) {
    final nameNoExt = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;

    // SxxExx
    final tvMatch =
        RegExp(tvEpisodePattern, caseSensitive: false).firstMatch(nameNoExt);
    if (tvMatch != null) {
      final seasonNum = int.tryParse(tvMatch.group(1) ?? '');
      final episodeNum = int.tryParse(tvMatch.group(2) ?? '');
      final titlePart = nameNoExt.substring(0, tvMatch.start).trim();
      final title = cleanTitle(titlePart);
      return MediaParsedFilename(
        title: title.isNotEmpty ? title : null,
        mediaType: 'series',
        seasonNum: seasonNum,
        episodeNum: episodeNum,
      );
    }

    // EP##
    final epMatch =
        RegExp(epPattern, caseSensitive: false).firstMatch(nameNoExt);
    if (epMatch != null) {
      final episodeNum = int.tryParse(epMatch.group(1) ?? '');
      final titlePart = nameNoExt.substring(0, epMatch.start).trim();
      final title = cleanTitle(titlePart);
      return MediaParsedFilename(
        title: title.isNotEmpty ? title : null,
        mediaType: 'series',
        episodeNum: episodeNum,
      );
    }

    // E## (guarded against year-like and word-prefixed numbers)
    final eMatch =
        RegExp(ePattern, caseSensitive: false).firstMatch(nameNoExt);
    if (eMatch != null) {
      final rawNum = eMatch.group(1) ?? '';
      final episodeNum = int.tryParse(rawNum);
      if (episodeNum != null && rawNum.length < 4) {
        final beforeE =
            eMatch.start > 0 ? nameNoExt[eMatch.start - 1] : '';
        if (!RegExp(r'[a-zA-Z]').hasMatch(beforeE)) {
          final titlePart = nameNoExt.substring(0, eMatch.start).trim();
          final title = cleanTitle(titlePart);
          return MediaParsedFilename(
            title: title.isNotEmpty ? title : null,
            mediaType: 'series',
            episodeNum: episodeNum,
          );
        }
      }
    }

    // Chinese episode
    final chMatch = RegExp(chineseEpisodePattern).firstMatch(nameNoExt);
    if (chMatch != null) {
      final episodeNum = int.tryParse(chMatch.group(1) ?? '');
      final titlePart = nameNoExt.substring(0, chMatch.start).trim();
      final title = cleanTitle(titlePart);
      return MediaParsedFilename(
        title: title.isNotEmpty ? title : null,
        mediaType: 'series',
        episodeNum: episodeNum,
      );
    }

    // Year extraction
    final yearMatch = RegExp(yearPattern).firstMatch(nameNoExt);
    int? year;
    String cleanTitleStr = nameNoExt;

    if (yearMatch != null) {
      year = int.tryParse(yearMatch.group(1) ?? '');
      cleanTitleStr =
          nameNoExt.replaceRange(yearMatch.start, yearMatch.end, '');
    }

    cleanTitleStr = cleanTitle(cleanTitleStr);

    // Bare number filename (e.g. "01.mkv")
    final bareMatch = RegExp(bareNumberPattern).firstMatch(cleanTitleStr);
    if (bareMatch != null && cleanTitleStr.length <= 3) {
      final episodeNum = int.tryParse(bareMatch.group(1) ?? '');
      return MediaParsedFilename(
        title: null,
        mediaType: 'series',
        episodeNum: episodeNum,
      );
    }

    return MediaParsedFilename(
      title: cleanTitleStr.isNotEmpty ? cleanTitleStr : null,
      year: year,
      mediaType: 'movie',
    );
  }

  // ---- title cleaning ------------------------------------------------------

  static String cleanTitle(String title) {
    var result = title;

    // Separators → spaces
    result = result.replaceAll(RegExp(r'[._]'), ' ');

    // Strip quality tags
    for (final tag in qualityTags) {
      final escaped = RegExp.escape(tag);
      result = result.replaceAll(
        RegExp('\\b$escaped\\b', caseSensitive: false),
        '',
      );
    }

    // Collapse whitespace
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Remove trailing dash/space
    result = result.replaceAll(RegExp(r'[-\s]+$'), '');

    return result;
  }

  // ---- episode-number assignment -------------------------------------------

  /// Extract episode numbers from a list of filenames.
  ///
  /// Missing / unparseable numbers are filled sequentially starting from 1,
  /// skipping already-used values. Returns one [int] per input filename.
  static List<int> assignEpisodeNumbers(List<String> fileNames) {
    final results = <int>[];
    final usedNumbers = <int>{};

    for (final name in fileNames) {
      final nameNoExt = name.contains('.')
          ? name.substring(0, name.lastIndexOf('.'))
          : name;
      int? episodeNum;

      int? tryExtract(RegExp pattern, [int group = 1]) {
        final m = pattern.firstMatch(nameNoExt);
        return m != null ? int.tryParse(m.group(group) ?? '') : null;
      }

      episodeNum ??= tryExtract(RegExp(tvEpisodePattern, caseSensitive: false), 2);
      episodeNum ??= tryExtract(RegExp(epPattern, caseSensitive: false));
      if (episodeNum == null) {
        final eM = RegExp(ePattern, caseSensitive: false).firstMatch(nameNoExt);
        if (eM != null) {
          final raw = eM.group(1) ?? '';
          final n = int.tryParse(raw);
          if (n != null && raw.length < 4) {
            final before = eM.start > 0 ? nameNoExt[eM.start - 1] : '';
            if (!RegExp(r'[a-zA-Z]').hasMatch(before)) episodeNum = n;
          }
        }
      }
      episodeNum ??= tryExtract(RegExp(chineseEpisodePattern));
      if (episodeNum == null) {
        final clean = cleanTitle(nameNoExt);
        final bare = RegExp(bareNumberPattern).firstMatch(clean);
        if (bare != null && clean.length <= 3) {
          episodeNum = int.tryParse(bare.group(1) ?? '');
        }
      }
      if (episodeNum == null) {
        final trailing =
            RegExp(r'[_\-\s]+(\d{1,3})$').firstMatch(nameNoExt);
        if (trailing != null) {
          episodeNum = int.tryParse(trailing.group(1) ?? '');
        }
      }

      results.add(episodeNum ?? -1);
      if (episodeNum != null) usedNumbers.add(episodeNum);
    }

    // Fill gaps sequentially
    var next = 1;
    for (var i = 0; i < results.length; i++) {
      if (results[i] < 0) {
        while (usedNumbers.contains(next)) {
          next++;
        }
        results[i] = next;
        usedNumbers.add(next);
      }
    }

    return results;
  }
}

/// Public result of [MediaFileNameParser.parseFilename].
class MediaParsedFilename {
  const MediaParsedFilename({
    this.title,
    this.originalTitle,
    this.year,
    this.mediaType,
    this.seasonNum,
    this.episodeNum,
  });

  final String? title;
  final String? originalTitle;
  final int? year;
  final String? mediaType;
  final int? seasonNum;
  final int? episodeNum;
}
