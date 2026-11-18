import 'dart:math';
import 'dart:typed_data';

/// A line diff of [expected] against [actual]: hunks of `-` lines that only
/// [expected] has and `+` lines that only [actual] has, with [context]
/// unchanged lines around each and the 1-based line of [expected] it starts
/// at. Empty when the texts are equal. Past [maxLines] lines the rest is
/// counted, not shown.
String lineDiff(
  String expected,
  String actual, {
  int context = 2,
  int maxLines = 300,
}) {
  if (expected == actual) return '';
  final a = expected.split('\n');
  final b = actual.split('\n');
  final edits = _edits(a, b);
  final out = <String>[];
  var index = 0;
  while (index < edits.length) {
    if (edits[index].kind == ' ') {
      index++;
      continue;
    }
    final start = max(0, index - context);
    var end = index;
    while (end < edits.length) {
      if (edits[end].kind != ' ') {
        end++;
        continue;
      }
      var run = end;
      while (run < edits.length && edits[run].kind == ' ') {
        run++;
      }
      if (run == edits.length || run - end > 2 * context) break;
      end = run;
    }
    final stop = min(edits.length, end + context);
    out.add('@@ line ${edits[start].line} @@');
    for (final edit in edits.sublist(start, stop)) {
      out.add('${edit.kind} ${edit.text}');
    }
    index = stop;
  }
  if (out.length <= maxLines) return out.join('\n');
  return [
    ...out.take(maxLines),
    '(${out.length - maxLines} more diff lines)',
  ].join('\n');
}

typedef _Edit = ({String kind, String text, int line});

List<_Edit> _edits(List<String> a, List<String> b) {
  var head = 0;
  while (head < a.length && head < b.length && a[head] == b[head]) {
    head++;
  }
  var tail = 0;
  while (tail < a.length - head &&
      tail < b.length - head &&
      a[a.length - 1 - tail] == b[b.length - 1 - tail]) {
    tail++;
  }
  final midA = a.sublist(head, a.length - tail);
  final midB = b.sublist(head, b.length - tail);
  return [
    for (var i = 0; i < head; i++) (kind: ' ', text: a[i], line: i + 1),
    for (final (kind, i, j) in _middle(midA, midB))
      (
        kind: kind,
        text: kind == '+' ? midB[j] : midA[i],
        line: head + i + 1,
      ),
    for (var i = a.length - tail; i < a.length; i++)
      (kind: ' ', text: a[i], line: i + 1),
  ];
}

// A longest common subsequence keeps the diff short where the texts are
// small enough for its table; past that every middle line is shown as
// changed, which is still correct.
List<(String, int, int)> _middle(List<String> a, List<String> b) {
  if (a.length * b.length > 16000000) {
    return [
      for (var i = 0; i < a.length; i++) ('-', i, 0),
      for (var j = 0; j < b.length; j++) ('+', a.length, j),
    ];
  }
  final width = b.length + 1;
  final table = Int32List((a.length + 1) * width);
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      table[i * width + j] = a[i] == b[j]
          ? table[(i + 1) * width + j + 1] + 1
          : max(table[(i + 1) * width + j], table[i * width + j + 1]);
    }
  }
  final edits = <(String, int, int)>[];
  var i = 0;
  var j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] == b[j]) {
      edits.add((' ', i, j));
      i++;
      j++;
    } else if (i < a.length &&
        (j == b.length ||
            table[(i + 1) * width + j] >= table[i * width + j + 1])) {
      edits.add(('-', i, j));
      i++;
    } else {
      edits.add(('+', i, j));
      j++;
    }
  }
  return edits;
}
