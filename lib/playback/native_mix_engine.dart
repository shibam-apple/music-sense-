import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../beat_sense/analysis/track_analysis.dart';
import '../beat_sense/dj.dart';
import '../beat_sense/mix_script.dart';
import '../beat_sense/next_track.dart';
import '../beat_sense/transition.dart';
import '../library/models.dart';
import '../sources/music_source.dart';
import 'analysis_service.dart';
import 'playback_controller.dart';

/// Beat Sense on the native audio engine (Android): both songs play
/// through one mixer with sample-exact beat lock, a DJ's 3-band EQ and
/// filter moves, and key matching. This class decides *what* to play and
/// *how* to mix; the engine does the audio.
class NativeMixEngine extends PlaybackController {
  NativeMixEngine._({required this._sources, required this._analysis}) {
    _events = _eventChannel.receiveBroadcastStream().listen(_onEvent);
  }

  static const _methods = MethodChannel('music_sense/engine');
  static const _eventChannel = EventChannel('music_sense/engine/events');

  /// The engine, or null when it isn't available on this device.
  static Future<NativeMixEngine?> create({
    required Map<String, MusicSource> sources,
    required AnalysisService analysis,
  }) async {
    try {
      await _methods.invokeMethod('init');
      return NativeMixEngine._(sources: sources, analysis: analysis);
    } catch (e) {
      debugPrint('Beat Sense engine unavailable: $e');
      return null;
    }
  }

  final Map<String, MusicSource> _sources;
  final AnalysisService _analysis;
  final _planner = const TransitionPlanner(
    targetLoudnessDb: -18,
    keyShift: true,
  );
  late final _dj = DjPlanner(planner: _planner);
  final _scorer = const NextTrackScorer();
  late final StreamSubscription<dynamic> _events;

  List<Track> _queue = const [];
  int _index = 0;
  bool _beatSense = true;
  bool _djMode = false;
  int _setIndex = 0;
  double _playedFrom = 0;
  BeatSenseStatus _status = BeatSenseStatus.off;
  TransitionPlan? _plan;
  Track? _next;
  TrackAnalysis? _current;
  bool _prepared = false;
  bool _mixing = false;
  bool _playing = false;
  bool _disposed = false;
  int _generation = 0;
  double _seconds = 0;
  double _duration = 0;
  double _nextDuration = 0;

  /// When play/pause was last asked; the engine's reports of play state
  /// are ignored briefly after, until it has applied the command.
  DateTime _commanded = DateTime(0);

  /// Key shift the playing song is on (from the mix that brought it in).
  int _shift = 0;

  // ---- PlaybackController ----

  @override
  Track? get track => _queue.isEmpty ? null : _queue[_index];
  @override
  List<Track> get queue => _queue;
  @override
  int get index => _index;
  @override
  Duration get position => Duration(microseconds: (_seconds * 1e6).round());
  @override
  Duration get duration {
    final d = _duration > 0 ? _duration : (_current?.duration ?? 0);
    return d > 0
        ? Duration(microseconds: (d * 1e6).round())
        : (track?.duration ?? Duration.zero);
  }

  @override
  bool get playing => _playing;
  @override
  TrackAnalysis? get analysis => _current;
  @override
  TrackAnalysis? get nextAnalysis {
    final next = _status.next;
    return next == null ? null : _analysis.cached(next);
  }

  @override
  BeatSenseStatus get beatSense => _status;
  @override
  bool get beatSenseEnabled => _beatSense;

  @override
  set beatSenseEnabled(bool value) {
    if (_beatSense == value) return;
    _beatSense = value;
    if (!value) {
      _cancelPlan();
      _status = BeatSenseStatus.off;
    } else {
      _status = const BeatSenseStatus(BeatSenseState.analysing);
      unawaited(_prepareNext());
    }
    notifyListeners();
  }

  @override
  bool get djMode => _djMode;

  @override
  set djMode(bool value) {
    if (_djMode == value) return;
    _djMode = value;
    _setIndex = 0;
    if (value) _beatSense = true;
    if (!_mixing && track != null) {
      _cancelPlan();
      _status = const BeatSenseStatus(BeatSenseState.analysing);
      unawaited(_prepareNext());
    }
    notifyListeners();
  }

  @override
  bool get canMixNow =>
      _beatSense && _prepared && _plan != null && !_mixing && _playing;

  @override
  void mixNow() => _mixSoon();

  @override
  Future<void> playTracks(List<Track> tracks, {int start = 0}) async {
    if (tracks.isEmpty) return;
    _queue = List.of(tracks);
    _index = start.clamp(0, tracks.length - 1);
    _setIndex = 0;
    await _startCurrent(play: true);
  }

  @override
  void play() {
    if (track == null) return;
    _playing = true;
    _commanded = DateTime.now();
    unawaited(_call('play'));
    notifyListeners();
  }

  @override
  void pause() {
    _playing = false;
    _commanded = DateTime.now();
    unawaited(_call('pause'));
    notifyListeners();
  }

  @override
  void seek(double fraction) {
    final total = duration.inMicroseconds / 1e6;
    final target = total * fraction.clamp(0.0, 1.0);
    final plan = _plan, from = _current;
    final wasMixing = _mixing;
    if (wasMixing) {
      // The engine drops a mix that is seeked through; plan a fresh one.
      _mixing = false;
      _prepared = false;
      _plan = null;
    } else if (plan != null && from != null && target > plan.exitAt - 1) {
      _setPlan(_planner.retime(plan, from, target + 2));
    }
    _seconds = target;
    positionListenable.value = position;
    unawaited(
      _call('seek', {'seconds': target}).then((_) {
        if (wasMixing) unawaited(_prepareNext());
      }),
    );
  }

  @override
  void skip(int seconds) {
    final total = duration.inMicroseconds / 1e6;
    if (total <= 0) return;
    seek((_seconds + seconds) / total);
  }

  @override
  void next() {
    // With the next song lined up, Next is a short DJ mix on the next
    // downbeat; during a mix it completes it.
    if (canMixNow) {
      _mixSoon(beats: 8);
      return;
    }
    if (_mixing) {
      unawaited(_call('finishTransition'));
      return;
    }
    if (_index + 1 >= _queue.length) return;
    _index++;
    unawaited(_startCurrent(at: _plan?.entryAt ?? 0, play: _playing));
  }

  @override
  void previous() {
    if (_seconds > 3 || _index == 0) {
      seek(0);
      return;
    }
    _index--;
    unawaited(_startCurrent(play: _playing));
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_events.cancel());
    unawaited(_call('pause'));
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // ---- Engine ----

  Future<Object?> _call(String method, [Map<String, Object?>? args]) =>
      _methods.invokeMethod(method, args);

  void _onEvent(dynamic raw) {
    if (_disposed || raw is! Map) return;
    switch (raw['type']) {
      case 'tick':
        _seconds = (raw['position'] as num).toDouble();
        positionListenable.value = position;
        final playing = raw['playing'] == true;
        final settled =
            DateTime.now().difference(_commanded) >
            const Duration(milliseconds: 400);
        if (settled && playing != _playing && _queue.isNotEmpty) {
          _playing = playing;
          notifyListeners();
        }
      case 'mixStart':
        _mixing = true;
        _status = BeatSenseStatus(
          BeatSenseState.mixing,
          plan: _plan,
          next: _next,
          why: _status.why,
        );
        notifyListeners();
      case 'mixEnd':
        _onMixEnd();
      case 'ended':
        _mixing = false;
        if (_index + 1 < _queue.length) {
          _index++;
          unawaited(_startCurrent(play: true));
        } else {
          _playing = false;
          notifyListeners();
        }
      case 'paused':
        _playing = false;
        notifyListeners();
      case 'resumed':
        _playing = true;
        notifyListeners();
    }
  }

  void _onMixEnd() {
    final plan = _plan;
    _mixing = false;
    _prepared = false;
    _index = _next == null ? _index + 1 : _queue.indexOf(_next!, _index);
    if (_index < 0) _index = 0;
    _current = _next == null ? null : _analysis.cached(_next!);
    _duration = _nextDuration;
    if (plan != null) {
      _playedFrom = plan.entryAt + plan.length * plan.incomingRate;
      _shift = plan.incomingSemitones;
    }
    if (_djMode) _setIndex++;
    _plan = null;
    _next = null;
    _status = const BeatSenseStatus(BeatSenseState.analysing);
    notifyListeners();
    unawaited(_prepareNext());
  }

  Future<void> _startCurrent({double at = 0, bool play = false}) async {
    final generation = ++_generation;
    _cancelPlan();
    _mixing = false;
    _shift = 0;
    _playedFrom = at;
    _current = null;
    _seconds = at;
    final current = track!;
    final source = _sources[current.source];
    if (source == null) return;
    notifyListeners();
    try {
      final ref = await source.resolve(current);
      if (generation != _generation) return;
      final r = await _methods.invokeMapMethod<String, Object?>('loadMaster', {
        'uri': ref.uri.toString(),
        'headers': ref.headers,
        'at': at,
      });
      _duration = (r?['duration'] as num?)?.toDouble() ?? 0;
      await _call('setTone', {'semitones': 0.0});
    } catch (e) {
      debugPrint('Could not play ${current.title}: $e');
      if (generation != _generation) return;
      final failure = e is StreamFailure ? e : null;
      if (failure != null && failure.affectsAll) {
        message.value = failure.message;
        return;
      }
      message.value = failure != null
          ? '${failure.message} Skipping "${current.title}".'
          : 'Couldn\'t play "${current.title}". Skipping.';
      if (_index + 1 < _queue.length) {
        _index++;
        unawaited(_startCurrent(play: play));
      }
      return;
    }
    if (generation != _generation) return;
    if (play) this.play();
    notifyListeners();
    unawaited(_analyseCurrent(generation));
  }

  Future<void> _analyseCurrent(int generation) async {
    if (!_beatSense) return;
    _status = const BeatSenseStatus(BeatSenseState.analysing);
    notifyListeners();
    final a = await _analysis.analyse(track!);
    if (generation != _generation) return;
    _current = a;
    if (a != null && _plan == null) {
      await _call('setGain', {'deck': 'master', 'db': _planner.gainFor(a)});
    }
    await _prepareNext();
  }

  /// Picks and analyses the next song, plans the transition, loads the
  /// song on the other deck and hands the engine its script.
  Future<void> _prepareNext() async {
    if (!_beatSense || _prepared) return;
    final generation = _generation;
    final current = _current;
    if (current == null) {
      _status = const BeatSenseStatus(BeatSenseState.unavailable);
      notifyListeners();
      return;
    }

    if (_djMode) {
      await _djPickNext(current, generation);
    } else if (_index + 1 >= _queue.length) {
      await _extendQueue(current);
    }
    if (_index + 1 >= _queue.length || generation != _generation) return;

    final next = _queue[_index + 1];
    final nextAnalysis = await _analysis.analyse(next);
    if (generation != _generation) return;
    if (nextAnalysis == null) {
      _status = const BeatSenseStatus(BeatSenseState.unavailable);
      notifyListeners();
      return;
    }

    String? why;
    TransitionPlan plan;
    if (_djMode) {
      final move = _dj.plan(
        current,
        nextAnalysis,
        playedFrom: _playedFrom,
        setIndex: _setIndex,
        fromSemitones: _shift,
      );
      plan = move.plan;
      why = '${DjPlanner.whyPicked(current, nextAnalysis)}. ${move.why}.';
    } else {
      plan = _planner.plan(current, nextAnalysis, fromSemitones: _shift);
      if (plan.incomingSemitones != 0) {
        why =
            'Shifted ${plan.incomingSemitones > 0 ? 'up' : 'down'} a '
            'semitone so the keys mix in harmony.';
      }
    }
    if (_seconds > plan.exitAt - 1) {
      plan = _planner.retime(plan, current, _seconds + 2);
    }

    final source = _sources[next.source]!;
    try {
      final ref = await source.resolve(next);
      if (generation != _generation) return;
      final r = await _methods.invokeMapMethod<String, Object?>('loadNext', {
        'uri': ref.uri.toString(),
        'headers': ref.headers,
      });
      _nextDuration = (r?['duration'] as num?)?.toDouble() ?? 0;
    } catch (e) {
      debugPrint('Beat Sense: could not load ${next.title}: $e');
      _status = const BeatSenseStatus(BeatSenseState.unavailable);
      notifyListeners();
      return;
    }
    if (generation != _generation) return;
    await _call('setGain', {'deck': 'next', 'db': plan.incomingGainDb});
    await _call('setGain', {'deck': 'master', 'db': plan.outgoingGainDb});
    _next = next;
    _prepared = true;
    _setPlan(plan, why: why);
  }

  /// Records [plan] and sends it to the engine.
  void _setPlan(TransitionPlan plan, {String? why}) {
    _plan = plan;
    unawaited(_call('setTransition', MixScript.toEngine(plan)));
    _status = BeatSenseStatus(
      BeatSenseState.ready,
      plan: plan,
      next: _next,
      why: why ?? _status.why,
    );
    notifyListeners();
  }

  void _mixSoon({int? beats}) {
    final plan = _plan, from = _current;
    if (plan == null || from == null || _mixing || !_prepared) return;
    _setPlan(_planner.retime(plan, from, _seconds + 0.3, beats: beats));
  }

  void _cancelPlan() {
    _plan = null;
    _next = null;
    _prepared = false;
    unawaited(_call('clearTransition'));
  }

  /// DJ mode: looks at the next few queued songs and the current song's
  /// radio, analyses a handful, and moves the one that flows best to the
  /// front of the queue.
  Future<void> _djPickNext(TrackAnalysis current, int generation) async {
    final seed = track!;
    final played = {for (final t in _queue.take(_index + 1)) t.key};
    final pool = <Track>[..._queue.skip(_index + 1).take(3)];
    final source = _sources[seed.source];
    if (source != null) {
      try {
        pool.addAll(await source.related(seed));
      } catch (_) {}
    }
    final seen = <String>{};
    final fresh = [
      for (final t in pool)
        if (!played.contains(t.key) && seen.add(t.key)) t,
    ];
    final candidates = <Candidate<Track>>[];
    for (final t in fresh.take(6)) {
      final a = await _analysis.analyse(t);
      if (generation != _generation) return;
      if (a != null) {
        candidates.add(Candidate(item: t, analysis: a, artist: t.artist));
      }
      if (candidates.length >= 4) break;
    }
    final recent = _queue.reversed.take(4).map((t) => t.artist).toSet();
    final best = _dj.pick(
      current,
      seed.artist,
      candidates,
      setIndex: _setIndex,
      recentArtists: recent,
    );
    if (best == null || generation != _generation) return;
    final pick = best.candidate.item;
    _queue = [
      ..._queue.take(_index + 1),
      pick,
      ..._queue.skip(_index + 1).where((t) => t != pick),
    ];
  }

  /// At the end of the queue, keeps going with related songs.
  Future<void> _extendQueue(TrackAnalysis current) async {
    final seed = track!;
    final source = _sources[seed.source];
    if (source == null) return;
    List<Track> pool;
    try {
      pool = await source.related(seed);
      if (pool.isEmpty) pool = await source.library();
    } catch (_) {
      return;
    }
    final played = _queue.map((t) => t.key).toSet();
    final fresh = pool.where((t) => !played.contains(t.key)).take(12).toList();
    final candidates = <Candidate<Track>>[];
    for (final t in fresh) {
      final a = await _analysis.analyse(t);
      if (a != null) {
        candidates.add(Candidate(item: t, analysis: a, artist: t.artist));
      }
      if (candidates.length >= 5) break;
    }
    if (candidates.isEmpty) return;
    final recent = _queue.reversed.take(4).map((t) => t.artist).toSet();
    final best = _scorer
        .rank(current, seed.artist, candidates, recentArtists: recent)
        .first;
    _queue = [..._queue, best.candidate.item];
  }
}
