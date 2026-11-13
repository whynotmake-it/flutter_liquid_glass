import 'package:sample/base.dart';
import 'package:sample/src/base/a.dart';
import 'package:sample/testing.dart';

class T {
  dynamic allowedHere;
}

class Shown {
  // Must show: the fixture holds one allowed print.
  void kept() => print('kept');

  // Must show:
  void bare() => print('bare');

  void stray() => print('stray');
}
