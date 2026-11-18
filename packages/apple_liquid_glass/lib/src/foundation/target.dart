import 'dart:ui';

import 'package:kinesis/input.dart';

/// The side, in points, of the smallest area that takes a finger: Apple's
/// Human Interface Guidelines ask for a target of at least 44 by 44 points
/// for every control, whatever the size of its look.
const double glassMinimumTargetExtent = 44;

/// The smallest area that takes a finger, [glassMinimumTargetExtent] square.
const Size glassMinimumTarget = Size.square(glassMinimumTargetExtent);

/// Where a control takes a finger: its box grown to [glassMinimumTarget].
/// A press on it holds the finger in that area alone.
const PressReach glassTargetReach = PressReach(minimumHit: glassMinimumTarget);

/// Where a glass button, a segment and a menu's source take a finger, as
/// [glassTargetReach], and how far beyond their body a finger still counts
/// as inside: 70 points.
///
/// Measured on an iPhone 16 Pro: a 120 x 44 glass button activates on a
/// release 70 pt above or 60 pt beside it (2026-10-13; below and left not
/// measured, glass-button passport), and UISegmentedControl selects on a
/// release 60 points below its bottom edge but not 70 (iOS 27.0.1). The
/// slop grows the body, not the 44 point target: a segment's 70 below its
/// edge is out.
const PressReach glassButtonReach = PressReach(
  minimumHit: glassMinimumTarget,
  slop: 70,
);
