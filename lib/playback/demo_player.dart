import 'dart:async';

import '../beat_sense/analysis/track_analysis.dart';
import '../library/models.dart';
import 'playback_controller.dart';

/// A silent stand-in player: advances a clock and pretends every song is
/// 120 BPM so beat-synced visuals can be previewed without audio.
class DemoPlayer extends PlaybackController {
  DemoPlayer(List<Track> tracks)
    : _queue = tracks,
      _position = const Duration(minutes: 1, seconds: 12) {
    positionListenable.value = _position;
  }

  static const _tick = Duration(milliseconds: 250);

  List<Track> _queue;
  int _index = 0;
  Duration _position;
  bool _playing = false;
  bool _beatSense = true;
  Timer? _timer;
  final _analyses = <String, TrackAnalysis>{};

  @override
  Track? get track => _queue.isEmpty ? null : _queue[_index];
  @override
  List<Track> get queue => _queue;
  @override
  int get index => _index;
  @override
  Duration get position => _position;
  @override
  Duration get duration => track?.duration ?? Duration.zero;
  @override
  bool get playing => _playing;

  @override
  TrackAnalysis? get analysis {
    final t = track;
    if (t == null || !_beatSense) return null;
    return _analyses.putIfAbsent(t.key, () => _grid(t.duration));
  }

  TrackAnalysis _grid(Duration d) {
    final seconds = d.inMilliseconds / 1000;
    final beats = [for (var t = 0.0; t < seconds; t += 0.5) t];
    final downbeats = [for (var i = 0; i < beats.length; i += 4) beats[i]];
    return TrackAnalysis(
      duration: seconds,
      bpm: 120,
      beatConfidence: 1,
      beats: beats,
      downbeats: downbeats,
      phrases: [for (var i = 0; i < downbeats.length; i += 8) downbeats[i]],
      key: const MusicalKey(9, minor: true),
      keyConfidence: 1,
      loudnessDb: -14,
      energy: 0.6,
      barEnergy: List.filled(downbeats.length, 1),
      introEnd: 8,
      outroStart: seconds - 16,
    );
  }

  @override
  bool get beatSenseEnabled => _beatSense;
  @override
  set beatSenseEnabled(bool value) {
    _beatSense = value;
    notifyListeners();
  }

  @override
  BeatSenseStatus get beatSense => _beatSense
      ? BeatSenseStatus(BeatSenseState.ready, next: upNext.firstOrNull)
      : BeatSenseStatus.off;

  @override
  Future<void> playTracks(List<Track> tracks, {int start = 0}) async {
    _queue = tracks;
    _index = start.clamp(0, tracks.length - 1);
    _position = Duration.zero;
    positionListenable.value = _position;
    notifyListeners();
    play();
  }

  @override
  void play() {
    if (_playing || track == null) return;
    _playing = true;
    _timer = Timer.periodic(_tick, (_) {
      _position += _tick;
      if (_position >= duration) {
        next();
        return;
      }
      positionListenable.value = _position;
    });
    notifyListeners();
  }

  @override
  void pause() {
    _timer?.cancel();
    _playing = false;
    notifyListeners();
  }

  @override
  void seek(double fraction) {
    _position = duration * fraction.clamp(0.0, 1.0);
    positionListenable.value = _position;
  }

  @override
  void skip(int seconds) {
    final ms = (_position.inMilliseconds + seconds * 1000).clamp(
      0,
      duration.inMilliseconds,
    );
    _position = Duration(milliseconds: ms);
    positionListenable.value = _position;
  }

  @override
  void next() {
    if (_queue.isEmpty) return;
    _index = (_index + 1) % _queue.length;
    _position = Duration.zero;
    positionListenable.value = _position;
    notifyListeners();
  }

  @override
  void previous() {
    if (_position > const Duration(seconds: 3) || _index == 0) {
      _position = Duration.zero;
    } else {
      _index--;
      _position = Duration.zero;
    }
    positionListenable.value = _position;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
