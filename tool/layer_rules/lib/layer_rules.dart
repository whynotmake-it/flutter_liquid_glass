/// Holds a package of this workspace to its library layers, the way
/// `package:flutter` holds its own.
///
/// A package describes its layout in one `LayerRules` value and checks it
/// in one test with `checkLayers` and `holdDebt`. The rules:
///
/// 1. Every folder `lib/src/<name>/` is one library, opened by the one file
///    `lib/<name>.dart`, which exports only from its own folder. No Dart file
///    sits directly in `lib/src/`. The umbrella exports every library, or
///    the ones `umbrellaLibraries` lists, and nothing else but the packages
///    it re-exports; the `unchecked` library files are exempt.
/// 2. A file of `lib/src/<a>/` reaches another library only through
///    `package:<package>/<b>.dart`, and its own library one way.
/// 3. A library imports only the libraries its row of the table names; the
///    table has no cycle, so neither have the imports.
/// 4. `lib/` imports only the configured packages, and no library imports
///    what it is forbidden.
/// 5. No banned pattern occurs in `lib/`.
///
/// Breaks of rule 1 always fail. Breaks of rules 2 to 5 that the code has
/// today are listed in a reviewed debt file, which only shrinks.
library;

export 'src/check.dart'
    show
        LayerReport,
        Violation,
        banned,
        checkLayers,
        forbiddenImport,
        foreignPackage,
        notAllowed,
        sameLibraryStyle,
        throughLibrary;
export 'src/debt.dart' show holdDebt, readDebt, updateDebtRequested, writeDebt;
export 'src/rules.dart' show Ban, LayerRules, SameLibraryImports, everyLibrary;
