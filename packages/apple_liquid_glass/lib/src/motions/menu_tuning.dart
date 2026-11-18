import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/motions/flex_interaction.dart';
import 'package:apple_liquid_glass/src/motions/flex_spec.dart';
import 'package:apple_liquid_glass/src/motions/menu_event.dart';
import 'package:apple_liquid_glass/src/motions/menu_morph_spec.dart';
import 'package:apple_liquid_glass/src/motions/menu_values.dart';
import 'package:apple_liquid_glass/src/motions/touch_glow.dart';
import 'package:flutter/painting.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';

/// The tuning of a glass button's menu, as measured on iOS 27.
///
/// The springs, delays and metrics are fitted to frame-by-frame
/// recordings of a `UIButton` with a glass configuration whose menu is its
/// primary action. Lengths are logical pixels, times seconds.
class MenuTuning {
  /// Creates a tuning from explicit values.
  const MenuTuning({
    this.morph = MenuMorphSpec.standard,
    this.dim,
    this.cornerRadius = 32,
    this.openingRadius = 195.4,
    this.radiusDelay = 0.098,
    this.sourceEndScale = 0.25,
    this.sourceTravel = 0.25,
    this.sourceReturnTolerance = 0.17,
    this.sourceReturnAfter = 0.4,
    this.capsuleAloneLanding = 2,
    this.capsuleSharedLanding = 3.33,
    this.capsuleHoldLanding = 8,
    this.crossfadeBlur = 4,
    this.fadeLead = 0.015,
    this.lookFadeStart = 0.07,
    this.lookFadeEnd = 0.42,
    this.lookStretch = 2.5,
    this.contentFadeStart = 0,
    this.contentFadeEnd = 1,
    this.contentCloseFadeEnd = 0.53,
    this.contentKickScale = 1.45,
    this.contentBlur = 8,
    this.contentKickBlur = 6,
    this.tapOpenDelay = 0.089,
    this.holdDuration = 0.22,
    this.reach = glassButtonReach,
    this.dismissDelay = 0.059,
    this.earlyCloseDelay = 0.016,
    this.actionDelay = 0.016,
    this.pressDelay = 0.015,
    this.sourceRelax = 0.05,
    this.openKickSpring = const Spring.response(0.2048, dampingRatio: 0.651),
    this.openKickGain = 4.229,
    this.closeKickSpring = const Spring.response(0.3396, dampingRatio: 0.8425),
    this.closeKickImpulse = 1450,
    this.closeKickDelay = 0.012,
    this.closeKickReach = 31.7,
    this.sourceKickSpring = const Spring.response(0.3102, dampingRatio: 0.6335),
    this.sourceKickGain = 2.02,
    this.edgeMargin = defaultEdgeMargin,
    this.glowDiameter = 160,
    this.glowRiseLag = 0.03,
    this.glowMinimumLit = 0.1,
    this.flex = FlexSpec.menu,
    this.flexInBoundsPoints = 40,
    this.flexPulseSpring = const Spring.response(0.574, dampingRatio: 0.548),
    this.flexPulseRate = 30,
    this.flexPulseRetargetStep = 1 / 60,
    this.flexDelay = 0.023,
    this.fusionRadius = 20,
    this.fusionCloseAmplitude = 20.95,
    this.fusionOpenRise = 0.0161,
    this.fusionCloseRise = 0.0213,
    this.fusionOpenHold = 0.199,
    this.fusionCloseHold = 0.057,
    this.fusionSpring = const Spring.response(0.4286),
    this.fusionCutoff = 0.2,
    this.submenuSpring = const Spring.response(0.395, dampingRatio: 0.86),
    this.submenuDelay = 0.076,
    this.deeperSubmenuSpring = const Spring.response(0.405, dampingRatio: 0.84),
    this.deeperSubmenuDelay = 0.04,
    this.backSpring = const Spring.response(0.4),
    this.backDelay = 0.022,
    this.hoverOpenDelay = 0.525,
    this.submenuActionDelay = 0.019,
    this.submenuCloseDelay = 0.031,
    this.keptActionDelay = 0.02,
    this.parentScale = 0.97,
    this.parentRowOpacity = 0.5,
    this.cardStartWidth = 230,
    this.cardLead = 36,
    this.cardRowsFadeIn = 0.25,
    this.cardRowsFadeOut = 0.55,
    this.cardPlatterFade = 0.3,
    this.cardHeaderBoldStart = 0.15,
    this.cardHeaderBoldEnd = 0.35,
    this.cardChevronTurn = 0.4,
    this.cardChevronBack = 0.2,
    this.cardHeaderBoldBack = 0.9,
    this.cardCloseFadeEnd = 0.2,
    this.cardCloseCenter = 0.5,
    this.cardContainerSpring = const Spring.response(0.35, dampingRatio: 0.85),
    this.cardContainerDelay = 0,
    this.cardContainerEndWidth = 50,
    this.cardGone = 0.007,
    this.growSpring = const Spring.response(0.565, dampingRatio: 0.84),
    this.growDelay = 0.045,
    this.shrinkSpring = const Spring.response(0.4),
    this.shrinkDelay = 0.03,
  });

  /// The horizontal placement margin from the device menu traces.
  static const double defaultEdgeMargin = 8;

  /// The numerical integration step of the measured driven kicks, in
  /// seconds: the kicks step on a fixed grid of it in motion time.
  ///
  /// NEAR: the kicks were fitted stepping this long between frame samples;
  /// on the grid the menu kick stays within 0.85 pt of that at its 31 pt
  /// peak and the button kick within 0.08 pt (menu-button.md, Spec -
  /// kicks).
  static const double kickIntegrationStep = 0.001;

  /// The driven kick displacement considered at rest, in points.
  static const double kickRestValue = 0.01;

  /// The driven kick velocity considered at rest, in points per second.
  static const double kickRestVelocity = 0.1;

  /// How far, in points, a finger that touched down beside the menu moves
  /// before the menu closes under it: 14 - 22 at the point the close started,
  /// 67 - 128 ms after its first move, at about 250 points a second on an
  /// iPhone 16 Pro. The captures do not tell a distance from a time; a still
  /// finger holds the menu open until its lift (NEAR).
  static const double outsideMoveClose = 18;

  /// The largest move, in points, of a menu edge that the flex pulse
  /// channel may still make once it stops stepping while a finger rests.
  ///
  /// A NEAR trade, not a measured value (0.75 px on a 3x screen at most;
  /// the bound is the channel's largest possible
  /// remaining swing, the swing itself is smaller): the channel
  /// ([MenuTuning.flexPulseSpring]) stops stepping once what is left
  /// of it cannot move an edge by more than this, and the shape keeps that
  /// remainder until the finger moves or lifts. Without it a 4 pt slide on
  /// a row keeps the menu drawing a frame per channel step through about
  /// 0.7 s of sub-pixel ringing (the perf_counts menu-held scene: 238
  /// frames at 0.01 pt, 224 at this value, 226 for the fitted model's
  /// sway at the same rest).
  static const double flexPulseRest = 0.25;

  /// The largest move, in points, of a menu edge that the flex's return
  /// may still make when it counts as at rest.
  ///
  /// A NEAR trade, not a measured value (0.03 px on a 3x screen,
  /// invisible): the return on the flex spec's scale spring stops driving
  /// frames below it.
  static const double flexReturnRest = 0.01;

  /// The context preview/menu margin inside the safe area, in points.
  /// iOS 27 simulator fit captures (2026-10-24): a 390-point card in a
  /// 402-point window fits to 370; a tall preview spans y=78..824 with
  /// system insets 62/34. See the context-menu passport.
  static const double contextMargin = 16;

  /// The spring a submenu card grows out of its row on, over the root
  /// menu: one spring for every property (iPhone 16 Pro, iOS 27.0.1,
  /// `_UIContextMenuListView` frames; 0.37 pt rms on the card height).
  final Spring submenuSpring;

  /// Seconds between the release on a submenu row of the root menu and
  /// the start of its card.
  final double submenuDelay;

  /// The spring of a card opened from another card.
  final Spring deeperSubmenuSpring;

  /// Seconds between the release on a submenu row of a card and the
  /// start of the next card.
  final double deeperSubmenuDelay;

  /// The spring a card shrinks back into its row on, critically damped.
  final Spring backSpring;

  /// Seconds between the release on a card's header and the start of the
  /// way back.
  final double backDelay;

  /// Seconds a held finger rests on a submenu row before its card opens
  /// (0.523 and 0.527 s in two device runs).
  final double hoverOpenDelay;

  /// Seconds between the release on a row of a card and its action.
  final double submenuActionDelay;

  /// Seconds between the release on a row of a card and the start of the
  /// whole menu's close: the menu glass of mm-sub-select replays the close
  /// spring at 0.19 pt RMS from 0.031 s after the lift, together with
  /// the container; a release on a root row closes after [dismissDelay].
  final double submenuCloseDelay;

  /// Seconds between the release on a row that keeps the menu open and
  /// its action.
  final double keptActionDelay;

  /// The scale of every card under an open card, per card above it,
  /// about the top center of the menu, including its glass platter
  /// (device list widths: 250, 242.5, 235.225 pt).
  final double parentScale;

  /// The opacity of the rows of a card under an open card.
  final double parentRowOpacity;

  /// The width a card starts at, centered on its row.
  final double cardStartWidth;

  /// How far above its row's center an open card's top sits: the header
  /// centers 5 pt above the row.
  final double cardLead;

  /// The card progress at which a growing card's rows are fully shown:
  /// on the device film the rows read at full contrast while the card is
  /// still small, clipped by its edges rather than faded.
  final double cardRowsFadeIn;

  /// The fraction of its progress at the start of the way back by which
  /// a card's rows have faded out: on film they are gone while the card
  /// is still over half its size. The header is not faded: it turns back
  /// into the row it came from.
  final double cardRowsFadeOut;

  /// The card progress below which the card's platter fades, as the
  /// square root of progress over this value: on film the shrunk card
  /// still shows as a pill around its row at a quarter of its progress
  /// and fades out as it reaches the row.
  final double cardPlatterFade;

  /// The card progress at which a growing card's header title starts to
  /// turn from the row's regular weight to its bold one (film).
  final double cardHeaderBoldStart;

  /// The card progress at which a growing card's header title is bold
  /// (film).
  final double cardHeaderBoldEnd;

  /// The fraction of its progress at the start of the way back at which a
  /// card's header title is regular again (film: bold on one frame,
  /// regular on the next).
  final double cardHeaderBoldBack;

  /// The card progress at which a growing card's chevron has turned from
  /// pointing at the trailing edge to pointing down (film, read by eye).
  final double cardChevronTurn;

  /// The fraction of its progress at the start of the way back at which
  /// a card's chevron points at the trailing edge again (film, read by
  /// eye).
  final double cardChevronBack;

  /// The menu progress at which the top card's rows and platter have
  /// faded out while the whole menu closes: UIKit shrinks the open card
  /// with the menu shape at full contrast and without the content blur
  /// of the root list, fading it only near the end (device film, light
  /// and dark: legible at a fifth of its size).
  final double cardCloseFadeEnd;

  /// The progress span over which opening content approaches the open
  /// card's center. Closing stacks use [cardContainerSpring] instead.
  final double cardCloseCenter;

  /// The closing spring of the submenu lists' container, fitted to
  /// device window bounds at 0.016 pt RMS, independently of the glass.
  final Spring cardContainerSpring;

  /// The container's delay after the close starts, in seconds. The
  /// container and the menu glass start together: in mm-sub-tap the
  /// container fit starts 0.0197 s and the glass 0.0200 s after the
  /// release plus 0.04 s (container records: 9-20 ms, mean 15.1 ms).
  final double cardContainerDelay;

  /// The width the 250 pt list container shrinks to on the device.
  final double cardContainerEndWidth;

  /// The progress below which a card on its way back is gone: on the
  /// device film the pill it leaves around its row disappears at once
  /// about 0.45 s into the critically damped way back.
  final double cardGone;

  /// The spring the menu grows on when its content gets taller while it
  /// is open (a row added through `updateVisibleMenu`, a deferred group
  /// answered; both fit 0.565 / 0.84 on the device).
  final Spring growSpring;

  /// Seconds between a content change (the action that made it) and the
  /// start of the growth: 0.045 and about 0.03 in two device runs, about
  /// 0.07 after the touch-up that ran the action.
  final double growDelay;

  /// The spring the menu shrinks on when its content gets shorter,
  /// critically damped.
  final Spring shrinkSpring;

  /// Seconds between a content change and the start of the shrink (about
  /// 0.05 after the touch-up that ran the action).
  final double shrinkDelay;

  /// The morph tuning the menu's open and close springs come from.
  final MenuMorphSpec morph;

  /// How the page under the menu dims, or null for a menu that leaves it
  /// as it is.
  final MenuDim? dim;

  /// The spring that opens the menu: the morph's eject spring at its
  /// speed.
  Spring get openSpring => morph.atSpeed(morph.eject);

  /// The spring that closes the menu: the morph's absorb spring at its
  /// speed.
  Spring get closeSpring => morph.atSpeed(morph.absorb);

  /// The corner radius of the open menu.
  final double cornerRadius;

  /// The corner radius the opening shape starts from before it eases to
  /// [cornerRadius]; the shape stays a capsule while it is smaller than
  /// this.
  final double openingRadius;

  /// Seconds the corner radius lags behind the opening.
  final double radiusDelay;

  /// The scale the button shrinks to inside the open menu.
  final double sourceEndScale;

  /// How far the shrinking button travels toward the menu center, as a
  /// fraction of the distance.
  final double sourceTravel;

  /// How close the source's shape must be to its rest for a close to end, half
  /// a pixel at 3x.
  ///
  /// The springs ring on for about 250 ms more, moving nothing the eye can see,
  /// while the menu's layer keeps its glass on screen and the real source stays
  /// hidden. Ending here is near, not identical: the last sixth of a point of
  /// the ring is skipped.
  final double sourceReturnTolerance;

  /// How long a close runs before it may end at [sourceReturnTolerance]: past
  /// the close's kick, which peaks at about 0.15 s and is down to half a point
  /// by 0.4 s (replayed recordings).
  final double sourceReturnAfter;

  /// How far past the sides of a bar capsule holding one item a tap's menu
  /// lands: the settled right edge is 388 against the capsule's 386 (iPhone 16
  /// Pro).
  final double capsuleAloneLanding;

  /// How far past the sides of a bar capsule holding several items a tap's menu
  /// lands, whichever item opened it: the settled right edge is 389.33 against
  /// the capsule's 386 with two and with three items (iPhone 16 Pro).
  final double capsuleSharedLanding;

  /// How far past the sides of a bar capsule a hold's menu lands: the settled
  /// right edge is 394 against the capsule's 386 with three items (iPhone 16
  /// Pro). Used for any number of items, which is an approximation.
  final double capsuleHoldLanding;

  /// The blur radius of the button's look per unit of progress.
  final double crossfadeBlur;

  /// Seconds ahead at which the fades of the button's look and of the
  /// content read the progress spring.
  ///
  /// The fades lead the shapes by this much, so they run a little ahead of
  /// the geometry in both directions: the look leaves and the content
  /// arrives early while the menu opens, and the content leaves and the
  /// look returns early while it closes.
  final double fadeLead;

  /// The progress up to which the button's look stays fully opaque.
  final double lookFadeStart;

  /// The progress at which the button's look has faded out.
  ///
  /// The look leaves early: it is gone while the menu shape is still
  /// small, and it comes back only once the closing shape is nearly the
  /// button again.
  final double lookFadeEnd;

  /// How much wider the button's look grows per unit of progress, on top
  /// of the button shape's scale; its height follows the shape alone.
  final double lookStretch;

  /// The progress at which the menu content starts to appear.
  ///
  /// The content is in the drop from the start: its opacity follows the
  /// progress, so it is half there when the drop is half grown.
  final double contentFadeStart;

  /// The progress at which the menu content is fully opaque.
  final double contentFadeEnd;

  /// The progress at which the content of a closing menu has faded out.
  ///
  /// The content leaves faster than it came: a close fades it linearly
  /// from the opacity it had to nothing at this progress, so it is gone
  /// while the shape is still more than half grown. A re-open fades it
  /// back in from where it was to full at [contentFadeEnd].
  final double contentCloseFadeEnd;

  /// How much the content swells past the menu shape's scale with the
  /// shape's kick, per unit of kick relative to the menu height.
  ///
  /// The content rides the menu shape: it is scaled with it, plus this
  /// swell, so it unfolds out of the drop instead of being revealed at
  /// its final size.
  final double contentKickScale;

  /// The blur radius of the content, in logical pixels on screen, at
  /// progress 0; it falls linearly to nothing at progress 1.
  final double contentBlur;

  /// The extra blur radius of the content per unit of the menu shape's
  /// kick relative to the menu height.
  final double contentKickBlur;

  /// Seconds between the release of a tap and the start of the opening:
  /// the mean glass open start of 17 device menu captures, each solved on
  /// the open spring from the recorded glass scale (spread 0.069 - 0.140
  /// s, median 0.085).
  final double tapOpenDelay;

  /// Seconds a held finger needs to open the menu without a release. A
  /// finger that slides beyond the source's [reach] before then never
  /// opens it by holding.
  final double holdDuration;

  /// Where a touch on the source's body ([MenuSource.body]) starts and
  /// how far from it a release still counts as a tap: within it a tap
  /// opens the menu (or raises [MenuTapped] when the menu opens only by
  /// holding), beyond it the release cancels and nothing opens.
  final PressReach reach;

  /// Seconds between a release that dismisses and the start of the
  /// closing: the mean glass close start of 13 device outside dismissals
  /// (nine plain menus, four with a submenu), spread 0.046 - 0.074 s,
  /// each replaying the close spring at 0.2 - 0.4 pt RMS.
  final double dismissDelay;

  /// Seconds between the opening and the start of the closing when the
  /// touch that closes the menu was released before the menu appeared.
  ///
  /// Measured on the device for releases from 0 to 100 ms after the tap
  /// that opened the menu: the close starts 16 ms after the opening
  /// whenever the release came, so the menu always reaches about 0.17 of
  /// its progress.
  final double earlyCloseDelay;

  /// Seconds between the release on a row and its action.
  final double actionDelay;

  /// Seconds between a touch and the start of the button's press growth.
  final double pressDelay;

  /// The time constant, in seconds, over which the closing button lets go
  /// of the scale it had when the menu opened.
  final double sourceRelax;

  /// The spring of the menu shape's kick while the menu opens.
  ///
  /// The kick is a second degree of freedom driven by the progress
  /// spring: while opening, it chases [openKickGain] times the velocity
  /// of the opening spring on this spring.
  final Spring openKickSpring;

  /// The gain of the opening kick, in pixels per unit of progress
  /// velocity, for a menu 146 pixels tall; other heights scale it by an
  /// amplitude interpolated over measured menu heights.
  final double openKickGain;

  /// The spring the menu shape's closing kick rings on.
  final Spring closeKickSpring;

  /// The velocity, in pixels per second, a close strikes the menu
  /// shape's kick with, for a menu 146 pixels tall; other heights scale
  /// it by their measured closing amplitude.
  ///
  /// The close kicks the menu shape away from the button, the same way
  /// the opening does; the kick it still carries from the opening rings
  /// out on [closeKickSpring] together with the strike.
  final double closeKickImpulse;

  /// Seconds between the start of a close and its strike on the menu
  /// shape.
  final double closeKickDelay;

  /// The kick, in pixels for a menu 146 pixels tall, past which a close
  /// no longer strikes: the strike shrinks linearly with the kick the
  /// menu shape still carries, so a close during the opening only tops
  /// it up.
  final double closeKickReach;

  /// The spring of the button shape's kick.
  final Spring sourceKickSpring;

  /// The gain of the button shape's kick while the menu closes, in
  /// pixels per unit of progress velocity, for a menu 146 pixels tall
  /// (other heights scale it by their measured amplitude);
  /// the closing progress runs backward, so the button shape is kicked
  /// toward the button's side. The button shape has no kick while the
  /// menu opens.
  final double sourceKickGain;

  /// The smallest gap a centered menu keeps from the safe area's sides;
  /// a menu that would come closer aligns with the button's edge instead.
  final double edgeMargin;

  /// The diameter of the glow under a finger on the menu: the open
  /// menu's `_UIFlexInteraction.LittleGlow` layer is a 160 pt disc drawn
  /// through a vibrant color matrix (iPhone 16 Pro,
  /// test/fixtures/ios27-device/menuglow). Its peak is [flex]'s little
  /// glow opacity (0.5, the device rows peak at 0.49 - 0.5); the menu has
  /// no wash ([flex]'s big glow opacity is 0). It follows the tab bar's
  /// law ([TouchGlowMotion]): a finger dragged 50 pt doubles it at
  /// half the strength, which is how a finger sliding over the rows
  /// lights the whole menu faintly.
  final double glowDiameter;

  /// Seconds after a touch before the glow rises: fitted to eight device
  /// captures (0.011 rms on a drag over the rows, 0.025 at worst).
  final double glowRiseLag;

  /// Seconds the glow rises at least before a lift lets it fall: a tap
  /// on a row lets the rise finish (the fall starts 115 - 170 ms after the
  /// touch, 40 - 87 ms after an 83 ms lift, on seven device captures),
  /// where a long hold falls 26 ms after its lift. 0.1 is the rise
  /// spring's response; the captures' spread around it is not modelled.
  final double glowMinimumLit;

  /// The flex of the open menu under a finger: UIKit's flex interaction
  /// spec for menus, [FlexSpec.menu], applied by [flexTargets] and
  /// [chaseFlexChannel]. Read from UIKit, notes private; the input-only
  /// replays of test/menu/drag_out_test.dart land at 0.09 - 0.15 pt rms
  /// while the finger is down and 0.15 - 0.17 after the lifts.
  final FlexSpec flex;

  /// The points a finger moving inside the open menu adds to the stretch
  /// per menu size it travels: inside, the menu moves `40 / 6000` of the
  /// finger's travel along an axis, beyond its edge `W / 6000` (or
  /// `H / 6000`) per point further out ([flexTargets]).
  ///
  /// Read from UIKit, notes private; the replay of
  /// `ios27-device/menu/drag-out-flex.jsonl` checks it with no fitted
  /// constant (test/menu/drag_out_test.dart).
  final double flexInBoundsPoints;

  /// The spring of the flex's pulse channel: it chases the finger's
  /// vertical travel, and its velocity, in points per second of the
  /// channel's own clock, sizes the pulse ([flexTargets]).
  ///
  /// Read from UIKit (response 0.574, damping 0.548, a tracking spring),
  /// notes private. How the channel steps it is [flexPulseRate] and
  /// [flexPulseRetargetStep].
  final Spring flexPulseSpring;

  /// How many times a second the pulse channel steps [flexPulseSpring]
  /// while a finger is on the open menu.
  ///
  /// Observed live on iOS 27.0.1 (iPhone 16 Pro at 120 Hz, the probe's
  /// animation tap, `ios27-device/menu/drag-out-animation-tap.jsonl`): the
  /// channel publishes every fourth frame. APPROXIMATION: the rule UIKit
  /// uses to schedule the channel from touches alone is not frozen; this
  /// fixed rate, counted from the touch-down, is the observed one at the
  /// device's refresh rate and is not known for other rates or Reduce
  /// Motion.
  final double flexPulseRate;

  /// The spring time, in seconds, one channel step advances
  /// [flexPulseSpring] by when the finger moved since the previous step;
  /// a step with the finger held advances it by the time that passed.
  ///
  /// Observed live on iOS 27.0.1 with [flexPulseRate]: a retarget advances
  /// the spring by one 1/60 s step although 1/30 s passed, so while the
  /// finger moves the spring's clock runs at half the wall time and its
  /// velocity, which the pulse reads, runs twice the rate its value
  /// changes at. One step reproduces UIKit's recorded value and velocity
  /// to 0.01 pt and 0.1 pt/s on 104 of 105 retargets and all 61 held
  /// steps of the tap capture (menu-button.md). APPROXIMATION like
  /// [flexPulseRate].
  final double flexPulseRetargetStep;

  /// Seconds from a touch's time stamp to the open menu's flex answering
  /// it: UIKit delivers the touch to its gesture after about 15 ms and
  /// shows the result on the next 120 Hz frame.
  ///
  /// Measured in `ios27-device/menu/drag-out-flex.jsonl` and
  /// `drag-out-animation-tap.jsonl` (touch stamp to the flex's
  /// translation: 14.4 and 15.9 ms median; the list's frame follows one
  /// frame later).
  final double flexDelay;

  /// The stretch UIKit's open menu takes under a finger, as the scale of
  /// its width and height and the drift of its center across and of its
  /// edge facing the button along the vertical.
  ///
  /// [translation] is the finger's travel from its touch-down,
  /// [inBounds] the travel of the finger clamped into the menu's bounds,
  /// [size] the menu's size W x H at rest, [velocity] the pulse channel's
  /// velocity ([flexPulseSpring]) and [side] +1 for a menu below its
  /// button, -1 above it. Along x (y likewise with H):
  ///
  /// ```text
  /// kx = (|t.x| - |it.x| + 40 |it.x| / W) / 6000   (0 when t.x is 0)
  /// sx = 1 + kx - ky, sy = 1 - kx + ky
  /// dx = sign(t.x) kx W, dy = sign(t.y) ky H
  /// p = velocity side / 8000
  /// sx *= 1 - 50 p / W, sy *= 1 + 32 p / H, dy += side 0.7 32 p
  /// sx, sy clamped to [0.9, 1.1]
  /// ```
  ///
  /// Read from UIKit, notes private. Applied to UIKit's own recorded
  /// inputs it reproduces the recorded menu frames to 0.25 pt rms over
  /// the edges (`lab/menu_flex_model.py`).
  ({double scaleX, double scaleY, double driftX, double driftY}) flexTargets({
    required Offset translation,
    required Offset inBounds,
    required Size size,
    required double velocity,
    required double side,
  }) => FlexInteraction.menuTargets(
    spec: flex,
    inBoundsPoints: flexInBoundsPoints,
    translation: translation,
    inBounds: inBounds,
    size: size,
    velocity: velocity,
    side: side,
  );

  /// The largest fusion radius: the standard deviation, in pixels, of
  /// the Gaussian that blurs the distance field of the two shapes.
  ///
  /// Read from the morph container's `gaussianRadius` on the device
  /// (iOS 27.0.1, iPhone 16 Pro): the container is one SDF layer with
  /// smoothness 0, so the shapes are joined only by this blur, which
  /// rises to 20 at every open and close and falls back to 0. A blur of
  /// this standard deviation reproduces the filmed silhouettes, neck
  /// included, of a ten-row menu closing into a bottom button (fit 0.9
  /// to 1.2 times the logged radius; 1.1 pt rms in row width).
  final double fusionRadius;

  /// The amplitude of the closing fusion envelope, in pixels; the
  /// envelope peaks at 19.7 because its fall starts before its rise
  /// ends. Fitted to the logged `gaussianRadius` of two closes (0.13 pt
  /// rms).
  final double fusionCloseAmplitude;

  /// The time constant, in seconds, of the fusion's rise when the menu
  /// opens. Fitted to two logged opens (0.4 pt rms, the fit's spread
  /// 0.016 to 0.017).
  final double fusionOpenRise;

  /// The time constant, in seconds, of the fusion's rise when the menu
  /// closes. Fitted to two logged closes.
  final double fusionCloseRise;

  /// Seconds after an open at which the fusion starts to fall.
  final double fusionOpenHold;

  /// Seconds after a close at which the fusion starts to fall.
  final double fusionCloseHold;

  /// The spring the fusion falls on, critically damped: fitted free to
  /// 0.424 to 0.433 s in both directions from the device's logged
  /// Gaussian radius. This envelope fit is independent of
  /// [MenuMorphSpec.atSpeed]; that method scales the progress springs.
  final Spring fusionSpring;

  /// The fusion radius under which the container drops its blur: the
  /// device's logged radius jumps from 0.18 to 0.
  final double fusionCutoff;

  /// The fusion envelope [t] seconds after an open, or a close when
  /// [opening] is false, before it is limited to [fusionRadius].
  ///
  /// It rises as `1 - exp(-t / rise)` and, after the hold, falls as a
  /// critically damped spring released from rest.
  double fusionEnvelope(double t, {required bool opening}) {
    if (t <= 0) return 0;
    final rise = opening ? fusionOpenRise : fusionCloseRise;
    final hold = opening ? fusionOpenHold : fusionCloseHold;
    final amplitude = opening ? fusionRadius : fusionCloseAmplitude;
    final fall = math.max<double>(t - hold, 0);
    final w = 2 * math.pi / fusionSpring.response;
    return amplitude *
        (1 - math.exp(-t / rise)) *
        (1 + w * fall) *
        math.exp(-w * fall);
  }

  /// Whether the fusion envelope started [t] seconds ago has fallen
  /// under [fusionCutoff] for good.
  bool fusionEnded(double t, {required bool opening}) =>
      t > (opening ? fusionOpenHold : fusionCloseHold) &&
      fusionEnvelope(t, opening: opening) < fusionCutoff;

  /// The glow a finger raises on the open menu ([glowDiameter]).
  TouchGlowMotion touchGlow() => TouchGlowMotion(
    flex: flex,
    diameter: glowDiameter,
    riseLag: glowRiseLag,
    minimumLit: glowMinimumLit,
  );

  /// The measured iOS 27 menu.
  static const standard = MenuTuning();

  /// The measured iOS 27 context menu: the menu of [standard] on the
  /// morph of [MenuMorphSpec.context], dimming the page by
  /// [MenuDim.context].
  static const context = MenuTuning(
    morph: MenuMorphSpec.context,
    dim: MenuDim.context,
  );
}
