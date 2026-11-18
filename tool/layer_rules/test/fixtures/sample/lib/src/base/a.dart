import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:other/x.dart';
import 'package:sample/top.dart';

import 'b.dart';

/* dynamic in a block comment */
// dynamic in a line comment
class A {
  // ignore: unused_field
  dynamic x;
  final s = 'dynamic in a string';
  late final u = 'a ${x as dynamic} b';
}
