/// The key of [LayerRules.forbidden] that applies to every library.
const everyLibrary = '*';

/// How a file reaches another file of its own library.
enum SameLibraryImports {
  /// Through `package:<package>/src/<library>/...`.
  package,

  /// Through a relative path.
  relative,
}

/// A pattern that must not occur in `lib/`.
final class Ban {
  /// Bans [pattern], a regular expression, in the files [bannedIn] names,
  /// or in every file when it names none, outside the files [allowedIn] and
  /// the occurrences [allowedWith] allows.
  ///
  /// With [code] true the pattern is matched against the source with its
  /// comments and string literals blanked out; with [code] false against
  /// the raw text, so it can ban a comment.
  const Ban(
    this.name,
    this.pattern, {
    required this.reason,
    this.code = true,
    this.bannedIn = const {},
    this.allowedIn = const {},
    this.allowedWith,
  });

  /// The name the debt file and failures show.
  final String name;

  /// The regular expression, as its source text.
  final String pattern;

  /// Why the pattern is banned, which a failure prints under each new
  /// break.
  final String reason;

  /// Whether comments and string literals are blanked before matching.
  final bool code;

  /// Paths, written as [allowedIn]'s are, of the only files the pattern is
  /// banned in; when empty, it is banned in every file.
  final Set<String> bannedIn;

  /// Paths relative to the package root, such as `lib/src/a/b.dart`, where
  /// the pattern may occur. A path that ends in `/`, such as `lib/src/a/`,
  /// allows every file under it.
  final Set<String> allowedIn;

  /// The words that open the line comment right above an occurrence's line
  /// to allow it, such as `After the frame:`, or null when no comment allows
  /// one.
  ///
  /// The comment gives the reason after the words, as in
  /// `// After the frame: the textures it sampled go now.`; the words alone
  /// allow nothing. Each allowed use names its reason where it stands,
  /// instead of a file or a debt line allowing every use in a file.
  final String? allowedWith;
}

/// The library layout of one package, as plain data.
///
/// Each library is a folder `lib/src/<name>/`, opened by one file
/// `lib/<name>.dart` unless it is [sourceOnly]. [libraries] names each
/// library with the libraries it may import; the table must have no cycle.
final class LayerRules {
  /// The rules for the package [package].
  const LayerRules({
    required this.package,
    required this.libraries,
    this.umbrella,
    this.umbrellaLibraries,
    this.umbrellaReexports = const {},
    this.unchecked = const {},
    this.sourceOnly = const {},
    this.sameLibraryImports = SameLibraryImports.package,
    this.otherLibrariesThroughSource = false,
    this.packages = const {},
    this.forbidden = const {},
    this.bans = const [],
  });

  /// The package name, as in `package:<package>/`.
  final String package;

  /// Each library, by folder name, with the libraries it may import.
  final Map<String, Set<String>> libraries;

  /// The library file, without `.dart`, that exports the libraries
  /// [umbrellaLibraries] names and nothing else, or null when the package
  /// has none.
  final String? umbrella;

  /// The libraries, by folder name, that the [umbrella] exports, or null
  /// for every library.
  ///
  /// An umbrella that is what an app needs leaves out the libraries for
  /// those who extend the package, which import them by name.
  final Set<String>? umbrellaLibraries;

  /// Libraries of other packages, as `package:` URIs, that the umbrella
  /// exports besides this package's libraries, such as the umbrella of a
  /// package this one builds on.
  final Set<String> umbrellaReexports;

  /// Library files, without `.dart`, that rule 1 leaves alone, such as a
  /// `testing` library that picks names from several libraries. A library
  /// file of `src` may not import them.
  final Set<String> unchecked;

  /// The libraries of [libraries] that have a folder and no library file:
  /// the package's own libraries reach them through their source files, and
  /// nothing of them is public by a library of their own.
  final Set<String> sourceOnly;

  /// How a file reaches another file of its own library.
  final SameLibraryImports sameLibraryImports;

  /// Whether a file of `src` may reach another library through the files of
  /// its `src` folder, besides its library file.
  ///
  /// A package whose library files are its public API turns it on, so what
  /// its libraries share among themselves stays out of that API.
  final bool otherLibrariesThroughSource;

  /// The packages besides this one that `lib/` may import. `dart:` libraries
  /// are always allowed unless [forbidden] names them.
  final Set<String> packages;

  /// Import URI prefixes each library may not import, by library name or
  /// [everyLibrary].
  final Map<String, List<String>> forbidden;

  /// Patterns that must not occur in `lib/`.
  final List<Ban> bans;
}
