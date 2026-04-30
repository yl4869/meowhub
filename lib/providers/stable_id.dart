import '../domain/utils/id_generator.dart';

/// Thin provider-layer utility that delegates to Domain [MediaIdGenerator].
/// Keeps UI files importing only from `providers/` rather than `domain/`.
class StableId {
  StableId._();

  static int hash(String value) => MediaIdGenerator.stableHash(value);
}
