// Emby uses 100-nanosecond ticks for time values.
// 1 tick = 100 nanoseconds, 1 microsecond = 10 ticks.

int durationToEmbyTicks(Duration duration) {
  return duration.inMicroseconds * 10;
}

Duration embyTicksToDuration(int? ticks) {
  if (ticks == null || ticks <= 0) return Duration.zero;
  return Duration(microseconds: ticks ~/ 10);
}

Duration durationFromEmbyTicks(int? ticks) {
  if (ticks == null || ticks <= 0) return Duration.zero;
  return Duration(microseconds: ticks ~/ 10);
}
