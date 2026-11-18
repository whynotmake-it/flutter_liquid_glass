# Changelog

## 0.1.0-dev.1

Values and transactions (`package:kinesis/kinesis.dart`):

- `Spring` in SwiftUI's form (duration, bounce) and UIKit's (response,
  damping ratio), with a tracking spring, a retarget impulse, a release
  projection and a Reduce Motion alternative.
- `MotionValue`: a value with a target, what is on screen and its velocity;
  every retarget continues from the current value and velocity. Listeners
  hear it every frame it moves and once more when it rests on its target.
- `MotionConverter` for doubles, offsets, sizes, rects, radii and colors.
- `withSpring` and `withoutAnimation` transactions; `MotionTraits` and
  `MotionTraitsOverride` for Reduce Motion and other preferences.
- `MotionSelection`: a value derived from motions, recomputed once per
  frame when what it reads changed. `addRenderListener` hears it in the
  resolve phase, before paint.

The clock:

- `MotionClock`: one frame clock per binding. A frame runs the due
  scheduled actions, steps and publishes every moving value in a microtask
  after every ticker and before build, on the display's frame grid, then
  resolves after layout. Pointer events are stamped at their own time. The
  clock dozes until a later change and asks for no frames at rest.
- `ManualMotionClock` runs the same phases on demand.
- `MotionClock.schedulePublish` runs a callback once in the coming publish
  phase, after the frame's values stepped and before build.
- Errors thrown by listeners and scheduled actions are reported through
  `FlutterError` and do not stop the frame.
- `FrameCadence`: on a display faster than 90 Hz, once started, the app draws
  every second vsync while nothing fast moves. A scroll or a finger past
  UIKit's speed and a `Motion` with a floor above 60 Hz draw every vsync; a
  device that cannot keep up stays at the lower rate.

On screen:

- `MotionTransition`: offset, scale, rotation, opacity, blur, clip and size
  from listenable values, through one composited layer, without building,
  laying out or repainting the child.
- `MotionDriven`: any chain of single-child render-object widgets driven by
  motion values without building.
- `MotionLayout` and `SliverMotionList`: animate whatever layout did to
  their children under the frame's transaction, with `LayoutPlanner.flip`,
  a pure `LayoutPlan` and `MotionEffect` insert and remove effects.
  `MotionMeasure` reports a child's size in the frame that laid it out;
  `MotionResolveHost` places a render object from this frame's layout.
- In debug mode, `LayoutMotion` reports an id that its code asked for and
  that no layout ever had, such as a key's value in place of the key.
- `MotionScope` holds a `Motion` on the clock while it is in the tree;
  `MotionScroll` reads a scroll view as a motion.

Input:

- Pure `Interaction`s (`PressInteraction`, `LongPressInteraction`,
  `DragInteraction`, `TapInteraction`, `ScrubInteraction`,
  `FollowInteraction`, with `exclusively` and `simultaneously`) and
  `InteractionSession`, which replays stamped input exactly, including
  UIKit's 0.15 s scroll delay.
- `InputRegion` feeds them from pointer, keyboard, hover and accessibility
  input with stamped times and the raw release velocity; `InputPort` takes
  the rest of a touch after a hand-off.

Presentations:

- `Presentation` and its `PresentationHandle`: the motion a presentation
  plays and the content over it. `PresentationRoute` (a popup),
  `PresentationPageRoute` (a page) and `PresentationPortal` (the root
  overlay, no route) are its shells. A route's animation status follows
  the motion, and a push completes at the open's rest.
- One dismissal gate (`DismissPolicy`, then the content's `PopScope`s)
  serves outside taps, Escape, Back, a screen reader's dismiss and the
  content's own gestures; a dismissal closes its own presentation, never
  the top one. While modal, the barrier absorbs taps and hides what is
  below from screen readers. A presentation that is leaving takes no new
  touches, so what is below does not wait for its close to end.
  `showPresentation`, `PresentationLevel` and `PresentationContext` pick the
  navigator inside the presenting view.
- `MotionSource` and `MotionSourceBox`: what a presentation grows out of
  and back into.

Writing motions (`package:kinesis/motion.dart`):

- `Motion`: a tree of parts with one time cursor and one timeline of
  delayed reactions; every command takes an explicit time, so a motion is
  a pure function of its stamped inputs and replays exactly in a test.
  The clock steps it while something looks at it and settles it at rest.
- Parts: `MotionValue` with `MotionValueCommands`, `MotionRect` on
  `RectSprings`, `Presence`, `TimedValue`, `MotionSignal`, `MotionLoop`
  (a per-frame loop at its own fixed rate) and `LayoutMotion`; rest
  tolerances are `MotionRest`.
- `Band` (a rubber band), `Projection` (where a release lands and which
  stop or exit it picks) and `Ramp`.
- `Presented` and `Sourced` connect a motion to a presentation shell and
  its source.
