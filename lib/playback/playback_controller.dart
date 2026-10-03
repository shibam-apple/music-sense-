import 'package:flutter/widgets.dart';

import '../beat_sense/analysis/track_analysis.dart';
import '../beat_sense/transition.dart';
import '../library/models.dart';

enum BeatSenseState {
  /// Turned off by the listener.
  off,

  /// Reading the current or next song.
  analysing,

  /// The next transition is planned.
  ready,

  /// Two songs are playing together right now.
  mixing,

  /// The songs can't be analysed (no audio access); plain playback.
  unavailable,
}

class BeatSenseStatus {
  const BeatSenseStatus(this.state, {this.plan, this.next});

  static const off = BeatSenseStatus(BeatSenseState.off);

  final BeatSenseState state;
  final TransitionPlan? plan;
  final Track? next;

  /// One short line for the Now Playing label.
  String get label => switch (state) {
        BeatSenseState.off => 'NOW PLAYING',
        BeatSenseState.analysing => 'BEAT SENSE · LISTENING',
        BeatSenseState.ready => 'BEAT SENSE · READY',
        BeatSenseState.mixing => 'BEAT SENSE · MIXING',
        BeatSenseState.unavailable => 'NOW PLAYING',
      };
}

/// Everything the pages need from playback. Implemented by the Beat Sense
/// engine on devices and by a demo clock on the web preview and in tests.
abstract class PlaybackController extends ChangeNotifier {
  Track? get track;
  List<Track> get queue;
  int get index;

  List<Track> get upNext =>
      index + 1 < queue.length ? queue.sublist(index + 1) : const [];

  Duration get position;
  Duration get duration;
  bool get playing;

  double get progress {
    final total = duration.inMilliseconds;
    return total <= 0 ? 0 : (position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  /// Analysis of the current song, when Beat Sense has it.
  TrackAnalysis? get analysis;

  /// 0–1 position within the current beat, for visuals that pulse in time;
  /// null when the beat isn't known.
  double? get beatPhase {
    final a = analysis;
    if (a == null || a.beats.length < 2) return null;
    final t = position.inMicroseconds / 1e6;
    var lo = 0, hi = a.beats.length - 1;
    if (t < a.beats.first || t >= a.beats.last) return null;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (a.beats[mid] <= t) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (t - a.beats[lo]) / (a.beats[hi] - a.beats[lo]);
  }

  bool get beatSenseEnabled;
  set beatSenseEnabled(bool value);
  BeatSenseStatus get beatSense;

  Future<void> playTracks(List<Track> tracks, {int start = 0});
  void play();
  void pause();
  void toggle() => playing ? pause() : play();
  void seek(double fraction);
  void skip(int seconds);
  void next();
  void previous();
}

/// Makes the [PlaybackController] available to every page.
class PlayerScope extends InheritedNotifier<PlaybackController> {
  const PlayerScope({
    super.key,
    required PlaybackController player,
    required super.child,
  }) : super(notifier: player);

  static PlaybackController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlayerScope>()!.notifier!;

  /// Reads the controller without rebuilding when it changes; for
  /// per-frame visuals that poll it from a ticker.
  static PlaybackController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PlayerScope>()!.notifier!;
}

String formatTime(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
