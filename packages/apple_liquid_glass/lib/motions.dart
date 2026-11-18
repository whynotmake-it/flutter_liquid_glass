/// The measured laws of iOS motion: how the switch, slider, lens, sheet,
/// bars, menus, alert, search and page zoom move, as pure classes on
/// kinesis's `Motion`, and the bar and menu layouts as plain math.
///
/// For the controls of this package, and for the tests that replay
/// recordings from an iPhone against the same laws. A host tells a law
/// what happened and reads its values; the springs and tuning classes
/// stay inside.
///
/// It promises that a number in a law carries its source, a measurement on
/// the device or UIKit's tuning, in its dartdoc.
///
/// It never imports Flutter's widgets or rendering libraries, and never
/// decides what is drawn.
library;

export 'src/motions/activity_motion.dart' show ActivityMotion;
export 'src/motions/alert_motion.dart' show AlertMotion;
export 'src/motions/bar_frames.dart'
    show GlassBarCapsuleFrame, GlassBarCapsuleLayout, GlassBarItemFrame;
export 'src/motions/bar_layout.dart'
    show
        GlassBarButtonKind,
        GlassBarButtonSpec,
        GlassBarCapsuleSpec,
        GlassBarItemId,
        GlassBarMetrics,
        GlassBarSegment,
        layoutGlassBar;
export 'src/motions/bar_motion.dart' show GlassBarMotion;
export 'src/motions/bar_transition_spec.dart' show GlassBarTransitionSpec;
export 'src/motions/content_offset_motion.dart' show ContentOffsetMotion;
export 'src/motions/date_picker_motion.dart'
    show
        DatePickerCalendarMotion,
        DatePickerLabelMotion,
        DatePickerMotion,
        DatePickerPlacement,
        placeDatePicker;
export 'src/motions/flex_interaction.dart' show FlexValues;
export 'src/motions/glass_press.dart' show FlexLaw, GlassPress;
export 'src/motions/lens_motion.dart' show LensMotion;
export 'src/motions/lens_values.dart' show LensEvent, LensSelected, LensSlot;
export 'src/motions/list_highlight.dart' show ListRowHighlight;
export 'src/motions/menu_context_hold.dart' show ContextHold;
export 'src/motions/menu_event.dart'
    show MenuActivated, MenuEvent, MenuHighlightChanged, MenuTapped;
export 'src/motions/menu_layout.dart' show MenuLayout;
export 'src/motions/menu_metrics.dart' show MenuMetrics;
export 'src/motions/menu_motion.dart' show MenuMotion;
export 'src/motions/menu_placed.dart'
    show MenuPlaced, MenuPlacedKind, MenuTarget, MenuTargetKind;
export 'src/motions/menu_specs.dart'
    show
        MenuDividerSpec,
        MenuLoadingSpec,
        MenuRowSpec,
        MenuSectionSpec,
        MenuSpec,
        MenuSpecSize,
        MenuWidgetSpec;
export 'src/motions/menu_values.dart'
    show MenuAttachment, MenuBlob, MenuCapsuleSource, MenuCard, MenuSource;
export 'src/motions/navigation_motion.dart'
    show NavigationPopMotion, PageMotion, PageSlideMotion;
export 'src/motions/page_control_motion.dart'
    show PageControlEvent, PageControlMotion, PageControlPicked;
export 'src/motions/popover_motion.dart'
    show PopoverArrowDirection, PopoverMotion, PopoverPlacement, placePopover;
export 'src/motions/popover_shape.dart' show PopoverShape;
export 'src/motions/presence_motion.dart' show LargeTitleSnap, PresenceMotion;
export 'src/motions/search_motion.dart'
    show
        SearchBarGeometry,
        SearchMotion,
        SearchTabGeometry,
        searchBarLayout,
        searchTabLayout;
export 'src/motions/search_tab_motion.dart' show SearchTabMotion;
export 'src/motions/segment_highlight.dart' show SegmentHighlight;
export 'src/motions/selector_motion.dart'
    show GlassSelectorMotion, SelectorGeometry, SelectorMotion;
export 'src/motions/sheet_detent.dart' show GlassSheetDetent;
export 'src/motions/sheet_event.dart'
    show SheetDetentChanged, SheetDismissRefused, SheetDismissed, SheetEvent;
export 'src/motions/sheet_layout.dart' show SheetLayout;
export 'src/motions/sheet_motion.dart' show SheetMotion;
export 'src/motions/slider_motion.dart'
    show
        SliderChangeEnded,
        SliderChanged,
        SliderEvent,
        SliderFelt,
        SliderMotion;
export 'src/motions/small_lens.dart' show SmallLens;
export 'src/motions/stacked_search_motion.dart' show StackedSearchMotion;
export 'src/motions/swipe_actions_motion.dart' show SwipeActionsMotion;
export 'src/motions/switch_motion.dart'
    show SwitchChanged, SwitchEvent, SwitchMotion, SwitchShown;
export 'src/motions/tab_bar_layout.dart' show TabBarLayout;
export 'src/motions/tab_minimize.dart'
    show GlassTabBarMinimizeBehavior, ScrollAway, TabBarMinimizeMotion;
export 'src/motions/touch_glow.dart' show TouchGlowMotion;
export 'src/motions/zoom_page_motion.dart' show ZoomPageMotion;
