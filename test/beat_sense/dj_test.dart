import 'package:flutter_test/flutter_test.dart';
import 'package:music_sense/beat_sense/analysis/track_analysis.dart';
import 'package:music_sense/beat_sense/dj.dart';
import 'package:music_sense/beat_sense/next_track.dart';
import 'package:music_sense/beat_sense/transition.dart';

/// A 4-minute song on a perfect grid: quiet for [dropBar] bars, then loud.
TrackAnalysis song({
  double bpm = 124,
  double duration = 240,
  MusicalKey key = const MusicalKey(9, minor: true),
  double energy = 0.6,
  int dropBar = 16,
}) {
  final beat = 60 / bpm;
  final beats = [for (var t = 0.25; t < duration; t += beat) t];
  final downbeats = [for (var i = 0; i < beats.length; i += 4) beats[i]];
  final phrases = [for (var i = 0; i < downbeats.length; i += 8) downbeats[i]];
  return TrackAnalysis(
    duration: duration,
    bpm: bpm,
    beatConfidence: 0.9,
    beats: beats,
    downbeats: downbeats,
    phrases: phrases,
    key: key,
    keyConfidence: 0.8,
    loudnessDb: -10,
    energy: energy,
    barEnergy: [
      for (var i = 0; i < downbeats.length; i++) i < dropBar ? 0.4 : 1.0,
    ],
    introEnd: downbeats[8],
    outroStart: downbeats[downbeats.length - 8],
  );
}

void main() {
  const dj = DjPlanner();

  test('finds the drop where the energy jumps', () {
    final a = song(dropBar: 16);
    expect(DjPlanner.dropOf(a), a.downbeats[16]);
  });

  test('blends so the blend finishes on the next song\'s drop', () {
    final a = song(bpm: 124), b = song(bpm: 122, dropBar: 24);
    final move = dj.plan(a, b);
    final p = move.plan;
    expect(p.style, isNot(TransitionStyle.dropCut));
    expect(a.phrases, contains(p.exitAt));
    expect(p.exitAt, greaterThanOrEqualTo(dj.minPlay));
    expect(p.exitAt, lessThan(a.outroStart));
    final drop = DjPlanner.dropOf(b);
    final arrives = p.entryAt + p.length * p.incomingRate;
    expect(arrives, lessThanOrEqualTo(drop + 0.05));
    expect(drop - arrives, lessThan(4 * b.beatLength + 0.05));
  });

  test('cuts on a phrase downbeat into the drop when keys clash', () {
    final a = song(bpm: 124, key: const MusicalKey(9, minor: true));
    final b = song(bpm: 123, key: const MusicalKey(3, minor: false));
    final move = dj.plan(a, b);
    final p = move.plan;
    expect(p.style, TransitionStyle.dropCut);
    expect(move.why, contains('keys clash'));
    // The swap moment is a phrase start of the outgoing song…
    expect(a.phrases.any((x) => (x - p.endsAt).abs() < 1e-6), isTrue);
    // …and the incoming song is exactly at its drop then.
    final drop = DjPlanner.dropOf(b);
    expect(p.entryAt + p.length * p.incomingRate, closeTo(drop, 1e-6));
    expect(p.levelsAt(0.5).incoming, 0);
    expect(p.levelsAt(1).incoming, 1);
    expect(p.levelsAt(1).outgoing, 0);
  });

  test('cuts into the drop when the energy goes up', () {
    final a = song(energy: 0.4), b = song(bpm: 125, energy: 0.8);
    expect(dj.plan(a, b).plan.style, TransitionStyle.dropCut);
  });

  test('mixes in some cuts for variety', () {
    final a = song(), b = song(bpm: 123);
    final styles = [
      for (var i = 0; i < 3; i++) dj.plan(a, b, setIndex: i).plan.style,
    ];
    expect(styles, contains(TransitionStyle.dropCut));
    expect(styles.where((s) => s != TransitionStyle.dropCut), isNotEmpty);
  });

  test('plays at least a minute of a song that started at its drop', () {
    final a = song(), b = song(bpm: 123);
    final from = a.downbeats[16];
    final p = dj.plan(a, b, playedFrom: from).plan;
    expect(p.exitAt - from, greaterThanOrEqualTo(dj.minPlay - 1e-6));
  });

  test('a re-timed cut still lands on a downbeat', () {
    const planner = TransitionPlanner();
    final a = song(key: const MusicalKey(9, minor: true));
    final b = song(key: const MusicalKey(3, minor: false));
    final p = dj.plan(a, b).plan;
    final moved = planner.retime(p, a, 33.3);
    expect(a.downbeats.any((d) => (d - moved.endsAt).abs() < 1e-6), isTrue);
    expect(moved.exitAt, greaterThanOrEqualTo(33.3 - 1e-6));
  });

  test('picks the next song that keeps the set flowing', () {
    final now = song(bpm: 124, energy: 0.5);
    final candidates = [
      Candidate(item: 'far', analysis: song(bpm: 90), artist: 'A'),
      Candidate(
        item: 'close',
        analysis: song(bpm: 125, energy: 0.56),
        artist: 'B',
      ),
      Candidate(
        item: 'clash',
        analysis: song(bpm: 124, key: const MusicalKey(3, minor: false)),
        artist: 'C',
      ),
    ];
    expect(dj.pick(now, 'X', candidates)!.candidate.item, 'close');
  });
}
