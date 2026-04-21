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
