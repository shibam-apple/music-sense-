import 'dart:math' as math;
import 'dart:typed_data';

/// Pitch classes of common chords, for building test progressions.
const chords = {
  'C': [0, 4, 7],
  'Dm': [2, 5, 9],
  'E': [4, 8, 11],
  'F': [5, 9, 0],
  'G': [7, 11, 2],
  'Am': [9, 0, 4],
};

/// A synthetic loop: kick on every beat (louder on beat one), snare on two
/// and four, hi-hats on the off-beats, and optional sustained chords that
/// change every bar. Returns mono samples in [-1, 1].
Float32List drumLoop({
  required double bpm,
  double seconds = 40,
  int sampleRate = 22050,
  double silenceBefore = 0,
  List<String> progression = const [],
  double gain = 1,
}) {
  final total = ((silenceBefore + seconds) * sampleRate).round();
  final out = Float32List(total);
  final rng = math.Random(1);
  final beat = 60 / bpm;
  final offset = (silenceBefore * sampleRate).round();

  void add(int at, double value) {
    if (at >= 0 && at < total) out[at] += value;
  }

  final beats = (seconds / beat).floor();
  for (var b = 0; b < beats; b++) {
    final start = offset + (b * beat * sampleRate).round();
    final downbeat = b % 4 == 0;
    // Kick: falling sine with fast decay.
    for (var i = 0; i < (0.12 * sampleRate); i++) {
      final t = i / sampleRate;
      final f = 60 - 25 * t / 0.12;
      add(start + i,
          (downbeat ? 0.9 : 0.55) * math.exp(-t * 28) * math.sin(2 * math.pi * f * t));
    }
    // Snare on 2 and 4.
    if (b % 4 == 1 || b % 4 == 3) {
      for (var i = 0; i < (0.09 * sampleRate); i++) {
        final t = i / sampleRate;
        add(start + i,
            0.25 * math.exp(-t * 35) * ((rng.nextDouble() * 2 - 1) + math.sin(2 * math.pi * 190 * t)));
      }
    }
    // Hi-hat on the off-beat.
    final hat = start + (beat * sampleRate / 2).round();
    var last = 0.0;
    for (var i = 0; i < (0.03 * sampleRate); i++) {
      final n = rng.nextDouble() * 2 - 1;
      add(hat + i, 0.08 * math.exp(-i / sampleRate * 120) * (n - last));
      last = n;
    }
  }

  if (progression.isNotEmpty) {
    final bar = beat * 4;
    for (var i = 0; i < (seconds * sampleRate); i++) {
      final t = i / sampleRate;
      final chord = chords[progression[(t / bar).floor() % progression.length]]!;
      var v = 0.0;
      for (final pc in chord) {
        for (final octave in [3, 4]) {
          final hz = 440 * math.pow(2, (pc + 12 * (octave + 1) - 69) / 12);
          v += 0.035 * math.sin(2 * math.pi * hz * t);
        }
      }
      final root = 440 * math.pow(2, (chord.first + 36 - 69) / 12);
      v += 0.06 * math.sin(2 * math.pi * root * t);
      add(offset + i, v);
    }
  }

  for (var i = 0; i < total; i++) {
    out[i] = (out[i] * gain).clamp(-1.0, 1.0);
  }
  return out;
}
