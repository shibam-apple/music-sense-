import 'dart:math' as math;

import 'analysis/track_analysis.dart';
import 'transition.dart';

/// Where the listener wants the energy to go over the next songs.
enum EnergyFlow { steady, build, windDown }

/// A song Beat Sense could play next, with what it knows about it.
class Candidate<T> {
  const Candidate({
    required this.item,
    required this.analysis,
    required this.artist,
    this.affinity = 0.5,
  });

  final T item;
  final TrackAnalysis analysis;
  final String artist;

  /// 0–1 from the listener's history: plays, skips, likes.
  final double affinity;
}

class ScoredCandidate<T> {
  const ScoredCandidate(this.candidate, this.score, this.parts);

  final Candidate<T> candidate;
  final double score;

  /// Each component's 0–1 score, for tuning and for "why this song".
  final Map<String, double> parts;
}

/// Ranks candidates to follow the current song so the mix sounds
/// intentional: close tempo, compatible key, a sensible energy step, and
/// songs the listener likes, without repeating artists back to back.
class NextTrackScorer {
  const NextTrackScorer({
    this.flow = EnergyFlow.steady,
    this.weights = const {
      'tempo': 0.32,
      'key': 0.24,
      'energy': 0.2,
      'affinity': 0.24,
    },
  });

  final EnergyFlow flow;
  final Map<String, double> weights;

  List<ScoredCandidate<T>> rank<T>(
    TrackAnalysis current,
    String currentArtist,
    Iterable<Candidate<T>> candidates, {
    Set<String> recentArtists = const {},
  }) {
    final scored = [
      for (final c in candidates)
        _score(current, currentArtist, c, recentArtists),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  ScoredCandidate<T> _score<T>(
    TrackAnalysis current,
    String currentArtist,
    Candidate<T> c,
    Set<String> recentArtists,
  ) {
    final next = c.analysis;

    final rate = TransitionPlanner.matchRate(current.bpm, next.bpm);
    final tempoGap = (rate - 1).abs();
    final tempo = math.exp(-math.pow(tempoGap / 0.05, 2));

    final distance = current.key.camelotDistance(next.key);
    final keyFit = switch (distance) {
      0 => 1.0,
      1 => 0.9,
      2 => 0.6,
      3 => 0.3,
      _ => 0.1,
    };
    // Trust the key only as far as both detections are confident.
    final trust = math
        .min(current.keyConfidence, next.keyConfidence)
        .clamp(0.0, 1.0);
    final key = 0.6 + (keyFit - 0.6) * trust;

    final step = switch (flow) {
      EnergyFlow.steady => 0.0,
      EnergyFlow.build => 0.06,
      EnergyFlow.windDown => -0.06,
    };
    final energy =
        1 - ((next.energy - (current.energy + step)).abs() * 2).clamp(0.0, 1.0);

    final parts = {
      'tempo': tempo,
      'key': key,
      'energy': energy,
      'affinity': c.affinity.clamp(0.0, 1.0),
    };
    var score = 0.0;
    for (final e in parts.entries) {
      score += (weights[e.key] ?? 0) * e.value;
    }
    if (c.artist == currentArtist) score *= 0.6;
    if (recentArtists.contains(c.artist)) score *= 0.8;
    return ScoredCandidate(c, score, parts);
  }
}
