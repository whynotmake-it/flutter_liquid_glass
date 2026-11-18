import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:apple_liquid_glass/src/motions/menu_fusion.dart';
import 'package:apple_liquid_glass/src/motions/menu_outline_math.dart';
import 'package:meta/meta.dart';

/// Background isolates that fuse menu silhouettes ahead of the frames
/// that show them.
///
/// The UI isolate posts, each frame, the inputs it expects the next
/// `MenuFusion.prefetchFrames` frames to fuse ([request]: the menu shape,
/// the button shape, the fusion radius and whether the field is wanted,
/// `MenuFusion.encode`);
/// a worker computes `menuSilhouetteParts` and sends the parts back,
/// the field samples without a copy, or the edge alone when the request
/// asks for no field. Up to [poolSize] workers run, one request each;
/// requests made while every worker runs wait, the [waitingLimit] newest
/// of them, for the first worker that returns. [take] hands out an arrived
/// fusion whose inputs are within a tolerance of the
/// inputs the frame fuses; [reset] drops what no frame will read.
///
/// The workers spawn on demand and live for the isolate's lifetime; they
/// fail closed - any error stops them, and every fusion is then computed
/// where it is needed.
@internal
abstract final class FusionWorker {
  /// Whether this device runs the worker: only with at least six CPU
  /// cores, since on fewer the workers compete with the UI and raster
  /// threads and cost more frames than they save.
  static final bool supported = Platform.numberOfProcessors >= 6;

  /// The most workers that run at once.
  static const int poolSize = 4;

  /// The most requests that wait for a worker.
  static const int waitingLimit = 3;

  /// The most arrived fusions kept for [take].
  static const int keep = 9;

  static final List<_Worker> _workers = [];
  static ReceivePort? _port;
  static bool _failed = false;
  static final List<(Float64List, Object?)> _waiting = [];
  static final List<(Float64List, OutlineParts, Object?)> _ready = [];

  /// Asks a worker for the fusion of [inputs] on behalf of [owner], the
  /// requester a later [reset] can drop alone.
  ///
  /// A request whose inputs are within [_sameRequest] of one waiting,
  /// being computed or arrived is dropped: a motion predicts each frame
  /// from several frames before it, and the predictions agree.
  static void request(Float64List inputs, {Object? owner}) {
    if (_failed) return;
    if (_known(inputs)) return;
    final port = _port ??= _listen();
    for (final worker in _workers) {
      if (!worker.busy && worker.send != null) {
        worker.dispatch(inputs, owner);
        return;
      }
    }
    _waiting.add((inputs, owner));
    if (_waiting.length > waitingLimit) _waiting.removeAt(0);
    if (_workers.length < poolSize &&
        _workers.every((_Worker worker) => worker.send != null)) {
      _spawn(port);
    }
  }

  /// An arrived fusion whose every geometric input is within [tolerance]
  /// of [inputs], whose fusion radius samples the same grid with the same
  /// kernel (`MenuFusion.sameGrid`) and that carries the field when
  /// [inputs] ask for it, the newest such; it is handed out once, and the
  /// fusions that arrived before it are dropped. A fusion with its field
  /// serves a request for the edge alone too.
  static OutlineParts? take(Float64List inputs, double tolerance) {
    for (var k = _ready.length - 1; k >= 0; k--) {
      final (ready, parts, _) = _ready[k];
      if (_matches(ready, inputs, tolerance)) {
        _ready.removeRange(0, k + 1);
        return parts;
      }
    }
    return null;
  }

  /// How close, in logical pixels, two requests' inputs are for the later
  /// to add nothing.
  static const double _sameRequest = MenuFusion.prefetchTolerance / 50;

  static bool _known(Float64List inputs) {
    bool same(Float64List other) {
      if (other[11] != inputs[11]) return false;
      for (var i = 0; i < 11; i++) {
        if (!((other[i] - inputs[i]).abs() <= _sameRequest)) return false;
      }
      return true;
    }

    for (final (waiting, _) in _waiting) {
      if (same(waiting)) return true;
    }
    for (final worker in _workers) {
      if (worker.busy && !worker.stale && same(worker.inputs!)) return true;
    }
    for (final (ready, _, _) in _ready) {
      if (same(ready)) return true;
    }
    return false;
  }

  static bool _matches(Float64List a, Float64List b, double tolerance) {
    for (var i = 0; i < 11; i++) {
      if (!((a[i] - b[i]).abs() <= tolerance)) return false;
    }
    return (a[11] != 0 || b[11] == 0) && MenuFusion.sameGrid(a[10], b[10]);
  }

  /// Whether fusions have arrived that [take] has not handed out.
  @visibleForTesting
  static bool get debugHasReady => _ready.isNotEmpty;

  /// Drops the fusions and the requests not yet handed out, those of
  /// [owner] alone when it is given; the fusions the workers are computing
  /// for them now are dropped when they arrive.
  static void reset({Object? owner}) {
    bool mine(Object? of) => owner == null || identical(of, owner);
    _ready.removeWhere(
      ((Float64List, OutlineParts, Object?) ready) => mine(ready.$3),
    );
    _waiting.removeWhere(((Float64List, Object?) waiting) => mine(waiting.$2));
    for (final worker in _workers) {
      if (worker.busy && mine(worker.owner)) worker.stale = true;
    }
  }

  static ReceivePort _listen() {
    final port = ReceivePort('menu fusion');
    port.listen(_receive);
    return port;
  }

  static void _spawn(ReceivePort port) {
    final worker = _Worker(_workers.length);
    _workers.add(worker);
    Isolate.spawn(
      _main,
      (port.sendPort, worker.index),
      debugName: 'menu fusion ${worker.index}',
    ).then<void>((Isolate isolate) {
      if (_failed) {
        isolate.kill(priority: Isolate.immediate);
        return;
      }
      worker.isolate = isolate;
      isolate.addOnExitListener(port.sendPort, response: false);
    }, onError: (Object _) => _fail());
  }

  static void _fail() {
    _failed = true;
    for (final worker in _workers) {
      worker.send = null;
      worker.isolate?.kill(priority: Isolate.immediate);
      worker.isolate = null;
    }
    reset();
    _port?.close();
  }

  static void _receive(Object? message) {
    switch (message) {
      case (final int index, final SendPort send):
        final worker = _workers[index];
        worker.send = send;
        _next(worker);
      case [
        final int index,
        final Float64List inputs,
        final Float64List points,
        final Int32List loops,
        final _SentGrid? grid,
      ]:
        final worker = _workers[index];
        if (!worker.stale) {
          _ready.add((
            inputs,
            OutlineParts(
              points: points,
              loops: loops,
              grid: switch (grid) {
                final grid? => (
                  samples: grid.samples.materialize().asFloat32List(),
                  cols: grid.cols,
                  rows: grid.rows,
                  origin: Offset(grid.x, grid.y),
                  step: grid.step,
                ),
                null => null,
              },
            ),
            worker.owner,
          ));
          if (_ready.length > keep) _ready.removeAt(0);
        }
        worker.busy = false;
        worker.stale = false;
        _next(worker);
      default:
        _fail();
    }
  }

  static void _next(_Worker worker) {
    if (_waiting.isEmpty) return;
    final (inputs, owner) = _waiting.removeAt(0);
    worker.dispatch(inputs, owner);
  }

  static void _main((SendPort, int) start) {
    final (reply, index) = start;
    final port = ReceivePort();
    reply.send((index, port.sendPort));
    port.listen((Object? message) {
      final v = message! as Float64List;
      final parts = menuSilhouetteParts(
        RRect.fromLTRBXY(v[0], v[1], v[2], v[3], v[4], v[4]),
        RRect.fromLTRBXY(v[5], v[6], v[7], v[8], v[9], v[9]),
        v[10],
        withField: v[11] != 0,
      );
      final grid = parts.grid;
      reply.send([
        index,
        v,
        Float64List.fromList(parts.points),
        parts.loops,
        if (grid == null)
          null
        else
          (
            samples: TransferableTypedData.fromList([grid.samples]),
            cols: grid.cols,
            rows: grid.rows,
            x: grid.origin.dx,
            y: grid.origin.dy,
            step: grid.step,
          ),
      ]);
    });
  }
}

/// One fusion isolate as the UI isolate sees it.
class _Worker {
  _Worker(this.index);

  final int index;
  SendPort? send;
  Isolate? isolate;
  bool busy = false;
  bool stale = false;
  Object? owner;
  Float64List? inputs;

  void dispatch(Float64List inputs, Object? owner) {
    busy = true;
    stale = false;
    this.owner = owner;
    this.inputs = inputs;
    send!.send(inputs);
  }
}

typedef _SentGrid = ({
  TransferableTypedData samples,
  int cols,
  int rows,
  double x,
  double y,
  double step,
});
