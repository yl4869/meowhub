import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/watch_history_item.dart';
import '../models/playback_record.dart';

abstract class LocalWatchHistoryDataSource {
  Future<void> updateProgress(PlaybackRecord record);

  Future<List<PlaybackRecord>> getHistory();

  Future<void> clearHistoryForSource(WatchSourceType sourceType);

  Future<void> replaceHistoryForSource(
    WatchSourceType sourceType,
    List<PlaybackRecord> records,
  );
}

class InMemoryLocalWatchHistoryDataSource
    implements LocalWatchHistoryDataSource {
  static const _prefsKey = 'meowhub_watch_history';

  final Map<String, PlaybackRecord> _records = <String, PlaybackRecord>{};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      for (final entry in list) {
        final record = PlaybackRecord.fromJson(entry as Map<String, dynamic>);
        _records[_keyFor(record.sourceType, record.id)] = record;
      }
    } catch (_) {
      // 数据损坏则丢弃
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _records.values.map((r) => r.toJson()).toList();
    await prefs.setString(_prefsKey, jsonEncode(list));
  }

  @override
  Future<void> updateProgress(PlaybackRecord record) async {
    await _ensureLoaded();
    final key = _keyFor(record.sourceType, record.id);
    final existing = _records[key];
    _records[key] = _mergeRecord(existing, record);
    await _persist();
  }

  @override
  Future<List<PlaybackRecord>> getHistory() async {
    await _ensureLoaded();
    final history = _records.values.toList(growable: false)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return history;
  }

  @override
  Future<void> clearHistoryForSource(WatchSourceType sourceType) async {
    await _ensureLoaded();
    _records.removeWhere((key, record) => record.sourceType == sourceType);
    await _persist();
  }

  @override
  Future<void> replaceHistoryForSource(
    WatchSourceType sourceType,
    List<PlaybackRecord> records,
  ) async {
    await _ensureLoaded();
    _records.removeWhere((key, record) => record.sourceType == sourceType);
    for (final record in records) {
      final key = _keyFor(record.sourceType, record.id);
      _records[key] = record;
    }
    await _persist();
  }

  PlaybackRecord _mergeRecord(
    PlaybackRecord? existing,
    PlaybackRecord incoming,
  ) {
    if (existing == null) {
      return incoming;
    }

    return existing.copyWith(
      title: incoming.title.isNotEmpty ? incoming.title : existing.title,
      poster: incoming.poster.isNotEmpty ? incoming.poster : existing.poster,
      position: _maxDuration(existing.position, incoming.position),
      duration: _maxDuration(existing.duration, incoming.duration),
      updatedAt: incoming.updatedAt.isAfter(existing.updatedAt)
          ? incoming.updatedAt
          : existing.updatedAt,
      episodeIndex: incoming.episodeIndex != 0
          ? incoming.episodeIndex
          : existing.episodeIndex,
      originalTitle: incoming.originalTitle ?? existing.originalTitle,
      overview: incoming.overview ?? existing.overview,
      backdrop: incoming.backdrop ?? existing.backdrop,
      parentTitle: incoming.parentTitle ?? existing.parentTitle,
      year: incoming.year ?? existing.year,
      seriesId: incoming.seriesId ?? existing.seriesId,
      parentIndexNumber:
          incoming.parentIndexNumber ?? existing.parentIndexNumber,
      indexNumber: incoming.indexNumber ?? existing.indexNumber,
    );
  }

  String _keyFor(WatchSourceType sourceType, String id) {
    return '${sourceType.name}:$id';
  }

  Duration _maxDuration(Duration left, Duration right) {
    return left >= right ? left : right;
  }
}
