import 'package:flutter_test/flutter_test.dart';
import 'package:music_sense/beat_sense/analysis/analyzer.dart';
import 'package:music_sense/beat_sense/analysis/track_analysis.dart';

import 'synth.dart';

void main() {
  const sr = 22050;
  final analyzer = BeatSenseAnalyzer();

  group('tempo', () {
    for (final bpm in [90.0, 100.0, 128.0, 140.0]) {
      test('finds $bpm BPM', () {
        final a = analyzer.analyze(drumLoop(bpm: bpm), sr);
        expect(a.bpm, closeTo(bpm, 1.0));
      });
    }

    // Drum & bass is read at full or half time, as DJs do; the planner
    // treats the two as the same tempo.
    test('finds 174 BPM or its half-time 87', () {
      final a = analyzer.analyze(drumLoop(bpm: 174), sr);
      final folded = a.bpm < 120 ? a.bpm * 2 : a.bpm;
      expect(folded, closeTo(174, 1.5));
    });
  });

  test('beats land on the kicks', () {
    const bpm = 128.0;
    final a = analyzer.analyze(drumLoop(bpm: bpm), sr);
    const beat = 60 / bpm;
    final truth = [for (var t = 2.0; t < 38; t += beat) t];
    var hits = 0;
    for (final t in [for (var i = 0; i * beat < 38; i++) i * beat]) {
      if (t < 2) continue;
      if (a.beats.any((b) => (b - t).abs() < 0.035)) hits++;
    }
    expect(hits / truth.length, greaterThan(0.95));
  });

  test('bars start on the accented beat', () {
    const bpm = 120.0;
    final a = analyzer.analyze(drumLoop(bpm: bpm), sr);
    const bar = 4 * 60 / bpm;
    final onBarline = a.downbeats.where((d) {
      final phase = (d / bar) - (d / bar).round();
      return (phase * bar).abs() < 0.04;
    }).length;
    expect(onBarline / a.downbeats.length, greaterThan(0.9));
  });

  group('key', () {
    test('A minor progression reads as A minor (8A)', () {
      final a = analyzer.analyze(
        drumLoop(
          bpm: 110,
          progression: ['Am', 'Am', 'Dm', 'E', 'Am', 'F', 'E', 'Am'],
        ),
        sr,
      );
      expect(a.key, const MusicalKey(9, minor: true));
      expect(a.key.camelot, '8A');
    });

    test('C major progression reads as C major (8B)', () {
      final a = analyzer.analyze(
        drumLoop(
          bpm: 110,
          progression: ['C', 'C', 'F', 'G', 'C', 'Am', 'G', 'C'],
        ),
        sr,
      );
      expect(a.key, const MusicalKey(0, minor: false));
      expect(a.key.camelot, '8B');
    });
  });

  test('loudness follows gain', () {
    final full = analyzer.analyze(drumLoop(bpm: 120, seconds: 20), sr);
    final half = analyzer.analyze(
      drumLoop(bpm: 120, seconds: 20, gain: 0.5),
      sr,
    );
    expect(full.loudnessDb - half.loudnessDb, closeTo(6.02, 0.5));
  });

  test('leading silence is skipped', () {
    final a = analyzer.analyze(drumLoop(bpm: 120, silenceBefore: 6), sr);
    expect(a.beats.first, greaterThan(5.9));
    expect(a.introEnd, greaterThan(5.9));
    expect(a.bpm, closeTo(120, 1));
  });

  test('phrases are 8 bars apart', () {
    final a = analyzer.analyze(drumLoop(bpm: 125, seconds: 90), sr);
    const phrase = 32 * 60 / 125;
    for (var i = 1; i < a.phrases.length; i++) {
      expect(a.phrases[i] - a.phrases[i - 1], closeTo(phrase, 0.08));
    }
  });

  test('round-trips through JSON', () {
    final a = analyzer.analyze(drumLoop(bpm: 120, seconds: 20), sr);
    final b = TrackAnalysis.fromJson(a.toJson())!;
    expect(b.bpm, a.bpm);
    expect(b.key, a.key);
    expect(b.beats, a.beats);
  });

  group('Camelot', () {
    test('wheel positions', () {
      expect(const MusicalKey(0, minor: false).camelot, '8B');
      expect(const MusicalKey(7, minor: false).camelot, '9B');
      expect(const MusicalKey(5, minor: false).camelot, '7B');
      expect(const MusicalKey(9, minor: true).camelot, '8A');
      expect(const MusicalKey(4, minor: true).camelot, '9A');
      expect(const MusicalKey(11, minor: false).camelot, '1B');
    });

    test('distance', () {
      const c = MusicalKey(0, minor: false), g = MusicalKey(7, minor: false);
      const am = MusicalKey(9, minor: true), fs = MusicalKey(6, minor: false);
      expect(c.camelotDistance(c), 0);
      expect(c.camelotDistance(g), 1);
      expect(c.camelotDistance(am), 1);
      expect(c.camelotDistance(fs), 6);
    });
  });
}
