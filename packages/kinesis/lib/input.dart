/// Gestures as pure logic: interactions, their combinations, the handoff of
/// a touch between regions, and time-stamped input events.
///
/// For the author of a control: an `Interaction` (press, tap, long press,
/// drag, scrub, follow, secondary click, hover dwell) takes
/// `InteractionInput`s and answers with `InteractionEvent`s, so a gesture
/// is checked by replaying a recording, with no screen. `InputPort` hands
/// a touch from one region to another.
///
/// It promises one way to stamp an event with its time, and that keyboard
/// and accessibility commands (`ActivateInput`, the value commands of
/// `AdjustInput`, the keyboard's request for a context menu,
/// `ContextMenuInput`), the secondary button and the scroll wheel
/// (`PointerScrollInput`) arrive on the same path as touches.
///
/// It never knows about widgets, focus or semantics, and imports neither
/// widgets nor rendering.
library;

export 'src/input/drag_interaction.dart'
    show DragInteraction, DragInteractionDetails;
export 'src/input/follow.dart' show FollowInteraction, PointerFollower;
export 'src/input/hover_dwell_interaction.dart' show HoverDwellInteraction;
export 'src/input/interaction.dart'
    show Interaction, InteractionSession, SessionOutput;
export 'src/input/interaction_event.dart'
    show
        ActivationEvent,
        InteractionEvent,
        InteractionUpdate,
        LongPressStartEvent,
        ScrubChangeEvent;
export 'src/input/interaction_input.dart'
    show
        ActivateInput,
        AdjustInput,
        ContextMenuInput,
        InteractionInput,
        PointerAcceptedInput,
        PointerCancelInput,
        PointerDownInput,
        PointerHoverInput,
        PointerMoveInput,
        PointerScrollInput,
        PointerUpInput;
export 'src/input/interaction_values.dart'
    show
        ActivationSource,
        AdjustRange,
        InteractionRole,
        MotionHaptic,
        PointerCancelReason,
        ValueCommand;
export 'src/input/long_press_interaction.dart' show LongPressInteraction;
export 'src/input/port.dart' show InputPort, PortEvent;
export 'src/input/press_interaction.dart' show PressInteraction;
export 'src/input/press_reach.dart' show PressReach;
export 'src/input/secondary_click_interaction.dart'
    show SecondaryClickInteraction;
export 'src/input/tap_interaction.dart' show TapInteraction;
