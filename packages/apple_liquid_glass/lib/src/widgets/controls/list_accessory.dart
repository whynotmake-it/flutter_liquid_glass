import 'package:apple_liquid_glass/src/widgets/controls/list.dart';

/// The standard accessory of a [GlassListRow].
///
/// UIKit: `UITableViewCell.AccessoryType`. SwiftUI: a `NavigationLink`'s
/// chevron. Flutter: `CupertinoListTile.trailing` with
/// `CupertinoListTileChevron`.
///
/// The checkmark and the info button are drawn in the row's icon color.
/// UIKit draws the SF symbol `checkmark` at 17 point semibold, medium
/// scale, and the info button as `info.circle` (read from UIKit, notes
/// private); these are painted by eye in a 22 point box, not read.
enum GlassListAccessory {
  /// The disclosure chevron of a row that pushes a screen.
  disclosureIndicator,

  /// A checkmark: the row is the chosen one of a list of options.
  checkmark,

  /// An info button; a tap on it calls [GlassListRow.onAccessoryPressed]
  /// instead of the row's [GlassListRow.onPressed].
  detailButton,

  /// An info button followed by the disclosure chevron.
  detailDisclosureButton,
}
