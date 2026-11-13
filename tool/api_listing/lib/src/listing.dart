import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// The public API of one package, as the texts its snapshot files hold.
final class ApiListing {
  /// A listing of the given texts.
  const ApiListing({
    required this.api,
    required this.names,
    required this.leaks,
  });

  /// The text of `test/api/public_api.txt`: one section per public library,
  /// each declaration with its public members and their signatures.
  final String api;

  /// The text of `test/api/public_names.txt`: every public top-level name a
  /// public library of the package exports, sorted, one per line.
  final String names;

  /// Each place a public signature names a type no public library exports,
  /// as `Type in Declaration.member`, sorted.
  final List<String> leaks;
}

/// Lists the public API of the package whose root is [root].
///
/// The package's public libraries are the Dart files under its `lib/` outside
/// `lib/src/`. The package must have been resolved (`flutter pub get`), as
/// the listing reads `.dart_tool/package_config.json`. [sdkPath] is the Dart
/// SDK to analyze against; by default it is the one of the Flutter checkout
/// that resolved the package, or of the running VM for a pure Dart package.
Future<ApiListing> listApi(Directory root, {String? sdkPath}) async {
  final packages = _packageConfig(root);
  final own = packages.entries
      .firstWhere(
        (entry) => _samePath(entry.value.root, root.absolute.path),
        orElse: () => throw StateError(
          'No package of ${root.path}/.dart_tool/package_config.json is '
          'rooted at ${root.path}; run pub get there.',
        ),
      )
      .key;
  final lib = packages[own]!.lib;
  final collection = AnalysisContextCollection(
    includedPaths: [lib],
    sdkPath: sdkPath ?? _dartSdk(packages),
  );
  try {
    final session = collection.contextFor(lib).currentSession;
    return await _Lister(session, own, packages).run();
  } finally {
    await collection.dispose();
  }
}

typedef _Package = ({String root, String lib});

Map<String, _Package> _packageConfig(Directory root) {
  final file = File.fromUri(
    root.absolute.uri.resolve('.dart_tool/package_config.json'),
  );
  if (!file.existsSync()) {
    throw StateError('${file.path} is missing; run pub get in ${root.path}.');
  }
  final packages = <String, _Package>{};
  if (jsonDecode(file.readAsStringSync()) case {
    'packages': final List<Object?> entries,
  }) {
    for (final entry in entries) {
      if (entry case {
        'name': final String name,
        'rootUri': final String rootUri,
      }) {
        final packageRoot = file.uri.resolve(
          rootUri.endsWith('/') ? rootUri : '$rootUri/',
        );
        final packageUri = switch (entry['packageUri']) {
          final String uri => uri,
          _ => 'lib/',
        };
        packages[name] = (
          root: _path(packageRoot),
          lib: _path(packageRoot.resolve(packageUri)),
        );
      }
    }
  }
  return packages;
}

String _path(Uri directory) {
  final path = directory.normalizePath().toFilePath();
  return path.length > 1 && path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
}

bool _samePath(String a, String b) =>
    Directory(a).absolute.uri.normalizePath() ==
    Directory(b).absolute.uri.normalizePath();

// Under `flutter test` the running executable is the Flutter tester, not the
// Dart VM, so the analyzer cannot find the SDK by itself.
String? _dartSdk(Map<String, _Package> packages) {
  final flutter = packages['flutter'];
  final flutterRoot = flutter != null
      ? Directory(flutter.root).parent.parent.path
      : Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) return null;
  final sdk = Directory('$flutterRoot/bin/cache/dart-sdk');
  return sdk.existsSync() ? sdk.absolute.path : null;
}

/// The Dart files under [lib] outside `src/`, as paths relative to [lib],
/// sorted.
List<String> _publicLibraries(String lib) {
  final dir = Directory(lib);
  if (!dir.existsSync()) return const [];
  final base = dir.absolute.uri;
  final paths = [
    for (final entity in dir.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart'))
        Uri.decodeComponent(
          entity.absolute.uri.path.substring(base.path.length),
        ),
  ].where((path) => !path.startsWith('src/')).toList();
  paths.sort();
  return paths;
}

String _key(Element element) => '${element.library?.uri}::${element.name}';

final class _Lister {
  _Lister(this.session, this.own, this.packages);

  final AnalysisSession session;
  final String own;
  final Map<String, _Package> packages;

  final _exported = <String, Set<String>>{};
  final _leaks = <String>{};

  Future<ApiListing> run() async {
    final libraries = [
      for (final path in _publicLibraries(packages[own]!.lib))
        'package:$own/$path',
    ];
    final namespaces = <String, List<Element>>{};
    for (final uri in libraries) {
      namespaces[uri] = _visible(await _library(uri));
    }
    _exported[own] = {
      for (final elements in namespaces.values)
        for (final element in elements) _key(element),
    };
    final out = StringBuffer();
    final listed = <String, String>{};
    final checks = <Element>[];
    for (final uri in libraries) {
      if (out.isNotEmpty) out.writeln();
      out.writeln('# $uri');
      final foreign = <String, List<String>>{};
      for (final element in namespaces[uri]!) {
        final source = _source(element);
        if (source != null) {
          (foreign[source] ??= []).add(element.name!);
          continue;
        }
        if (listed[_key(element)] case final section?) {
          out.writeln('${_kind(element)} ${element.name} (see $section)');
          continue;
        }
        listed[_key(element)] = uri;
        checks.add(element);
        out.writeln(_signature(element));
        for (final member in _members(element)) {
          out.writeln('  $member');
        }
      }
      final sources = foreign.keys.toList();
      sources.sort();
      for (final source in sources) {
        out.writeln('re-exported from $source:');
        for (final name in foreign[source]!) {
          out.writeln('  $name');
        }
      }
    }
    for (final element in checks) {
      await _checkTypes(element);
    }
    final names = {
      for (final elements in namespaces.values)
        for (final element in elements) element.name!,
    }.toList();
    names.sort();
    final leaks = _leaks.toList();
    leaks.sort();
    return ApiListing(
      api: out.toString(),
      names: names.isEmpty ? '' : '${names.join('\n')}\n',
      leaks: leaks,
    );
  }

  Future<LibraryElement> _library(String uri) async {
    final result = await session.getLibraryByUri(uri);
    if (result is! LibraryElementResult) {
      throw StateError('Cannot resolve $uri: $result');
    }
    return result.element;
  }

  /// The public names [library] exports, sorted by name.
  List<Element> _visible(LibraryElement library) {
    final elements = <Element>[
      for (final MapEntry(:key, :value)
          in library.exportNamespace.definedNames2.entries)
        if (!key.endsWith('=') && value.isPublic)
          if (value case PropertyAccessorElement(:final variable))
            variable
          else
            value,
    ];
    elements.sort((a, b) => a.name!.compareTo(b.name!));
    return elements;
  }

  /// The package or SDK library a re-exported [element] comes from, or null
  /// when this package declares it.
  String? _source(Element element) {
    final uri = element.library!.uri;
    if (uri.isScheme('dart')) return 'dart:${uri.path}';
    final package = uri.pathSegments.first;
    return package == own ? null : 'package:$package';
  }

  /// Whether a public library of the package that declares [element], or the
  /// SDK, exports it.
  Future<bool> _isExported(Element element) async {
    final name = element.name;
    if (name == null || !element.isPublic) return false;
    final library = element.library;
    if (library == null) return true;
    final uri = library.uri;
    if (uri.isScheme('dart')) return !uri.path.startsWith('_');
    if (!uri.isScheme('package')) return false;
    final package = uri.pathSegments.first;
    return (await _exports(package)).contains(_key(element));
  }

  Future<Set<String>> _exports(String package) async {
    if (_exported[package] case final known?) return known;
    final keys = <String>{};
    final entry = packages[package];
    if (entry != null) {
      for (final path in _publicLibraries(entry.lib)) {
        final result = await session.getLibraryByUri('package:$package/$path');
        if (result is! LibraryElementResult) continue;
        for (final element in _visible(result.element)) {
          keys.add(_key(element));
        }
      }
    }
    return _exported[package] = keys;
  }

  /// Records each type a public signature of [element] or of its public
  /// members names that no public library exports. Overrides are left out,
  /// as the listing names them without a signature.
  Future<void> _checkTypes(Element element) async {
    if (element.metadata.hasInternal) return;
    final name = element.name!;
    await _checkSignature(element, name);
    if (element is! InstanceElement) return;
    for (final member in _memberElements(element)) {
      if (member.metadata.hasInternal || member.metadata.hasOverride) {
        continue;
      }
      final memberName = switch (member) {
        ConstructorElement(name: null || 'new') => 'new',
        SetterElement() => '${member.name}=',
        _ => member.name!,
      };
      await _checkSignature(member, '$name.$memberName');
    }
  }

  Future<void> _checkSignature(Element element, String site) async {
    for (final named in _namedTypes(element)) {
      if (await _isExported(named)) continue;
      final source = _source(named);
      _leaks.add(
        '${named.name}${source == null ? '' : ' from $source'} in $site',
      );
    }
  }

  /// The declarations whose types the signature of [element] names, members
  /// left out.
  List<Element> _namedTypes(Element element) {
    final types = <DartType>[
      ...switch (element) {
        InterfaceElement() => [
          if (element.supertype case final type?) type,
          ...element.mixins,
          ...element.interfaces,
          if (element is MixinElement) ...element.superclassConstraints,
          if (element is ExtensionTypeElement) element.representation.type,
        ],
        ExtensionElement() => [element.extendedType],
        TypeAliasElement() => [element.aliasedType],
        ConstructorElement() => const <DartType>[],
        ExecutableElement() => [element.returnType],
        PropertyInducingElement() => [element.type],
        _ => const <DartType>[],
      },
      if (element case ExecutableElement(:final formalParameters))
        for (final parameter in formalParameters)
          if (!parameter.metadata.hasInternal) parameter.type,
      if (element case TypeParameterizedElement(:final typeParameters))
        for (final parameter in typeParameters)
          if (parameter.bound case final bound?) bound,
    ];
    final named = <Element>[];
    void walk(DartType type) {
      if (type.alias case final alias?) {
        named.add(alias.element);
        alias.typeArguments.forEach(walk);
        return;
      }
      switch (type) {
        case InterfaceType(:final element, :final typeArguments):
          named.add(element);
          typeArguments.forEach(walk);
        case FunctionType():
          walk(type.returnType);
          for (final parameter in type.formalParameters) {
            walk(parameter.type);
          }
          for (final parameter in type.typeParameters) {
            if (parameter.bound case final bound?) walk(bound);
          }
        case RecordType():
          for (final field in type.positionalFields) {
            walk(field.type);
          }
          for (final field in type.namedFields) {
            walk(field.type);
          }
        default:
      }
    }

    types.forEach(walk);
    return named;
  }
}

String _kind(Element element) => switch (element) {
  ClassElement() => 'class',
  MixinElement() => 'mixin',
  EnumElement() => 'enum',
  ExtensionTypeElement() => 'extension type',
  ExtensionElement() => 'extension',
  TypeAliasElement() => 'typedef',
  TopLevelFunctionElement() => 'function',
  TopLevelVariableElement() => 'variable',
  _ => throw StateError('No kind for ${element.kind}: $element'),
};

/// The declaration of [element] on one line, or with one parameter per line
/// when the line at [indent] would pass 80 columns.
String _signature(Element element, {String indent = ''}) {
  final line = _declaration(element, null);
  if (indent.length + line.length <= 80 ||
      element is! ExecutableElement ||
      element.formalParameters.isEmpty) {
    return line;
  }
  return _declaration(element, indent);
}

String _annotations(Metadata metadata) => [
  if (metadata.hasDeprecated) '@Deprecated',
  if (metadata.hasInternal) '@internal',
  if (metadata.hasProtected) '@protected',
  if (metadata.hasVisibleForOverriding) '@visibleForOverriding',
  if (metadata.hasVisibleForTesting) '@visibleForTesting',
].map((annotation) => '$annotation ').join();

String _declaration(Element element, String? wrap) {
  final declaration = switch (element) {
    ClassElement() => _class(element),
    MixinElement() => _mixin(element),
    EnumElement() => _enum(element),
    ExtensionTypeElement() => _extensionType(element),
    ExtensionElement() => _extension(element),
    TypeAliasElement() =>
      'typedef ${element.name}${_typeParameters(element.typeParameters)} = '
          '${_type(element.aliasedType)}',
    TopLevelFunctionElement() => _function(element, wrap),
    ConstructorElement() => _constructor(element, wrap),
    MethodElement() => _method(element, wrap),
    GetterElement() =>
      '${_static(element)}${_type(element.returnType)} get ${element.name}',
    SetterElement() =>
      '${_static(element)}set ${element.name}'
          '${_parameters(element.formalParameters, null)}',
    PropertyInducingElement() => _variable(element),
    _ => throw StateError('No declaration for ${element.kind}: $element'),
  };
  return '${_annotations(element.metadata)}$declaration';
}

String _class(ClassElement element) {
  final modifiers = [
    if (element.isSealed) 'sealed' else if (element.isAbstract) 'abstract',
    if (element.isBase) 'base',
    if (element.isInterface) 'interface',
    if (element.isFinal) 'final',
    if (element.isMixinClass) 'mixin',
  ];
  return '${modifiers.map((modifier) => '$modifier ').join()}'
      'class ${element.name}${_typeParameters(element.typeParameters)}'
      '${_supertypes(element)}';
}

String _mixin(MixinElement element) =>
    '${element.isBase ? 'base ' : ''}'
    'mixin ${element.name}${_typeParameters(element.typeParameters)}'
    '${_clause('on', element.superclassConstraints)}'
    '${_clause('implements', element.interfaces)}';

String _enum(EnumElement element) =>
    'enum ${element.name}${_typeParameters(element.typeParameters)}'
    '${_clause('with', element.mixins)}'
    '${_clause('implements', element.interfaces)}';

String _extension(ExtensionElement element) =>
    'extension ${element.name}${_typeParameters(element.typeParameters)} '
    'on ${_type(element.extendedType)}';

String _extensionType(ExtensionTypeElement element) =>
    'extension type ${element.name}'
    '${_typeParameters(element.typeParameters)}'
    '(${_type(element.representation.type)} '
    '${element.representation.name})'
    '${_clause('implements', element.interfaces)}';

String _supertypes(InterfaceElement element) => [
  if (element.supertype case final type? when !type.isDartCoreObject)
    ' extends ${_type(type)}',
  _clause('with', element.mixins),
  _clause('implements', element.interfaces),
].join();

String _clause(String keyword, List<DartType> types) =>
    types.isEmpty ? '' : ' $keyword ${types.map(_type).join(', ')}';

String _function(ExecutableElement element, String? wrap) =>
    '${_type(element.returnType)} ${element.name}'
    '${_typeParameters(element.typeParameters)}'
    '${_parameters(element.formalParameters, wrap)}';

String _constructor(ConstructorElement element, String? wrap) {
  final type = element.enclosingElement.name;
  final name = switch (element.name) {
    null || 'new' => type,
    final name => '$type.$name',
  };
  return [
    if (element.isConst) 'const',
    if (element.isFactory) 'factory',
    '$name${_parameters(element.formalParameters, wrap)}',
  ].join(' ');
}

String _method(MethodElement element, String? wrap) =>
    '${_static(element)}${element.isAbstract ? 'abstract ' : ''}'
    '${_function(element, wrap)}';

String _variable(PropertyInducingElement element) => [
  if (element.isStatic && element is FieldElement) 'static',
  if (element.isLate) 'late',
  if (element.isConst) 'const' else if (element.isFinal) 'final',
  '${_type(element.type)} ${element.name}',
].join(' ');

String _static(ExecutableElement element) =>
    element.isStatic && element.enclosingElement is InstanceElement
    ? 'static '
    : '';

String _typeParameters(List<TypeParameterElement> parameters) {
  if (parameters.isEmpty) return '';
  final list = [
    for (final parameter in parameters)
      switch (parameter.bound) {
        final bound? => '${parameter.name} extends ${_type(bound)}',
        null => parameter.name!,
      },
  ];
  return '<${list.join(', ')}>';
}

/// [parameters] in parentheses: on one line when [wrap] is null, otherwise
/// one per line, indented under a declaration that starts at [wrap]. A
/// default value shows as `= ...`: whether it exists, not what it is.
String _parameters(List<FormalParameterElement> parameters, String? wrap) {
  String describe(FormalParameterElement parameter) => [
    if (parameter.metadata.hasInternal) '@internal',
    if (parameter.isRequiredNamed) 'required',
    _type(parameter.type),
    parameter.name ?? '_',
    if (parameter.hasDefaultValue) '= ...',
  ].join(' ');
  final required = [
    for (final parameter in parameters)
      if (parameter.isRequiredPositional) describe(parameter),
  ];
  final optional = [
    for (final parameter in parameters)
      if (!parameter.isRequiredPositional) describe(parameter),
  ];
  final (open, close) = parameters.any((parameter) => parameter.isNamed)
      ? ('{', '}')
      : ('[', ']');
  if (wrap == null) {
    final all = [
      ...required,
      if (optional.isNotEmpty) '$open${optional.join(', ')}$close',
    ];
    return '(${all.join(', ')})';
  }
  final lines = [for (final parameter in required) '$parameter,'];
  final head = optional.isNotEmpty && lines.isEmpty ? '($open' : '(';
  if (optional.isNotEmpty && lines.isNotEmpty) {
    lines.last = '${lines.last} $open';
  }
  lines.addAll([for (final parameter in optional) '$parameter,']);
  final tail = optional.isEmpty ? ')' : '$close)';
  return [head, for (final line in lines) '$wrap  $line', '$wrap$tail'].join(
    '\n',
  );
}

String _type(DartType type) => type.getDisplayString();

/// The public members [element] declares itself: constructors (enums left
/// out), fields, getters, setters and methods.
List<Element> _memberElements(InstanceElement element) => [
  if (element is InterfaceElement && element is! EnumElement)
    ...element.constructors,
  ...element.fields.where((field) => field.isOriginDeclaration),
  ...element.getters.where((getter) => getter.isOriginDeclaration),
  ...element.setters.where((setter) => setter.isOriginDeclaration),
  ...element.methods.where((method) => method.isOriginDeclaration),
].where((member) => member.isPublic).toList();

/// The lines under a declaration of this package: enum values in declaration
/// order, then constructors and the other public members sorted by name,
/// then the names of its overrides.
List<String> _members(Element element) {
  if (element is! InstanceElement) return const [];
  final members = _memberElements(element);
  final overrides = <String>{
    for (final member in members)
      if (member.metadata.hasOverride) member.displayName,
  }.toList();
  overrides.sort();
  final declared = [
    for (final member in members)
      if (!member.metadata.hasOverride &&
          !(member is FieldElement && member.isEnumConstant))
        (
          member is ConstructorElement ? 0 : 1,
          member.displayName,
          _signature(member, indent: '  '),
        ),
  ];
  declared.sort(
    (a, b) => a.$1 != b.$1
        ? a.$1 - b.$1
        : a.$2 != b.$2
        ? a.$2.compareTo(b.$2)
        : a.$3.compareTo(b.$3),
  );
  return [
    if (element is EnumElement)
      for (final value in element.constants) '${value.name},',
    for (final (_, _, signature) in declared) signature,
    if (overrides.isNotEmpty) 'overrides: ${overrides.join(', ')}',
  ];
}
