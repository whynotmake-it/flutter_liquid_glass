/// [source] with its comments, and with [strings] also its string literals,
/// replaced by spaces; line breaks stay, so offsets and lines still match.
String blank(String source, {bool strings = false}) {
  final out = StringBuffer();
  final stack = <_Context>[_Code()];
  void write(String text) {
    out.write(strings && stack.last is _String ? _spaces(text) : text);
  }

  var i = 0;
  while (i < source.length) {
    final context = stack.last;
    final char = source[i];
    switch (context) {
      case _Code():
        if (source.startsWith('//', i)) {
          final end = source.indexOf('\n', i);
          final stop = end < 0 ? source.length : end;
          out.write(_spaces(source.substring(i, stop)));
          i = stop;
        } else if (source.startsWith('/*', i)) {
          final stop = _blockCommentEnd(source, i);
          out.write(_spaces(source.substring(i, stop)));
          i = stop;
        } else if (char == '{') {
          context.depth++;
          write(char);
          i++;
        } else if (char == '}') {
          if (context.depth == 0 && stack.length > 1) {
            stack.removeLast();
          } else {
            context.depth--;
          }
          write(char);
          i++;
        } else if (_stringStart(source, i) case final string?) {
          stack.add(string);
          final opening = (string.raw ? 'r' : '') + string.close;
          write(opening);
          i += opening.length;
        } else {
          write(char);
          i++;
        }
      case _String(:final raw, :final close):
        if (!raw && char == r'\') {
          write(source.substring(i, i + 2 > source.length ? i + 1 : i + 2));
          i += 2;
        } else if (source.startsWith(close, i)) {
          write(close);
          i += close.length;
          stack.removeLast();
        } else if (!raw && source.startsWith(r'${', i)) {
          write(r'${');
          i += 2;
          stack.add(_Code());
        } else {
          write(char);
          i++;
        }
    }
  }
  return out.toString();
}

String _spaces(String text) => text.replaceAll(RegExp(r'[^\n]'), ' ');

int _blockCommentEnd(String source, int start) {
  var depth = 0;
  var i = start;
  while (i < source.length) {
    if (source.startsWith('/*', i)) {
      depth++;
      i += 2;
    } else if (source.startsWith('*/', i)) {
      depth--;
      i += 2;
      if (depth == 0) return i;
    } else {
      i++;
    }
  }
  return source.length;
}

final _identifier = RegExp(r'[A-Za-z0-9_$]');

_String? _stringStart(String source, int i) {
  var at = i;
  var raw = false;
  if (source[at] == 'r' &&
      (at == 0 || !_identifier.hasMatch(source[at - 1])) &&
      at + 1 < source.length &&
      (source[at + 1] == "'" || source[at + 1] == '"')) {
    raw = true;
    at++;
  }
  final quote = source[at];
  if (quote != "'" && quote != '"') return null;
  final triple = source.startsWith(quote * 3, at);
  return _String(raw: raw, close: triple ? quote * 3 : quote);
}

sealed class _Context {}

final class _Code extends _Context {
  int depth = 0;
}

final class _String extends _Context {
  _String({required this.raw, required this.close});

  final bool raw;
  final String close;
}

final _directive = RegExp(
  r'''^(?:import|export|part)\s+((?:'[^']*'|"[^"]*")(?:[^;'"]|'[^']*'|"[^"]*")*);''',
  multiLine: true,
);
final _uri = RegExp('[\'"]([^\'"]+)[\'"]');

/// The URIs of the import, export and part directives of [source], one
/// list per directive (a conditional import names several). A `part of`
/// directive is left out. A directive starts a line, as `dart format`
/// writes it, so a statement such as `part is! Motion` is not one.
List<List<String>> directives(String source) => [
  for (final match in _directive.allMatches(blank(source)))
    [for (final uri in _uri.allMatches(match.group(1)!)) uri.group(1)!],
];
