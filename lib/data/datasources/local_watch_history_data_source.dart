/// ✅ 模拟实现：没网或者测试时用，不发真实请求
class MockEmbyWatchHistoryRemoteDataSource implements EmbyWatchHistoryRemoteDataSource {
  @override
  Future<List<EmbyResumeItemDto>> getHistory() async => [];

  @override
  Future<void> startPlayback({ ... }) async {} // 空操作

  @override
  Future<void> updateProgress({ ... }) async {} // 空操作

  @override
  Future<void> stopPlayback({ ... }) async {} // 空操作
}