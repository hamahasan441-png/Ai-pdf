import 'dart:convert';

/// Deterministic id for a local document path.
///
/// [String.hashCode] is not guaranteed to stay the same across process
/// restarts, so annotation files must not be named with it.
String stableDocumentId(String filePath) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  for (final byte in utf8.encode(filePath)) {
    hash ^= byte;
    hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
