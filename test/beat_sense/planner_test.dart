import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_sense/beat_sense/analysis/analyzer.dart';
import 'package:music_sense/beat_sense/analysis/track_analysis.dart';
import 'package:music_sense/beat_sense/next_track.dart';
import 'package:music_sense/beat_sense/transition.dart';

import 'synth.dart';

/// A track with a perfect grid: [bpm], 8-bar phrases, an intro and outro.
TrackAnalysis track({
  double bpm = 124,
  double duration = 200,
  MusicalKey key = const MusicalKey(9, minor: true),
  double keyConfidence = 0.8,
  double beatConfidence = 0.8,
  double energy = 0.6,
  double loudnessDb = -10,
  double introBars = 8,
  double outroBars = 8,
}) {
  final beat = 60 / bpm;
  final beats = [for (var t = 0.5; t < duration; t += beat) t];
  final downbeats = [for (var i = 0; i < beats.length; i += 4) beats[i]];
  final phrases = [for (var i = 0; i < downbeats.length; i += 8) downbeats[i]];
  return TrackAnalysis(
    duration: duration,
    bpm: bpm,
    beatConfidence: beatConfidence,
    beats: beats,
    downbeats: downbeats,
    phrases: phrases,
    key: key,
    keyConfidence: keyConfidence,
    loudnessDb: loudnessDb,
    energy: energy,
    barEnergy: List.filled(downbeats.length, 1),
    introEnd: downbeats[introBars.toInt()],
    outroStart: downbeats[downbeats.length - outroBars.toInt()],
  );
}

void main() {
  const planner = TransitionPlanner();

  group('TransitionPlanner', () {
    test('beat-matches close tempos from a phrase start', () {
      final a = track(bpm: 124), b = track(bpm: 120);
      final plan = planner.plan(a, b);
      expect(plan.beatMatched, isTrue);
      expect(a.phrases, contains(plan.exitAt));
      expect(b.downbeats, contains(plan.entryAt));
      expect(plan.incomingRate, closeTo(124 / 120, 1e-9));
      expect(plan.endsAt, lessThanOrEqualTo(a.duration));
      // Incoming beats, played at the new rate, land on outgoing beats.
      expect(b.beatLength / plan.incomingRate, closeTo(a.beatLength, 1e-9));
    });

    test('long intros are entered so the drop lands as the blend ends', () {
      final a = track(), b = track(introBars: 16);
      final plan = planner.plan(a, b);
      expect(plan.entryAt + plan.length * plan.incomingRate,
          closeTo(b.introEnd, b.beatLength));
    });

    test('blends neighbouring keys and swaps bass on clashing ones', () {
      final a = track(key: const MusicalKey(9, minor: true));
      expect(planner.plan(a, track(key: const MusicalKey(4, minor: true))).style,
          TransitionStyle.blend);
      expect(planner.plan(a, track(key: const MusicalKey(3, minor: true))).style,
          TransitionStyle.bassSwap);
    });

    test('half-time tempos match without a rate change', () {
      final plan = planner.plan(track(bpm: 174), track(bpm: 87));
      expect(plan.beatMatched, isTrue);
      expect(plan.incomingRate, closeTo(1, 1e-9));
    });

    test('cuts on the beat when tempos are too far apart', () {
      final plan = planner.plan(track(bpm: 128), track(bpm: 100));
      expect(plan.style, TransitionStyle.cutOnBeat);
      expect(plan.incomingRate, 1);
    });

    test('crossfades when a song has no steady beat', () {
      final plan = planner.plan(track(), track(beatConfidence: 0.1));
      expect(plan.style, TransitionStyle.crossfade);
    });

    test('levels are equal power and the bass swaps halfway', () {
      final plan = planner.plan(
          track(), track(key: const MusicalKey(3, minor: true)));
      expect(plan.style, TransitionStyle.bassSwap);
      for (var x = 0.0; x <= 1.0; x += 0.1) {
        final l = plan.levelsAt(x);
        expect(l.outgoing * l.outgoing + l.incoming * l.incoming,
            closeTo(1, 1e-9));
      }
      expect(plan.levelsAt(0.25).incomingBassDb, MixLevels.bassCut);
      expect(plan.levelsAt(0.75).outgoingBassDb, MixLevels.bassCut);
    });

    test('evens out loudness', () {
      final plan = planner.plan(track(loudnessDb: -8), track(loudnessDb: -16));
      expect(plan.outgoingGainDb, closeTo(-6, 1e-9));
      expect(plan.incomingGainDb, closeTo(2, 1e-9));
    });

    test('plans from real analysis of synthetic songs', () {
      final analyzer = BeatSenseAnalyzer();
      final a = analyzer.analyze(drumLoop(bpm: 126, seconds: 120), 22050);
      final b = analyzer.analyze(drumLoop(bpm: 122, seconds: 120), 22050);
      final plan = planner.plan(a, b);
      expect(plan.beatMatched, isTrue);
      expect(plan.incomingRate, closeTo(126 / 122, 0.01));
      expect(a.downbeats, contains(plan.exitAt));
      expect(b.downbeats, contains(plan.entryAt));
    });
  });

  group('NextTrackScorer', () {
    const scorer = NextTrackScorer();
    final current = track(bpm: 124, key: const MusicalKey(9, minor: true));

    Candidate<String> c(String id, TrackAnalysis a,
            {String artist = 'Other', double affinity = 0.5}) =>
        Candidate(item: id, analysis: a, artist: artist, affinity: affinity);

    test('prefers matching tempo and key', () {
      final ranked = scorer.rank(current, 'Me', [
        c('far tempo', track(bpm: 95)),
        c('clashing key', track(bpm: 124, key: const MusicalKey(3, minor: false))),
        c('perfect', track(bpm: 123, key: const MusicalKey(4, minor: true))),
      ]);
      expect(ranked.first.candidate.item, 'perfect');
      expect(ranked.last.candidate.item, 'far tempo');
    });

    test('avoids the same artist back to back', () {
      final ranked = scorer.rank(current, 'Me', [
        c('same artist', track(), artist: 'Me'),
        c('other artist', track(), artist: 'Them'),
      ]);
      expect(ranked.first.candidate.item, 'other artist');
    });

    test('build mode prefers a step up in energy', () {
      const build = NextTrackScorer(flow: EnergyFlow.build);
      final ranked = build.rank(current, 'Me', [
        c('calmer', track(energy: 0.45)),
        c('higher', track(energy: 0.66)),
      ]);
      expect(ranked.first.candidate.item, 'higher');
    });

    test('scores stay within 0–1', () {
      final r = scorer.rank(current, 'Me', [c('x', track(), affinity: 1)]);
      expect(r.single.score, inInclusiveRange(0, 1));
      expect(r.single.parts.values.every((v) => v >= 0 && v <= 1), isTrue);
      expect(math.max(0, r.single.score), r.single.score);
    });
  });
}
