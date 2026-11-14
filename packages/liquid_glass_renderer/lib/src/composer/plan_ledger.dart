import 'dart:ui';

import 'package:liquid_glass_renderer/src/composer/geometry.dart';
import 'package:liquid_glass_renderer/src/composer/plan.dart';

/// What is kept between frames for the decisions, with one writer:
/// [compilePlan] returns edits and the composer applies them.
final class PlanLedger {
  /// Per read's lead.
  final Map<Object, ReadMemo> reads = Map.identity();
}

/// What a read's lead remembers.
final class ReadMemo {
  /// The frame its band last changed.
  int changedAt = 0;

  /// Holds that ended before they paid for their image, in a row.
  int misses = 0;

  /// The frame its image was drawn, if it has one.
  int? boughtAt;

  /// Whether the target budget bought its image, before the read held still
  /// long enough to pay for it: losing that image is no miss.
  bool forBudget = false;

  /// Where its backdrop's pixels lay: its image's, if it has one.
  ReadGeometry? geometry;

  /// The frame this memo was last used, to forget leads that left.
  int seenAt = 0;

  /// The leads of the reads it holds.
  List<Object> holds = const [];

  /// Where its band was a frame ago, to see how fast it moves.
  Rect? lastBand;
}

/// Edits to a [PlanLedger] that [compilePlan] asks for.
final class PlanLedgerEdits {
  /// The memos to write, by lead.
  final Map<Object, ReadMemo> writes = Map.identity();

  /// Applies the edits, and forgets leads gone for a while.
  void applyTo(PlanLedger ledger, int frame) {
    ledger.reads.addAll(writes);
    if (ledger.reads.length <= writes.length) return;
    ledger.reads.removeWhere((_, memo) => frame - memo.seenAt > 120);
  }
}
