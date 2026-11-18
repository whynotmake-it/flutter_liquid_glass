import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The accessibility settings iOS and macOS report and Flutter's
/// `AccessibilityFeatures` do not.
@immutable
final class AppleAccessibilityFeatures {
  /// Creates settings; the defaults are all off, with Prefer Cross-Fade
  /// Transitions, the Liquid Glass slider and the system's preference for
  /// reduced resource usage unreported.
  const AppleAccessibilityFeatures({
    this.reduceTransparency = false,
    this.showBorders = false,
    this.prefersCrossFade,
    this.glassTintAmount,
    this.prefersReducedResourceUsage,
  });

  factory AppleAccessibilityFeatures._from(Object? report) {
    final values = report! as Map<Object?, Object?>;
    return AppleAccessibilityFeatures(
      reduceTransparency: values['reduceTransparency'] == true,
      showBorders: values['showBorders'] == true,
      prefersCrossFade: values['prefersCrossFade'] as bool?,
      glassTintAmount: (values['glassTintAmount'] as num?)?.toDouble(),
      prefersReducedResourceUsage:
          values['prefersReducedResourceUsage'] as bool?,
    );
  }

  /// Reduce Transparency.
  ///
  /// UIKit: `UIAccessibility.isReduceTransparencyEnabled`. AppKit:
  /// `NSWorkspace.accessibilityDisplayShouldReduceTransparency`.
  final bool reduceTransparency;

  /// Show Borders, called Button Shapes before iOS 26.1.
  ///
  /// Accessibility: `AccessibilitySettings.showBordersEnabled`, reported
  /// from iOS and macOS 26.1; UIKit's `UIAccessibility.buttonShapesEnabled`
  /// on older iOS.
  final bool showBorders;

  /// Prefer Cross-Fade Transitions, or null where the platform does not
  /// report it (macOS).
  ///
  /// UIKit: `UIAccessibility.prefersCrossFadeTransitions`.
  final bool? prefersCrossFade;

  /// Where the Liquid Glass slider of iOS 27 (Settings, Appearance) stands,
  /// from 0 (Clear) to 1 (Tinted), or null where the platform does not
  /// report it (before iOS 27, macOS).
  ///
  /// UIKit has no public API for it: the plugin reads the getter and the
  /// change notification UIKit exports without declaring
  /// (`UIViewGlassGetTintAmount`,
  /// `UIViewGlassTintAmountDidChangeNotification`), looked up at run time,
  /// so an iOS that drops them reports null instead of failing. Undeclared
  /// API can draw App Store review questions.
  final double? glassTintAmount;

  /// Whether the system prefers that the app scale back resource-intensive
  /// work, or null where the platform does not report it (before iOS 27,
  /// macOS).
  ///
  /// UIKit: `UIApplication.systemPrefersReducedResourceUsage`.
  final bool? prefersReducedResourceUsage;

  static const _channel = EventChannel('apple_liquid_glass_accessibility');

  // One stream for every listener: a second `receiveBroadcastStream` on the
  // channel would take the events of the first.
  static final Stream<AppleAccessibilityFeatures> _reports = _channel
      .receiveBroadcastStream()
      .map((report) => _latest = AppleAccessibilityFeatures._from(report));

  static AppleAccessibilityFeatures? _latest;

  /// The settings now, then each change; nothing on other platforms.
  static Stream<AppleAccessibilityFeatures> watch() async* {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      return;
    }
    final latest = _latest;
    if (latest != null) yield latest;
    yield* _reports;
  }

  @override
  bool operator ==(Object other) =>
      other is AppleAccessibilityFeatures &&
      other.reduceTransparency == reduceTransparency &&
      other.showBorders == showBorders &&
      other.prefersCrossFade == prefersCrossFade &&
      other.glassTintAmount == glassTintAmount &&
      other.prefersReducedResourceUsage == prefersReducedResourceUsage;

  @override
  int get hashCode => Object.hash(
    reduceTransparency,
    showBorders,
    prefersCrossFade,
    glassTintAmount,
    prefersReducedResourceUsage,
  );
}

/// Feeds [AppleAccessibilityFeatures] into the `GlassTraits` of [child]:
/// glass draws flat under Reduce Transparency, outlines its surfaces under
/// Show Borders, follows the Liquid Glass slider of iOS 27, turns to the
/// adaptive renderer's fallback while the system prefers reduced resource
/// usage and, with Reduce Motion, cross-fades pages as Prefer Cross-Fade
/// Transitions says.
///
/// Wrap the app with it, or return it from `WidgetsApp.builder`, so
/// presented content sees the settings too. Until the platform reports,
/// and on other platforms, the enclosing traits stay.
class GlassPlatformTraits extends StatefulWidget {
  /// Feeds the platform's settings into [child]'s traits.
  const GlassPlatformTraits({required this.child, super.key});

  /// The subtree the settings apply to.
  final Widget child;

  @override
  State<GlassPlatformTraits> createState() => _GlassPlatformTraitsState();
}

class _GlassPlatformTraitsState extends State<GlassPlatformTraits> {
  late final StreamSubscription<AppleAccessibilityFeatures> _subscription;
  AppleAccessibilityFeatures? _features;

  @override
  void initState() {
    super.initState();
    _subscription = AppleAccessibilityFeatures.watch().listen(
      (features) => setState(() => _features = features),
    );
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final features = _features;
    return GlassTraitsOverride(
      reduceTransparency: features?.reduceTransparency,
      showBorders: features?.showBorders,
      prefersCrossFade: features?.prefersCrossFade,
      glassTintAmount: features?.glassTintAmount,
      prefersReducedResourceUsage: features?.prefersReducedResourceUsage,
      child: widget.child,
    );
  }
}
