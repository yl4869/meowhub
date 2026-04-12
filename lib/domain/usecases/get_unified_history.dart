import '../entities/watch_history_item.dart';
import '../repositories/watch_history_repository.dart';

class GetUnifiedHistoryUseCase {
  const GetUnifiedHistoryUseCase(this._repository);

  final WatchHistoryRepository _repository;

  Future<List<WatchHistoryItem>> call() {
    return _repository.getUnifiedHistory();
  }
}
