import 'package:kinesis/motion.dart';

/// The tuning of UIKit's morph between a control and the surface it opens,
/// such as a button turning into its menu.
///
/// The defaults are the `liquidMorph` tuning read live from iOS 27, the
/// set a glass button's menu uses: the opening ([eject]) and closing
/// ([absorb]) of the main shape on their own springs. UIKit divides time
/// by [speed], so the effective response of every spring is its response
/// times [speed]. The rest of `liquidMorph` drives nothing here: position,
/// size, transform and content on 0.3 / 0.8, kick 0.35 / 0.8, settle
/// 0.5 / 0.8, blur in 0.3 / 1 and out 0.45 / 0.8 at scales 1.2 - 1.65, a
/// second step 0.03 s late, intermediate shape ratios 0.25 growing and 0.9
/// shrinking, genie scale 0.4.
///
/// [context] is the morph of a context menu, which grows out of a blob at
/// the held view's center beside the lifted preview instead of out of a
/// button.
class MenuMorphSpec {
  /// Creates a morph spec from explicit values.
  const MenuMorphSpec({
    this.eject = const Spring.response(0.5, dampingRatio: 0.75),
    this.absorb = const Spring.response(0.7, dampingRatio: 0.8),
    this.speed = 0.7,
    this.kicks = true,
    this.fuses = true,
  });

  /// The spring of the main shape while it opens.
  final Spring eject;

  /// The spring of the main shape while it closes.
  final Spring absorb;

  /// The speed multiplier UIKit applies to the morph.
  final double speed;

  /// Whether the menu and source shapes ring with their measured kicks:
  /// the menu shape's open kick and close strike and the source shape's
  /// kick. A context menu has no source shape and its menu follows the
  /// plain spring (0.6 percent rms of travel on the device morph).
  final bool kicks;

  /// Whether the menu and source shapes fuse into one silhouette while
  /// they part and meet. The context menu draws its preview on glass of
  /// its own, which the menu never fuses with (read from UIKit, notes
  /// private).
  final bool fuses;

  /// [spring] as it runs at [speed]: its response times [speed], its
  /// damping ratio unchanged.
  Spring atSpeed(Spring spring) => Spring.response(
    spring.response * speed,
    dampingRatio: spring.dampingRatio,
  );

  /// UIKit's `liquidMorph` tuning.
  static const standard = MenuMorphSpec();

  /// The morph of UIKit's context menu, measured on an iPhone 16 Pro (iOS
  /// 27, `ios27-device/context_menu/morph.json`): the menu grows out of
  /// its blob and retracts into it on one spring both ways, response
  /// 0.284 s and damping ratio 0.81, the spring the preview resizes on
  /// (0.4 - 0.6 percent rms of travel), without kicks and without fusing
  /// with the preview.
  static const context = MenuMorphSpec(
    eject: Spring.response(0.284, dampingRatio: 0.81),
    absorb: Spring.response(0.284, dampingRatio: 0.81),
    speed: 1,
    kicks: false,
    fuses: false,
  );
}
