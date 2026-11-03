import 'dart:math' as math;

import 'analysis/track_analysis.dart';
import 'next_track.dart';
import 'transition.dart';

/// Beat Sense as a DJ: instead of playing each song to its end, it plays
/// the best part, then either blends into the next song so the blend
/// finishes on its drop, or cuts on a phrase downbeat straight into the
/// drop. Songs are chosen to keep tempo, key and energy flowing.
class DjPlanner {
  const DjPlanner({
    this.planner = const TransitionPlanner(),
    this.minPlay = 60,
    this.maxPlay = 150,
  });

  final TransitionPlanner planner;

  /// Seconds of each song the set plays, at least and at most.
  final double minPlay;
  final double maxPlay;

  /// Where the song "drops": the first phrase after the intro where the
  /// energy jumps to its high level. Falls back to the end of the intro.
  static double dropOf(TrackAnalysis a) {
    final e = a.barEnergy, bars = a.downbeats;
    if (e.length < 12 || bars.length != e.length) return a.introEnd;
    double mean(int from, int to) {
      final f = from.clamp(0, e.length), t = to.clamp(0, e.length);
      if (t <= f) return 0;
      return e.sublist(f, t).reduce((x, y) => x + y) / (t - f);
    }

    final starts = [
      for (final p in a.phrases)
        if (p >= a.introEnd - 0.05 || p >= bars[math.min(8, bars.length - 1)])
          bars.indexWhere((d) => (d - p).abs() < 0.05),
    ].where((i) => i > 0).toList();
    // A jump into a loud section.
    for (final i in starts) {
      if (mean(i, i + 4) >= 0.72 && mean(i, i + 4) - mean(i - 4, i) >= 0.12) {
        return bars[i];
      }
    }
    for (final i in starts) {
      if (mean(i, i + 4) >= 0.8) return bars[i];
    }
    return a.introEnd;
  }

  /// The transition from [from] (playing since [playedFrom] seconds into
  /// it) to [to]. [setIndex] counts transitions so far, for variety.
  DjMove plan(
    TrackAnalysis from,
    TrackAnalysis to, {
    double playedFrom = 0,
    int setIndex = 0,
    int fromSemitones = 0,
  }) {
    final base = planner.plan(from, to, fromSemitones: fromSemitones);
    final exit = _exit(from, playedFrom, base);
    final drop = dropOf(to);

    if (base.style == TransitionStyle.crossfade) {
      return DjMove(base.copyWith(exitAt: exit), 'no steady beat, so a fade');
    }

    // Keys as they'll actually sound, after any shift.
    final keyStep = from.key
        .transpose(fromSemitones)
        .camelotDistance(to.key.transpose(base.incomingSemitones));
    final keysTrusted = math.min(from.keyConfidence, to.keyConfidence) > 0.15;
    final energyJump = to.energy - from.energy;
    final matchable = base.beatMatched;

    final String why;
    final bool cut;
    if (!matchable) {
      cut = true;
      why = 'tempos too far apart to blend, so a cut on the beat';
    } else if (keysTrusted && keyStep > 2) {
      cut = true;
      why = 'keys clash, so a clean cut instead of a blend';
    } else if (energyJump > 0.15) {
      cut = true;
      why = 'energy goes up, so it cuts straight into the drop';
    } else if (setIndex % 3 == 2) {
      cut = true;
      why = 'a cut for variety';
    } else {
      cut = false;
      why = base.incomingSemitones != 0
          ? 'shifted ${base.incomingSemitones > 0 ? 'up' : 'down'} a semitone '
                'so the keys match, then blended into the drop'
          : base.style == TransitionStyle.blend
          ? 'keys and energy match, so a long blend into the drop'
          : 'beats locked, bass handed over on a downbeat';
    }

    if (cut) return DjMove(_cut(from, to, exit, drop, base), why);
    return DjMove(_blend(to, exit, drop, base), why);
  }

  /// Leave on a phrase start after the song has played a good stretch,
  /// never later than the planner's natural exit before the outro.
  double _exit(TrackAnalysis a, double playedFrom, TransitionPlan base) {
    final remaining = a.duration - playedFrom;
    final target =
        playedFrom + (remaining * 0.55).clamp(minPlay, maxPlay).toDouble();
    final earliest = playedFrom + math.min(minPlay, remaining * 0.5);
    final latest = base.exitAt;
    for (final marks in [a.phrases, a.downbeats]) {
      final fits = marks.where((p) => p >= earliest && p <= latest).toList();
      if (fits.isEmpty) continue;
      fits.sort((x, y) => (x - target).abs().compareTo((y - target).abs()));
      return fits.first;
    }
    return latest;
  }

  /// Beat-matched blend timed so it ends exactly on the incoming drop.
  TransitionPlan _blend(
    TrackAnalysis to,
    double exit,
    double drop,
    TransitionPlan base,
  ) {
    final span = base.length * base.incomingRate;
    final ideal = drop - span;
    final first = to.downbeats.first;
    var entry = first;
    if (ideal > first) {
      entry = to.downbeats.lastWhere(
        (d) => d <= ideal + 0.05,
        orElse: () => first,
      );
    }
    return TransitionPlan(
      style: base.style,
      exitAt: exit,
      entryAt: entry,
      length: base.length,
      incomingRate: base.incomingRate,
      rampBack: base.rampBack,
      incomingGainDb: base.incomingGainDb,
      outgoingGainDb: base.outgoingGainDb,
      incomingSemitones: base.incomingSemitones,
    );
  }

  /// The outgoing song plays to the phrase downbeat; on that beat the
  /// incoming song's drop hits. The incoming deck rolls silently for two
  /// beats first so it is exactly in time when it is heard.
  TransitionPlan _cut(
    TrackAnalysis from,
    TrackAnalysis to,
    double exit,
    double drop,
    TransitionPlan base,
  ) {
    final rate = base.beatMatched ? base.incomingRate : 1.0;
    final preRoll = 2 * from.beatLength;
    final start = math.max(0.0, exit - preRoll);
    final length = exit - start;
    final entry = math.max(0.0, drop - length * rate);
    return TransitionPlan(
      style: TransitionStyle.dropCut,
      exitAt: start,
      entryAt: entry,
      length: math.max(0.05, length),
      incomingRate: rate,
      rampBack: base.beatMatched ? 8 * 4 * from.beatLength : 0,
      incomingGainDb: base.incomingGainDb,
      outgoingGainDb: base.outgoingGainDb,
      incomingSemitones: base.incomingSemitones,
    );
  }

  /// Picks the best next song for the set from analysed [candidates]:
  /// close tempo, compatible key, energy building early in the set and
  /// then holding, and no artist twice in a row.
  ScoredCandidate<T>? pick<T>(
    TrackAnalysis current,
    String currentArtist,
    List<Candidate<T>> candidates, {
    int setIndex = 0,
    Set<String> recentArtists = const {},
  }) {
    if (candidates.isEmpty) return null;
    final scorer = NextTrackScorer(
      flow: setIndex < 4 ? EnergyFlow.build : EnergyFlow.steady,
    );
    return scorer
        .rank(current, currentArtist, candidates, recentArtists: recentArtists)
        .first;
  }

  /// A short reason a song was picked, from its score parts.
  static String whyPicked(TrackAnalysis from, TrackAnalysis to) {
    final parts = <String>[];
    final bpm = to.bpm - from.bpm;
    final rate = TransitionPlanner.matchRate(from.bpm, to.bpm);
    if ((rate - 1).abs() < 0.02) {
      parts.add('same tempo');
    } else {
      parts.add('${bpm > 0 ? '+' : ''}${bpm.round()} BPM');
    }
    final step = from.key.camelotDistance(to.key);
    parts.add(switch (step) {
      0 => 'same key',
      1 => 'key next door',
      _ => 'key change',
    });
    final e = to.energy - from.energy;
    parts.add(
      e > 0.06 ? 'energy up' : (e < -0.06 ? 'energy down' : 'energy holds'),
    );
    return parts.join(' · ');
  }
}

/// One DJ decision: how to transition, and why.
class DjMove {
  const DjMove(this.plan, this.why);

  final TransitionPlan plan;
  final String why;
}
