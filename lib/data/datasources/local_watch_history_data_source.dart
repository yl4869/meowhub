import '../models/playback_record.dart';

abstract class PlaybackRecordStore {
  Future<List<PlaybackRecord>> loadRecords();

  Future<void> saveRecord(PlaybackRecord record);
}

class NoopPlaybackRecordStore implements PlaybackRecordStore {
  const NoopPlaybackRecordStore();

  @override
  Future<List<PlaybackRecord>> loadRecords() async {
    return const [];
  }

  @override
  Future<void> saveRecord(PlaybackRecord record) async {}
}

abstract class LocalWatchHistoryDataSource {
  Future<void> updateProgress(PlaybackRecord record);

  Future<List<PlaybackRecord>> getHistory();
}

class InMemoryLocalWatchHistoryDataSource implements LocalWatchHistoryDataSource {
  InMemoryLocalWatchHistoryDataSource({
    Map<String, PlaybackRecord>? initialRecords,
    PlaybackRecordStore? persistenceStore,
  }) : _records = {...?initialRecords},
       _persistenceStore = persistenceStore ?? const NoopPlaybackRecordStore();

  final Map<String, PlaybackRecord> _records;
  final PlaybackRecordStore _persistenceStore;

  @override
  Future<List<PlaybackRecord>> getHistory() async {
    if (_records.isEmpty) {
      final persistedRecords = await _persistenceStore.loadRecords();
      for (final record in persistedRecords) {
        _records[record.id] = record;
      }
    }

    return _records.values.toList(growable: false);
  }

  @override
  Future<void> updateProgress(PlaybackRecord record) async {
    _records[record.id] = record;
    await _persistenceStore.saveRecord(record);
  }
}
