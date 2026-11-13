import 'dart:convert';
import 'dart:io';

import 'package:api_listing/api_listing.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late Directory sample;

  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('api_listing_');
    final fixtures = Directory('test/fixtures');
    for (final entity in fixtures.listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.path.substring(fixtures.path.length + 1);
      final copy = File('${temp.path}/$relative');
      copy.parent.createSync(recursive: true);
      entity.copySync(copy.path);
    }
    sample = Directory('${temp.path}/sample');
    final config = File('${sample.path}/.dart_tool/package_config.json');
    config.parent.createSync(recursive: true);
    config.writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          for (final (name, root) in [
            ('sample', '../'),
            ('dep', '../../dep/'),
            ('meta', '../../meta/'),
          ])
            {
              'name': name,
              'rootUri': root,
              'packageUri': 'lib/',
              'languageVersion': '3.13',
            },
        ],
      }),
    );
  });

  tearDownAll(() => temp.deleteSync(recursive: true));

  test('lists the fixture as the reviewed listing', () async {
    final listing = await listApi(sample);
    final expected = File('test/expected_api.txt').readAsStringSync();
    expect(lineDiff(expected, listing.api), isEmpty);
  });

  test('lists every exported name once, re-exports included', () async {
    final listing = await listApi(sample);
    expect(
      listing.names,
      'Callback\nExtra\nMode\nShown\nWidget\ntop\n',
    );
  });

  test('finds the types public signatures leak', () async {
    final listing = await listApi(sample);
    expect(listing.leaks, [
      'Engine in Callback',
      'Hidden from package:dep in Widget.hidden',
      '_Base in Widget',
    ]);
  });

  test('gives the same texts on every run', () async {
    final first = await listApi(sample);
    final second = await listApi(sample);
    expect(second.api, first.api);
    expect(second.names, first.names);
    expect(second.leaks, first.leaks);
  });

  test('an allowlist fails on an added and on a fixed entry', () {
    final file = File('${temp.path}/allow.txt');
    file.writeAsStringSync('A in B\nC in D\n');
    expect(checkAllowlist(file, ['A in B', 'C in D'], update: false), isNull);
    final failure = checkAllowlist(file, ['A in B', 'E in F'], update: false);
    expect(failure, contains('  E in F'));
    expect(failure, contains('  C in D'));
    expect(checkAllowlist(file, ['E in F'], update: true), isNull);
    expect(file.readAsStringSync(), 'E in F\n');
  });

  test('a snapshot fails with a line diff', () {
    final file = File('${temp.path}/snapshot.txt');
    file.writeAsStringSync('a\nb\nc\nd\n');
    final failure = checkSnapshot(file, 'a\nb\nx\nd\n', update: false);
    expect(failure, contains('@@ line 1 @@\n  a\n  b\n- c\n+ x\n  d'));
    expect(checkSnapshot(file, 'a\nb\nc\nd\n', update: false), isNull);
  });
}
