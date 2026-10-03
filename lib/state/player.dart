import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/library.dart';

/// Playback state for the UI. This is a stand-in clock until the audio
/// engine exists; the pages only depend on this interface.
class PlayerState extends ChangeNotifier {
  static const _tick = Duration(milliseconds: 250);

  Song _song = MockLibrary.futuristic;
  Duration _position = const Duration(minutes: 1, seconds: 12);
  bool _playing = false;
  Timer? _timer;

  Song get song => _song;
  Duration get position => _position;
  Duration get duration => _song.duration;
  bool get playing => _playing;

  double get progress {
    final total = duration.inMilliseconds;
    return total == 0 ? 0 : _position.inMilliseconds / total;
  }

  void toggle() => _playing ? pause() : play();

  void play() {
    if (_playing) return;
    _playing = true;
    _timer = Timer.periodic(_tick, (_) {
      _position += _tick;
      if (_position >= duration) _position = Duration.zero;
      notifyListeners();
    });
    notifyListeners();
  }

  void pause() {
    _timer?.cancel();
    _playing = false;
    notifyListeners();
  }

  void seek(double fraction) {
    _position = duration * fraction.clamp(0.0, 1.0);
    notifyListeners();
  }

  void skip(int seconds) {
    final ms = (_position.inMilliseconds + seconds * 1000)
        .clamp(0, duration.inMilliseconds);
    _position = Duration(milliseconds: ms);
    notifyListeners();
  }

  void playSong(Song song) {
    _song = song;
    _position = Duration.zero;
    notifyListeners();
    play();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Makes the [PlayerState] available to every page.
class PlayerScope extends InheritedNotifier<PlayerState> {
  const PlayerScope({
    super.key,
    required PlayerState player,
    required super.child,
  }) : super(notifier: player);

  static PlayerState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlayerScope>()!.notifier!;
}

String formatTime(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
