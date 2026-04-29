import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

enum NfoType { movie, episode, tvshow }

class NfoMetadata {
  const NfoMetadata({
    this.title,
    this.originalTitle,
    this.showTitle,
    this.year,
    this.plot,
    this.rating,
    this.thumb,
    this.fanart,
    this.seasonNumber,
    this.episodeNumber,
    required this.type,
  });

  final String? title;
  final String? originalTitle;
  final String? showTitle;
  final int? year;
  final String? plot;
  final double? rating;
  final String? thumb;
  final String? fanart;
  final int? seasonNumber;
  final int? episodeNumber;
  final NfoType type;
}

class LocalNfoParser {
  LocalNfoParser();

  /// Try to find and parse an NFO file for a given video file.
  /// Returns null if no NFO file is found or parsing fails.
  static NfoMetadata? parseForVideo(File videoFile) {
    final dir = videoFile.parent;
    final basename = basenameWithoutExtension(videoFile.path);

    final candidates = [
      File('${dir.path}/$basename.nfo'),
      File('${videoFile.path}.nfo'),
      File('${dir.path}/movie.nfo'),
      File('${dir.path}/tvshow.nfo'),
    ];

    for (final candidate in candidates) {
      if (candidate.existsSync()) {
        debugPrint('[LocalMedia][NFO] 找到候选 NFO 文件: ${candidate.path}');
        final metadata = tryParse(candidate);
        if (metadata != null) {
          debugPrint('[LocalMedia][NFO] 解析成功: type=${metadata.type.name}');
          return metadata;
        }
        debugPrint('[LocalMedia][NFO] 解析失败, 尝试下一个候选');
      }
    }

    debugPrint('[LocalMedia][NFO] 未找到有效的 NFO 文件, 候选列表: ${candidates.map((f) => f.path).toList()}');
    return null;
  }

  /// Parse an NFO file and return metadata or null.
  static NfoMetadata? tryParse(File nfoFile) {
    try {
      final content = nfoFile.readAsStringSync();
      debugPrint('[LocalMedia][NFO] 读取 NFO 文件: ${nfoFile.path}, 大小: ${content.length} bytes');
      final document = XmlDocument.parse(content);
      final root = document.rootElement;
      debugPrint('[LocalMedia][NFO] XML 根元素: <${root.name.local}>');
      return _parseElement(root, nfoFile.parent.path);
    } catch (e) {
      debugPrint('[LocalMedia][NFO] 解析异常: $e');
      return null;
    }
  }

  static NfoMetadata? _parseElement(XmlElement root, String parentDir) {
    final tagName = root.name.local.toLowerCase();

    final title = _childText(root, 'title');
    final originalTitle = _childText(root, 'originaltitle');
    final showTitle = _childText(root, 'showtitle');
    final plot = _childText(root, 'plot');
    final thumb = _childText(root, 'thumb');
    final fanart = _resolveFanart(root, parentDir);

    final yearStr = _childText(root, 'year');
    final year = int.tryParse(yearStr ?? '');

    final ratingStr = _childText(root, 'rating');
    final rating = double.tryParse(ratingStr ?? '');

    return switch (tagName) {
      'movie' => NfoMetadata(
          title: title,
          originalTitle: originalTitle,
          year: year,
          plot: plot,
          rating: rating,
          thumb: _makeAbsolute(thumb, parentDir),
          fanart: fanart,
          type: NfoType.movie,
        ),
      'episodedetails' => NfoMetadata(
          title: title,
          originalTitle: originalTitle,
          showTitle: showTitle,
          year: year,
          plot: plot,
          rating: rating,
          thumb: _makeAbsolute(thumb, parentDir),
          fanart: fanart,
          seasonNumber: int.tryParse(_childText(root, 'season') ?? ''),
          episodeNumber: int.tryParse(_childText(root, 'episode') ?? ''),
          type: NfoType.episode,
        ),
      'tvshow' => NfoMetadata(
          title: title,
          originalTitle: originalTitle,
          year: year,
          plot: plot,
          rating: rating,
          thumb: _makeAbsolute(thumb, parentDir),
          fanart: fanart,
          type: NfoType.tvshow,
        ),
      _ => null,
    };
  }

  static String? _childText(XmlElement parent, String tagName) {
    final elements = parent.findElements(tagName);
    if (elements.isEmpty) return null;
    return elements.first.innerText.trim();
  }

  static String? _resolveFanart(XmlElement root, String parentDir) {
    final fanart = root.findElements('fanart').firstOrNull;
    if (fanart != null) {
      final thumb = _childText(fanart, 'thumb');
      if (thumb != null) return _makeAbsolute(thumb, parentDir);
    }
    return null;
  }

  static String? _makeAbsolute(String? path, String parentDir) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('/') || path.contains('://')) return path;
    return '$parentDir/$path';
  }

  static String basenameWithoutExtension(String filePath) {
    final name = filePath.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}
