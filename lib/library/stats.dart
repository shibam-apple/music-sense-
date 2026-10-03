import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../playback/playback_controller.dart';
import 'models.dart';

/// Listening time per month and play counts per song, kept on the device.
class ListeningStats extends ChangeNotifier {
  final _secondsByMonth = <String, int>{};
  final _plays = <String, int>{};
  File? _file;
  PlaybackController? _player;
  String? _countedKey;
  DateTime? _lastTick;
  int _unsaved = 0;

  static String _month(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  double get hoursThisMonth =>
      (_secondsByMonth[_month(DateTime.now())] ?? 0) / 3600;

  int playsOf(Track t) => _plays[t.key] ?? 0;

  /// Most played songs, most first.
  List<Track> topOf(List<Track> tracks, {int count = 50}) {
    final played = tracks.where((t) => playsOf(t) > 0).toList()
      ..sort((a, b) => playsOf(b).compareTo(playsOf(a)));
    return played.take(count).toList();
  }

  Future<void> attach(PlaybackController player) async {
    if (!kIsWeb) {
      try {
        _file = File(
          '${(await getApplicationSupportDirectory()).path}/stats.json',
        );
        if (await _file!.exists()) {
          final json =
              jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
          _secondsByMonth.addAll((json['months'] as Map).cast<String, int>());
          _plays.addAll((json['plays'] as Map).cast<String, int>());
        }
      } catch (_) {}
    }
    _player = player..addListener(_onPlayer);
    notifyListeners();
  }

  void _onPlayer() {
    final p = _player!;
    final now = DateTime.now();
    if (p.playing && _lastTick != null) {
      final seconds = now.difference(_lastTick!).inSeconds.clamp(0, 5);
      final month = _month(now);
      _secondsByMonth[month] = (_secondsByMonth[month] ?? 0) + seconds;
      _unsaved += seconds;
    }
    _lastTick = p.playing ? now : null;

    // A play counts once 30 seconds in.
    final t = p.track;
    if (t != null && t.key != _countedKey && p.position.inSeconds >= 30) {
      _countedKey = t.key;
      _plays[t.key] = (_plays[t.key] ?? 0) + 1;
      _unsaved += 30;
    }
    if (_unsaved >= 30) {
      _unsaved = 0;
      _save();
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null) return;
    try {
      await f.writeAsString(
        jsonEncode({'months': _secondsByMonth, 'plays': _plays}),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _player?.removeListener(_onPlayer);
    super.dispose();
  }
}
