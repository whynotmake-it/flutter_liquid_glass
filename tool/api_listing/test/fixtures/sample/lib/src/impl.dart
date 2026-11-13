import 'package:dep/dep.dart';
import 'package:dep/src/hidden.dart';
import 'package:meta/meta.dart';

class _Base {}

class Engine {}

enum Mode { slow, fast }

class Widget extends _Base {
  Widget(this.size, {required this.mode, this.label = 'x', @internal Engine? engine});

  final int size;

  final Mode mode;

  final String label;

  Hidden get hidden => Hidden();

  Shown shown<T extends Object>(T value) => Shown();

  @internal
  Engine get engine => Engine();

  @override
  String toString() => 'Widget';
}

typedef Callback = void Function(Engine engine);

int top(int a, [int b = 1]) => a + b;
