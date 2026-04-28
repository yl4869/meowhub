const int embyTicksPerSecond = 10000000;
const int embyTicksPerMicrosecond = 10;

Duration durationFromEmbyTicks(int ticks) {
  if (ticks <= 0) {
    return Duration.zero;
  }
  return Duration(microseconds: ticks ~/ embyTicksPerMicrosecond);
}

int durationToEmbyTicks(Duration duration) {
  if (duration <= Duration.zero) {
    return 0;
  }
  return duration.inMicroseconds * embyTicksPerMicrosecond;
}

/// 2. [新增] 将 Emby 的 Ticks 转换为 Flutter 的 Duration
/// 报错就是因为缺少这个函数
Duration embyTicksToDuration(num? ticks) {
  if (ticks == null) return Duration.zero;
  // 10 Ticks = 1 微秒，所以除以 10
  return Duration(microseconds: (ticks / 10).round());
}
