import '../../domain/entities/watch_history_item.dart';
import '../models/playback_record.dart';

abstract class PlaybackRecordStore {
  Future<List<PlaybackRecord>> loadRecords();

  Future<void> saveRecord(PlaybackRecord record);

  Future<void> replaceRecordsForSource(
    WatchSourceType sourceType,
    List<PlaybackRecord> records,
  );
}

class NoopPlaybackRecordStore implements PlaybackRecordStore {
  const NoopPlaybackRecordStore();

  @override
  Future<List<PlaybackRecord>> loadRecords() async {
    return const [];
  }

  @override
  Future<void> saveRecord(PlaybackRecord record) async {}

  @override
  Future<void> replaceRecordsForSource(
    WatchSourceType sourceType,
    List<PlaybackRecord> records,
  ) async {}
}

abstract class LocalWatchHistoryDataSource {
  Future<void> updateProgress(PlaybackRecord record);

  Future<List<PlaybackRecord>> getHistory();

  Future<void> replaceHistoryForSource(
    WatchSourceType sourceType,
    List<PlaybackRecord> records,
  );
}

class InMemoryLocalWatchHistoryDataSource
    implements LocalWatchHistoryDataSource {
  InMemoryLocalWatchHistoryDataSource({
    Map<String, PlaybackRecord>? initialRecords,
    PlaybackRecordStore? persistenceStore,
  }) : _records = {...?initialRecords},
       _persistenceStore = persistenceStore ?? const NoopPlaybackRecordStore();

  final Map<String, PlaybackRecord> _records;
  final PlaybackRecordStore _persistenceStore;

  @override
  Future<List<PlaybackRecord>> getHistory() async {
    await _ensureLoaded();
    return _records.values.toList(growable: false);
  }

  @override
  Future<void> updateProgress(PlaybackRecord record) async {
    await _ensureLoaded();
    _records['${record.sourceType.name}:${record.id}'] = record;
    await _persistenceStore.saveRecord(record);
  }

  @override
  Future<void> replaceHistoryForSource(
    WatchSourceType sourceType,
    List<PlaybackRecord> records,
  ) async {
    await _ensureLoaded();
    _records.removeWhere((_, record) => record.sourceType == sourceType);
    for (final record in records) {
      _records['${record.sourceType.name}:${record.id}'] = record;
    }
    await _persistenceStore.replaceRecordsForSource(sourceType, records);
  }

  Future<void> _ensureLoaded() async {
    if (_records.isNotEmpty) {
      return;
    }

    final persistedRecords = await _persistenceStore.loadRecords();
    for (final record in persistedRecords) {
      _records['${record.sourceType.name}:${record.id}'] = record;
    }
  }
}
