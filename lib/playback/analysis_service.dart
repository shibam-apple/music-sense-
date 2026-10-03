import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../beat_sense/analysis/analyzer.dart';
import '../beat_sense/analysis/track_analysis.dart';
import '../library/models.dart';
import '../sources/local_source.dart';
import '../sources/music_source.dart';

/// Gets Beat Sense analysis for tracks: from memory, from the on-disk
/// cache, or by decoding the audio and analysing it in a background
/// isolate. Runs one analysis at a time to spare the battery.
class AnalysisService {
  AnalysisService(this._sources);

  final Map<String, MusicSource> _sources;
  static const sampleRate = 22050;

  final _memory = <String, TrackAnalysis>{};
  final _pending = <String, Future<TrackAnalysis?>>{};
  Future<void> _queue = Future.value();
  Directory? _dir;

  TrackAnalysis? cached(Track track) => _memory[track.key];

  Future<TrackAnalysis?> analyse(Track track) {
    final hit = _memory[track.key];
    if (hit != null) return SynchronousFuture(hit);
    return _pending.putIfAbsent(track.key, () async {
      try {
        final result = await _load(track) ?? await _serial(() => _compute(track));
        if (result != null) _memory[track.key] = result;
        return result;
      } catch (e, s) {
        debugPrint('Beat Sense: could not analyse ${track.title}: $e\n$s');
        return null;
      } finally {
        _pending.remove(track.key);
      }
    });
  }

  Future<T> _serial<T>(Future<T> Function() work) {
    final run = _queue.then((_) => work());
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<TrackAnalysis?> _compute(Track track) async {
    final source = _sources[track.source];
    if (source == null) return null;
    final ref = await source.resolve(track);
    final bytes = await LocalSource.channel.invokeMethod<Uint8List>('decodePcm', {
      'uri': ref.uri.toString(),
      'headers': ref.headers,
      'sampleRate': sampleRate,
      'maxSeconds': 900,
    });
    if (bytes == null || bytes.lengthInBytes < sampleRate * 4 * 10) return null;

    final transferable = TransferableTypedData.fromList([bytes]);
    final json = await Isolate.run(() {
      final data = transferable.materialize().asUint8List();
      final pcm = data.buffer.asFloat32List(data.offsetInBytes, data.lengthInBytes ~/ 4);
      return BeatSenseAnalyzer().analyze(pcm, sampleRate).toJson();
    });
    final analysis = TrackAnalysis.fromJson(json)!;
    await _save(track, json);
    return analysis;
  }

  Future<File> _file(Track track) async {
    _dir ??= Directory('${(await getApplicationSupportDirectory()).path}/beat_sense');
    await _dir!.create(recursive: true);
    final name = track.key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${_dir!.path}/$name.json');
  }

  Future<TrackAnalysis?> _load(Track track) async {
    final file = await _file(track);
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return TrackAnalysis.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(Track track, Map<String, Object> json) async {
    await (await _file(track)).writeAsString(jsonEncode(json));
  }
}
