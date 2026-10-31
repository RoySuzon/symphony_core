// Internal helper of the auth entities. Not exported from the auth barrel.

/// Deep equality of JSON-like values: maps and lists are compared element by
/// element (recursively), everything else with `==`.
///
/// Used by the value equality of the entities whose free-form payloads
/// (`AuthUser.data`, `AuthTokens.extra`) usually come from decoded JSON, so
/// that two payloads with the same content are equal even when their nested
/// maps and lists are distinct instances.
bool jsonValueEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!jsonValueEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (!jsonValueEquals(a[index], b[index])) return false;
    }
    return true;
  }
  return a == b;
}
