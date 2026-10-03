/// Everything Beat Sense knows about one track. Computed once on the
/// device, cached as JSON and reused for every mix.
class TrackAnalysis {
  const TrackAnalysis({
    required this.duration,
    required this.bpm,
    required this.beatConfidence,
    required this.beats,
    required this.downbeats,
    required this.phrases,
    required this.key,
    required this.keyConfidence,
    required this.loudnessDb,
    required this.energy,
    required this.barEnergy,
    required this.introEnd,
    required this.outroStart,
  });

  /// Bump when the analysis changes so cached results are recomputed.
  static const version = 1;

  /// Seconds.
  final double duration;
  final double bpm;

  /// 0–1: how regular the beat is. Low values (rubato, ambient, speech)
  /// make the planner fall back to a plain crossfade.
  final double beatConfidence;

  /// Beat, bar-start and phrase-start times in seconds.
  final List<double> beats;
  final List<double> downbeats;
  final List<double> phrases;

  final MusicalKey key;
  final double keyConfidence;

  /// Mean level of the audible frames, dB relative to full scale.
  final double loudnessDb;

  /// 0–1 overall energy (level and rhythmic density).
  final double energy;

  /// Relative energy of each bar (0–1), one entry per downbeat.
  final List<double> barEnergy;

  /// Where the full arrangement starts and where it starts to wind down.
  final double introEnd;
  final double outroStart;

  double get beatLength => 60 / bpm;

  Map<String, Object> toJson() => {
        'v': version,
        'duration': duration,
        'bpm': bpm,
        'beatConfidence': beatConfidence,
        'beats': beats,
        'downbeats': downbeats,
        'phrases': phrases,
        'key': key.index,
        'keyConfidence': keyConfidence,
        'loudnessDb': loudnessDb,
        'energy': energy,
        'barEnergy': barEnergy,
        'introEnd': introEnd,
        'outroStart': outroStart,
      };

  /// Returns null when [json] came from another analysis version.
  static TrackAnalysis? fromJson(Map<String, dynamic> json) {
    if (json['v'] != version) return null;
    List<double> list(String k) =>
        (json[k] as List).map((e) => (e as num).toDouble()).toList();
    double number(String k) => (json[k] as num).toDouble();
    return TrackAnalysis(
      duration: number('duration'),
      bpm: number('bpm'),
      beatConfidence: number('beatConfidence'),
      beats: list('beats'),
      downbeats: list('downbeats'),
      phrases: list('phrases'),
      key: MusicalKey.fromIndex(json['key'] as int),
      keyConfidence: number('keyConfidence'),
      loudnessDb: number('loudnessDb'),
      energy: number('energy'),
      barEnergy: list('barEnergy'),
      introEnd: number('introEnd'),
      outroStart: number('outroStart'),
    );
  }
}

/// One of the 24 major and minor keys, with its Camelot wheel position.
class MusicalKey {
  const MusicalKey(this.tonic, {required this.minor});

  factory MusicalKey.fromIndex(int index) =>
      MusicalKey(index % 12, minor: index >= 12);

  /// Pitch class of the tonic, 0 = C … 11 = B.
  final int tonic;
  final bool minor;

  int get index => tonic + (minor ? 12 : 0);

  static const _names = [
    'C', 'D♭', 'D', 'E♭', 'E', 'F', 'F♯', 'G', 'A♭', 'A', 'B♭', 'B', //
  ];

  String get name => '${_names[tonic]} ${minor ? 'minor' : 'major'}';

  /// Camelot number 1–12. Neighbouring numbers are a fifth apart, and the
  /// same number in A (minor) and B (major) are relative keys.
  int get camelotNumber {
    // C major is 8B; each fifth up adds one. A minor (relative of C) is 8A.
    final major = minor ? (tonic + 3) % 12 : tonic;
    return ((major * 7) % 12 + 7) % 12 + 1;
  }

  String get camelot => '$camelotNumber${minor ? 'A' : 'B'}';

  /// Harmonic distance on the Camelot wheel: 0 same key, 1 a neighbour
  /// (perfect mix), 2 a further step, and so on.
  int camelotDistance(MusicalKey other) {
    final d = (camelotNumber - other.camelotNumber).abs();
    final steps = d > 6 ? 12 - d : d;
    return steps + (minor == other.minor ? 0 : 1);
  }

  @override
  bool operator ==(Object other) =>
      other is MusicalKey && other.tonic == tonic && other.minor == minor;

  @override
  int get hashCode => index;

  @override
  String toString() => '$name ($camelot)';
}
