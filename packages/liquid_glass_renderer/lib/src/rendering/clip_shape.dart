import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';

/// The shape a clip keeps, in its own coordinates.
///
/// Shapes compare by value, a path by identity: a new path each frame would
/// add the clip again and break every copy signed over it.
@internal
@immutable
sealed class ClipShape {
  const ClipShape();

  /// The rect around what the clip keeps.
  Rect get bounds;

  /// Pushes the clip with [behavior] onto [builder], reusing [oldLayer] where
  /// it is a layer of the same kind.
  ui.EngineLayer push(
    ui.SceneBuilder builder,
    Clip behavior, {
    ui.EngineLayer? oldLayer,
  });

  /// Clips [context]'s canvas with [behavior] around [painter].
  void clipAndPaint(ClipContext context, Clip behavior, VoidCallback painter);
}

/// A clip to [rect].
@internal
final class RectClip extends ClipShape {
  /// A clip to [rect].
  const RectClip(this.rect);

  /// What the clip keeps.
  final Rect rect;

  @override
  Rect get bounds => rect;

  @override
  ui.EngineLayer push(
    ui.SceneBuilder builder,
    Clip behavior, {
    ui.EngineLayer? oldLayer,
  }) => builder.pushClipRect(
    rect,
    clipBehavior: behavior,
    oldLayer: oldLayer is ui.ClipRectEngineLayer ? oldLayer : null,
  );

  @override
  void clipAndPaint(ClipContext context, Clip behavior, VoidCallback painter) =>
      context.clipRectAndPaint(rect, behavior, rect, painter);

  @override
  bool operator ==(Object other) => other is RectClip && other.rect == rect;

  @override
  int get hashCode => rect.hashCode;
}

/// A clip to [rrect].
@internal
final class RRectClip extends ClipShape {
  /// A clip to [rrect].
  const RRectClip(this.rrect);

  /// What the clip keeps.
  final RRect rrect;

  @override
  Rect get bounds => rrect.outerRect;

  @override
  ui.EngineLayer push(
    ui.SceneBuilder builder,
    Clip behavior, {
    ui.EngineLayer? oldLayer,
  }) => builder.pushClipRRect(
    rrect,
    clipBehavior: behavior,
    oldLayer: oldLayer is ui.ClipRRectEngineLayer ? oldLayer : null,
  );

  @override
  void clipAndPaint(ClipContext context, Clip behavior, VoidCallback painter) =>
      context.clipRRectAndPaint(rrect, behavior, rrect.outerRect, painter);

  @override
  bool operator ==(Object other) => other is RRectClip && other.rrect == rrect;

  @override
  int get hashCode => rrect.hashCode;
}

/// A clip to [rsuperellipse].
@internal
final class RSuperellipseClip extends ClipShape {
  /// A clip to [rsuperellipse].
  const RSuperellipseClip(this.rsuperellipse);

  /// What the clip keeps.
  final RSuperellipse rsuperellipse;

  @override
  Rect get bounds => rsuperellipse.outerRect;

  @override
  ui.EngineLayer push(
    ui.SceneBuilder builder,
    Clip behavior, {
    ui.EngineLayer? oldLayer,
  }) => builder.pushClipRSuperellipse(
    rsuperellipse,
    clipBehavior: behavior,
    oldLayer: oldLayer is ui.ClipRSuperellipseEngineLayer ? oldLayer : null,
  );

  @override
  void clipAndPaint(ClipContext context, Clip behavior, VoidCallback painter) =>
      context.clipRSuperellipseAndPaint(
        rsuperellipse,
        behavior,
        rsuperellipse.outerRect,
        painter,
      );

  @override
  bool operator ==(Object other) =>
      other is RSuperellipseClip && other.rsuperellipse == rsuperellipse;

  @override
  int get hashCode => rsuperellipse.hashCode;
}

/// A clip to the oval inside [rect], pushed as a path, as [RenderClipOval]
/// pushes it.
@internal
final class OvalClip extends ClipShape {
  /// A clip to the oval inside [rect].
  OvalClip(this.rect);

  /// The rect the oval fills.
  final Rect rect;

  /// The oval, one path for the life of the clip.
  late final Path path = Path()..addOval(rect);

  @override
  Rect get bounds => rect;

  @override
  ui.EngineLayer push(
    ui.SceneBuilder builder,
    Clip behavior, {
    ui.EngineLayer? oldLayer,
  }) => builder.pushClipPath(
    path,
    clipBehavior: behavior,
    oldLayer: oldLayer is ui.ClipPathEngineLayer ? oldLayer : null,
  );

  @override
  void clipAndPaint(ClipContext context, Clip behavior, VoidCallback painter) =>
      context.clipPathAndPaint(path, behavior, rect, painter);

  @override
  bool operator ==(Object other) => other is OvalClip && other.rect == rect;

  @override
  int get hashCode => rect.hashCode;
}

/// A clip to [path].
@internal
final class PathClip extends ClipShape {
  /// A clip to [path].
  const PathClip(this.path);

  /// What the clip keeps.
  final Path path;

  static final _bounds = Expando<Rect>();

  @override
  Rect get bounds => _bounds[path] ??= path.getBounds();

  @override
  ui.EngineLayer push(
    ui.SceneBuilder builder,
    Clip behavior, {
    ui.EngineLayer? oldLayer,
  }) => builder.pushClipPath(
    path,
    clipBehavior: behavior,
    oldLayer: oldLayer is ui.ClipPathEngineLayer ? oldLayer : null,
  );

  @override
  void clipAndPaint(ClipContext context, Clip behavior, VoidCallback painter) =>
      context.clipPathAndPaint(path, behavior, bounds, painter);

  @override
  bool operator ==(Object other) =>
      other is PathClip && identical(other.path, path);

  @override
  int get hashCode => identityHashCode(path);
}
