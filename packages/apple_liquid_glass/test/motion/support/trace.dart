import 'dart:convert';

import '../../support/fixtures.dart';

/// One touch sample recorded by the UIKit probe.
class TraceTouch {
  /// Creates a touch sample.
  const TraceTouch(this.t, this.phase, this.x, this.y);

  /// Seconds on the device's media clock.
  final double t;

  /// UITouch.Phase: 0 began, 1 moved, 2 stationary, 3 ended, 4 cancelled.
  final int phase;

  /// Window-space x, in points.
  final double x;

  /// Window-space y, in points.
  final double y;
}

/// One presentation-layer sample of a tracked UIKit view.
class TraceFrame {
  /// Creates a frame sample from its decoded JSON row.
  TraceFrame(this.raw);

  /// The decoded row.
  final Map<String, Object?> raw;

  /// Seconds on the device's media clock.
  double get t => _d('t');

  /// The view's class name; compacted lens fixtures omit it.
  String get cls => raw['cls'] as String? ?? '_UILiquidLensView';

  /// A stable identity of the view within one recording.
  int get id => raw['id']! as int;

  /// Window-space center x of the bounding box, in points.
  double get x => _d('x');

  /// Window-space center y of the bounding box, in points.
  double get y => _d('y');

  /// Bounding-box width including the layer transform, in points.
  double get w => _d('w');

  /// Bounding-box height including the layer transform, in points.
  double get h => _d('h');

  /// Presentation bounds width, in points.
  double get bw => _d('bw');

  /// Presentation bounds height, in points.
  double get bh => _d('bh');

  /// Layer transform scale x.
  double get sx => _d('sx');

  /// Layer transform scale y.
  double get sy => _d('sy');

  /// Layer opacity.
  double get a => _d('a');

  /// Reads a numeric field.
  double _d(String key) => (raw[key]! as num).toDouble();

  /// Reads an optional numeric field.
  double? opt(String key) => (raw[key] as num?)?.toDouble();

  /// The layer path of a layer row, such as `0.0.1`.
  String? get path => raw['p'] as String?;

  /// Layer translation x, in points.
  double get tx => _d('tx');
}

/// A probe recording: touches and per-frame samples of tracked views.
class Trace {
  /// Creates a trace from decoded parts.
  Trace(
    this.touches,
    this.frames, {
    this.layers = const [],
    this.events = const [],
    this.states = const [],
  });

  /// Loads a probe jsonl file.
  factory Trace.load(String path) {
    final touches = <TraceTouch>[];
    final frames = <TraceFrame>[];
    final layers = <TraceFrame>[];
    final events = <Map<String, Object?>>[];
    final states = <Map<String, Object?>>[];
    for (final line in Fixtures.lines(path)) {
      if (line.trim().isEmpty) continue;
      final row = (jsonDecode(line) as Map).cast<String, Object?>();
      switch (row['k']) {
        case 'touch':
          touches.add(
            TraceTouch(
              (row['t']! as num).toDouble(),
              row['phase']! as int,
              (row['x']! as num).toDouble(),
              (row['y']! as num).toDouble(),
            ),
          );
        case 'frame':
          frames.add(TraceFrame(row));
        case 'L':
          layers.add(TraceFrame(row));
        case 'evt':
          events.add(row);
        case 'state':
          states.add(row);
      }
    }
    return Trace(
      touches,
      frames,
      layers: layers,
      events: events,
      states: states,
    );
  }

  /// Every touch sample, in recording order.
  final List<TraceTouch> touches;

  /// Every frame sample, in recording order.
  final List<TraceFrame> frames;

  /// Every layer-tree sample, in recording order; rows are logged only
  /// when a layer changed.
  final List<TraceFrame> layers;

  /// Every control event row (`valueChanged`, `touchDown`, ...).
  final List<Map<String, Object?>> events;

  /// Every control state row (`on`, `v`, ...), logged when it changed.
  final List<Map<String, Object?>> states;

  /// Layer samples of the layer at [path].
  List<TraceFrame> layer(String path) => [
    for (final f in layers)
      if (f.path == path) f,
  ];

  /// Frames of views of class [cls] whose center lies within [yRange].
  List<TraceFrame> track(String cls, {(double, double)? yRange}) => [
    for (final f in frames)
      if (f.cls == cls &&
          (yRange == null || (f.y >= yRange.$1 && f.y <= yRange.$2)))
        f,
  ];
}
