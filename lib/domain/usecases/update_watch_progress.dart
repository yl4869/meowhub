import '../entities/watch_history_item.dart';
import '../repositories/watch_history_repository.dart';

class UpdateWatchProgressUseCase {
  const UpdateWatchProgressUseCase(this._repository);

  final WatchHistoryRepository _repository;

  Future<void> call(WatchHistoryItem item) {
    return _repository.updateProgress(item);
  }
}
