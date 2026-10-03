import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../beat_sense/analysis/track_analysis.dart';
import '../library/models.dart';
import '../sources/music_source.dart';

/// One of the two players Beat Sense mixes between, with its own volume,
/// speed and (on Android) equalizer for the bass hand-over.
class Deck {
  Deck() : this._(_android ? AndroidEqualizer() : null);

  Deck._(this._eq)
      : audio = AudioPlayer(
          audioPipeline:
              _eq == null ? null : AudioPipeline(androidAudioEffects: [_eq]),
        );

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final AndroidEqualizer? _eq;
  final AudioPlayer audio;

  Track? track;
  TrackAnalysis? analysis;

  /// Loudness correction in dB. Players can't boost above full scale, so
  /// only cuts are applied; the engine aligns tracks downward.
  double gainDb = 0;
  double _level = 1;
  double _bassDb = 0;
  double _rate = 1;

  double get seconds => audio.position.inMicroseconds / 1e6;
  double get rate => _rate;
  bool get playing => audio.playing;

  Future<void> load(Track track, StreamRef ref, {double at = 0}) async {
    this.track = track;
    analysis = null;
    await audio.setAudioSource(
      AudioSource.uri(ref.uri, headers: ref.headers.isEmpty ? null : ref.headers, tag: track),
      initialPosition: Duration(microseconds: (at * 1e6).round()),
    );
    await setRate(1);
    await setBass(0);
  }

  /// Starts playback without waiting: just_audio's play() only completes
  /// when playback stops.
  void start() => unawaited(audio.play().catchError((Object _) {}));

  Future<void> pause() => audio.pause();

  Future<void> seek(double seconds) =>
      audio.seek(Duration(microseconds: (seconds * 1e6).round()));

  Future<void> setLevel(double level) async {
    _level = level;
    final gain = math.pow(10, math.min(0, gainDb) / 20).toDouble();
    await audio.setVolume((level * gain).clamp(0.0, 1.0));
  }

  Future<void> applyGain(double db) async {
    gainDb = db;
    await setLevel(_level);
  }

  Future<void> setRate(double rate) async {
    if ((rate - _rate).abs() < 1e-4) return;
    _rate = rate;
    await audio.setSpeed(rate);
  }

  /// Gain for the bands below ~250 Hz, used to swap bass between decks.
  Future<void> setBass(double db) async {
    final eq = _eq;
    if (eq == null || (db - _bassDb).abs() < 0.1) return;
    _bassDb = db;
    await eq.setEnabled(true);
    final params = await eq.parameters;
    for (final band in params.bands) {
      if (band.centerFrequency < 250) {
        await band.setGain(db.clamp(params.minDecibels, params.maxDecibels));
      }
    }
  }

  Future<void> dispose() => audio.dispose();
}

