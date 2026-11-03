import 'dart:math' as math;

import 'transition.dart';

/// The DJ moves for one transition on the native engine: how each deck's
/// volume, 3-band EQ and filter change over the blend. Lanes are lists of
/// (time, value) pairs flattened as `[t0, v0, t1, v1, …]`, times in
/// seconds of the outgoing song.
///
/// Volumes are 0–1, EQ bands are dB (0 untouched, [kill] removes the band)
/// and the filter is the DJ knob (0 off, + thins out, − muffles).
abstract final class MixScript {
  static const kill = -45.0;

  static Map<String, List<double>> lanes(TransitionPlan p) {
    double at(double x) => p.exitAt + x * p.length;
    List<double> lane(List<(double, double)> points) => [
      for (final (x, v) in points) ...[at(x), v],
    ];
    // A swap is quick but not instantaneous, so it never clicks.
    const edge = 0.012;

    switch (p.style) {
      case TransitionStyle.blend:
        // Long, smooth: the new song arrives under the old one with only
        // its mids, the bass changes hands halfway, then the old song
        // thins out and fades.
        return {
          'inGain': lane([(0, 0), (0.25, 0.75), (0.5, 1)]),
          'inLow': lane([(0, kill), (0.5 - edge, kill), (0.5, 0)]),
          'inHigh': lane([(0, -12), (0.5, 0)]),
          'outGain': lane([(0, 1), (0.5, 1), (0.8, 0.7), (1, 0)]),
          'outLow': lane([(0, 0), (0.5 - edge, 0), (0.5, kill)]),
          'outHigh': lane([(0, 0), (0.5, 0), (0.9, -12)]),
          'outFilter': lane([(0, 0), (0.6, 0), (1, 0.45)]),
        };
      case TransitionStyle.bassSwap:
        // Quicker hand-over when the energy differs: same moves, sooner.
        return {
          'inGain': lane([(0, 0), (0.375, 1)]),
          'inLow': lane([(0, kill), (0.5 - edge, kill), (0.5, 0)]),
          'inHigh': lane([(0, -12), (0.375, 0)]),
          'outGain': lane([(0, 1), (0.5, 1), (0.875, 0)]),
          'outLow': lane([(0, 0), (0.5 - edge, 0), (0.5, kill)]),
          'outHigh': lane([(0, 0), (0.25, 0), (0.75, -15)]),
          'outFilter': lane([(0, 0), (0.5, 0), (0.875, 0.5)]),
        };
      case TransitionStyle.dropCut:
      case TransitionStyle.cutOnBeat:
        // Silent until the downbeat at the end, then the new song's drop.
        const swap = 0.85;
        return {
          'inGain': lane([(0, 0), (swap, 0), (1, 1)]),
          'inLow': lane([(0, kill), (1 - edge, kill), (1, 0)]),
          'outGain': lane([(0, 1), (swap, 1), (1, 0)]),
          'outLow': lane([(0, 0), (swap, 0), (swap + edge, kill)]),
        };
      case TransitionStyle.crossfade:
        // No beat to lock to: an equal-power fade.
        final xs = [for (var i = 0; i <= 8; i++) i / 8];
        return {
          'inGain': lane([for (final x in xs) (x, math.sin(x * math.pi / 2))]),
          'outGain': lane([for (final x in xs) (x, math.cos(x * math.pi / 2))]),
        };
    }
  }

  /// Everything the engine needs for one transition.
  static Map<String, Object> toEngine(TransitionPlan p) => {
    'exit': p.exitAt,
    'entry': p.entryAt,
    'length': p.length,
    'rate': p.incomingRate,
    'semitones': p.incomingSemitones.toDouble(),
    'rampBack': p.rampBack,
    'lanes': lanes(p),
  };
}
