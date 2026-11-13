/// Lists the public API of a package of this workspace and holds it to the
/// reviewed snapshot files under the package's `test/api/`.
///
/// A package's `test/public_api_test.dart` calls `listApi` once and checks
/// the listing's `api`, `names` and `leaks` with `checkSnapshot` and
/// `checkAllowlist`.
library;

export 'src/diff.dart' show lineDiff;
export 'src/listing.dart' show ApiListing, listApi;
export 'src/snapshot.dart'
    show checkAllowlist, checkSnapshot, regenerateCommand, updateRequested;
