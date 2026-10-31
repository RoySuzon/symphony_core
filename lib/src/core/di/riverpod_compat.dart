// Version bridge for Riverpod types used in public signatures.
//
// Riverpod 3 no longer exports `Override` and `ProviderListenable` from
// `package:flutter_riverpod/flutter_riverpod.dart` (they moved to
// `package:flutter_riverpod/misc.dart`), while Riverpod 2 has no `misc.dart`.
// `src/internals.dart` exports both types on every supported version
// (flutter_riverpod 2.4 – 3.x), so it is the single place this package imports
// them from. This library is internal: it is not exported from the barrels
// (applications get the types from Riverpod itself).
// ignore: implementation_imports
export 'package:flutter_riverpod/src/internals.dart'
    show Override, ProviderListenable;
