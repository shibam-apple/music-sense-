import 'dart:math' as math;

import 'analysis/track_analysis.dart';

/// How two songs are blended.
enum TransitionStyle {
  /// Beat-matched; the bass is handed from one song to the other on a
  /// downbeat halfway through so the two kick drums never clash.
  bassSwap,

  /// Beat-matched equal-power blend, for songs whose bass lines sit well
  /// together (same or neighbouring key, similar energy).
  blend,

  /// Tempos too far apart to match: the outgoing song fades over one bar
  /// and the incoming song lands on the next downbeat.
  cutOnBeat,

  /// No reliable beat in one of the songs (ambient, classical, speech):
  /// a plain timed crossfade.
  crossfade,

  /// The DJ's cut: the outgoing song plays to a phrase downbeat and the
  /// incoming song's drop hits on that beat. The incoming deck rolls
  /// silently (tempo-matched) beforehand so the cut is in time.
  dropCut,
}

enum MixLength { short, medium, long }

/// What Beat Sense will do at the end of one song.
class TransitionPlan {
  const TransitionPlan({
    required this.style,
    required this.exitAt,
    required this.entryAt,
    required this.length,
    required this.incomingRate,
    required this.rampBack,
    required this.incomingGainDb,
    required this.outgoingGainDb,
  });

  final TransitionStyle style;

  /// Position in the outgoing song (seconds) where the incoming song
  /// starts. A downbeat (usually a phrase start) for beat-matched styles.
  final double exitAt;

  /// Position in the incoming song (seconds) to start playing from.
  final double entryAt;

  /// Length of the blend in seconds of the outgoing song's time.
  final double length;

  /// Playback rate for the incoming song during the blend, so its beats
  /// line up with the outgoing song. 1.0 for unmatched styles.
  final double incomingRate;

  /// Seconds after the blend over which the incoming rate eases to 1.0.
  final double rampBack;

  /// Gains that bring both songs to the same loudness.
  final double incomingGainDb;
  final double outgoingGainDb;

  double get endsAt => exitAt + length;

  TransitionPlan copyWith({double? exitAt, double? length}) => TransitionPlan(
    style: style,
    exitAt: exitAt ?? this.exitAt,
    entryAt: entryAt,
    length: length ?? this.length,
    incomingRate: incomingRate,
    rampBack: rampBack,
    incomingGainDb: incomingGainDb,
    outgoingGainDb: outgoingGainDb,
  );

  bool get beatMatched =>
      style == TransitionStyle.bassSwap ||
      style == TransitionStyle.blend ||
      style == TransitionStyle.dropCut;

  /// Volumes (0–1) and bass gains (dB, 0 = untouched) at [progress] 0–1
  /// through the blend. Volumes are equal-power so the sum stays level.
  MixLevels levelsAt(double progress) {
    final x = progress.clamp(0.0, 1.0);
    switch (style) {
      case TransitionStyle.bassSwap:
        // Incoming bass held back until the swap at the halfway downbeat.
        final swapped = x >= 0.5;
        return MixLevels(
          outgoing: math.cos(x * math.pi / 2),
          incoming: math.sin(x * math.pi / 2),
          outgoingBassDb: swapped ? MixLevels.bassCut : 0,
          incomingBassDb: swapped ? 0 : MixLevels.bassCut,
        );
      case TransitionStyle.blend:
      case TransitionStyle.crossfade:
        return MixLevels(
          outgoing: math.cos(x * math.pi / 2),
          incoming: math.sin(x * math.pi / 2),
        );
      case TransitionStyle.dropCut:
        // Silent pre-roll, then a hard swap on the downbeat with a few
        // milliseconds of overlap (bass held back) so it doesn't click.
        if (x < 0.85) return const MixLevels(outgoing: 1, incoming: 0);
        if (x >= 1) return const MixLevels(outgoing: 0, incoming: 1);
        final t = (x - 0.85) / 0.15;
        return MixLevels(
          outgoing: math.cos(t * math.pi / 2),
          incoming: math.sin(t * math.pi / 2),
          outgoingBassDb: MixLevels.bassCut,
          incomingBassDb: MixLevels.bassCut,
        );
      case TransitionStyle.cutOnBeat:
        // Outgoing fades across the bar; incoming enters at the end of it.
        return MixLevels(
          outgoing: math.cos(x * math.pi / 2),
          incoming: x >= 1 ? 1 : 0,
        );
    }
  }

  @override
  String toString() =>
      'TransitionPlan(${style.name}, exit ${exitAt.toStringAsFixed(2)}s, '
      'entry ${entryAt.toStringAsFixed(2)}s, ${length.toStringAsFixed(2)}s, '
      'rate ${incomingRate.toStringAsFixed(3)})';
}

class MixLevels {
  const MixLevels({
    required this.outgoing,
    required this.incoming,
    this.outgoingBassDb = 0,
    this.incomingBassDb = 0,
  });

  static const bassCut = -15.0;

  final double outgoing, incoming, outgoingBassDb, incomingBassDb;
}

/// Plans the transition from one analysed song to the next.
class TransitionPlanner {
  const TransitionPlanner({
    this.length = MixLength.medium,
    this.maxRateChange = 0.08,
    this.targetLoudnessDb = -14,
  });

  final MixLength length;

  /// Largest tempo change applied to the incoming song (±8% by default;
  /// beyond that pitch-preserved stretching starts to sound wrong).
  final double maxRateChange;
  final double targetLoudnessDb;

  static const minBeatConfidence = 0.35;

  TransitionPlan plan(TrackAnalysis from, TrackAnalysis to) {
    final gains = (out: gainFor(from), inc: gainFor(to));

    if (from.beatConfidence < minBeatConfidence ||
        to.beatConfidence < minBeatConfidence ||
        from.downbeats.isEmpty ||
        to.downbeats.isEmpty) {
      return _crossfade(from, to, gains.out, gains.inc);
    }

    final rate = matchRate(from.bpm, to.bpm);
    if ((rate - 1).abs() > maxRateChange) {
      return _cut(from, to, gains.out, gains.inc);
    }

    final beats = _beats(from, to);
    final blendLength = beats * from.beatLength;
    final exit = _exitPoint(from, blendLength);
    final entry = _entryPoint(to, beats * to.beatLength);
    final keyClose =
        from.key.camelotDistance(to.key) <= 1 &&
        math.min(from.keyConfidence, to.keyConfidence) > 0.15;
    final style = keyClose && (from.energy - to.energy).abs() < 0.2
        ? TransitionStyle.blend
        : TransitionStyle.bassSwap;

    return TransitionPlan(
      style: style,
      exitAt: exit,
      entryAt: entry,
      length: blendLength,
      incomingRate: rate,
      rampBack: 8 * 4 * from.beatLength,
      incomingGainDb: gains.inc,
      outgoingGainDb: gains.out,
    );
  }

  /// Rate that brings [to] onto [from]'s tempo, treating half and double
  /// time as the same tempo (87 and 174 BPM mix as equals).
  static double matchRate(double from, double to) {
    var best = from / to;
    for (final k in [0.5, 2.0]) {
      final r = from / (to * k);
      if ((r - 1).abs() < (best - 1).abs()) best = r;
    }
    return best;
  }

  /// Moves [plan] to start on the first downbeat at or after [after]
  /// seconds into [from], as a DJ does when mixing early. With [beats] the
  /// blend is shortened to that many beats (a quick mix for Next); it is
  /// also shortened if the song would end before the blend does.
  TransitionPlan retime(
    TransitionPlan plan,
    TrackAnalysis from,
    double after, {
    int? beats,
  }) {
    if (plan.style == TransitionStyle.dropCut) {
      // The cut itself must land on a downbeat; the pre-roll precedes it.
      final cut = from.downbeats.firstWhere(
        (d) => d >= after + plan.length,
        orElse: () => after + plan.length,
      );
      return plan.copyWith(exitAt: cut - plan.length);
    }
    final exit = from.downbeats.firstWhere(
      (d) => d >= after,
      orElse: () => after,
    );
    var length = beats == null || !plan.beatMatched
        ? plan.length
        : math.min(plan.length, beats * from.beatLength);
    final room = from.duration - exit - 0.5;
    if (length > room) {
      // Whole bars that still fit, at least one beat.
      final bar = 4 * from.beatLength;
      length = room >= bar
          ? (room / bar).floor() * bar
          : math.max(from.beatLength, room);
    }
    return plan.copyWith(exitAt: exit, length: math.max(0.5, length));
  }

  int _beats(TrackAnalysis from, TrackAnalysis to) {
    // DJ-length blends: 8 bars by default (about 16 s at 120 BPM).
    var beats = switch (length) {
      MixLength.short => 16,
      MixLength.medium => 32,
      MixLength.long => 64,
    };
    // Clashing keys: keep the overlap short.
    if (from.key.camelotDistance(to.key) > 2 && beats > 8) beats ~/= 2;
    return beats;
  }

  /// Start the blend on the phrase where the outgoing song begins to wind
  /// down, leaving room for the whole blend before it ends.
  double _exitPoint(TrackAnalysis a, double blend) {
    final latest = a.duration - blend - 1;
    final target = math.min(a.outroStart, latest);
    for (final candidates in [a.phrases, a.downbeats]) {
      final fits = candidates.where((p) => p <= target + 0.05).toList();
      if (fits.isNotEmpty && fits.last > a.duration * 0.4) return fits.last;
    }
    return math.max(0, latest);
  }

  /// Start the incoming song so its full arrangement arrives as the blend
  /// finishes: a long intro is entered part-way, on a downbeat.
  double _entryPoint(TrackAnalysis b, double blend) {
    final first = b.downbeats.first;
    final ideal = b.introEnd - blend;
    if (ideal <= first) return first;
    // A phrase start if one fits (it's where a DJ would drop in), else a
    // downbeat.
    for (final candidates in [b.phrases, b.downbeats]) {
      final fits = candidates.where((d) => d >= first && d <= ideal + 0.05);
      if (fits.isNotEmpty) return fits.last;
    }
    return first;
  }

  TransitionPlan _cut(
    TrackAnalysis from,
    TrackAnalysis to,
    double outDb,
    double inDb,
  ) {
    final bar = 4 * from.beatLength;
    final exit = _exitPoint(from, bar);
    return TransitionPlan(
      style: TransitionStyle.cutOnBeat,
      exitAt: exit,
      entryAt: to.downbeats.first,
      length: bar,
      incomingRate: 1,
      rampBack: 0,
      incomingGainDb: inDb,
      outgoingGainDb: outDb,
    );
  }

  TransitionPlan _crossfade(
    TrackAnalysis from,
    TrackAnalysis to,
    double outDb,
    double inDb,
  ) {
    final seconds = switch (length) {
      MixLength.short => 4.0,
      MixLength.medium => 7.0,
      MixLength.long => 12.0,
    };
    final fade = math.min(seconds, from.duration / 4);
    final exit = math.max(0.0, math.min(from.outroStart, from.duration - fade));
    final start = to.beats.isEmpty ? 0.0 : math.max(0.0, to.beats.first - 0.05);
    return TransitionPlan(
      style: TransitionStyle.crossfade,
      exitAt: exit,
      entryAt: start,
      length: fade,
      incomingRate: 1,
      rampBack: 0,
      incomingGainDb: inDb,
      outgoingGainDb: outDb,
    );
  }

  /// Gain that brings [a] to the target loudness.
  double gainFor(TrackAnalysis a) =>
      (targetLoudnessDb - a.loudnessDb).clamp(-12.0, 9.0);
}
