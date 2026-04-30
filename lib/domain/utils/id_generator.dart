/// Pure utility for generating stable numeric IDs from string identifiers.
///
/// Lives in Domain so both UI (fallback MediaItem creation) and Data
/// (LocalFileResolver) can depend on it without violating Clean Architecture.
class MediaIdGenerator {
  MediaIdGenerator._();

  static int stableHash(String value) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;

    var hash = 0x811C9DC5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
