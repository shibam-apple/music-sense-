import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;

import '../beat_sense/analysis/track_analysis.dart';
import '../beat_sense/next_track.dart';
import '../beat_sense/transition.dart';
import '../library/models.dart';
import '../sources/music_source.dart';
import 'analysis_service.dart';
import 'deck.dart';
import 'playback_controller.dart';

/// Plays the queue on two decks and, with Beat Sense on, mixes each song
/// into the next: the incoming deck starts on a downbeat, runs at the
/// outgoing tempo, and the conductor drives volumes and the bass swap
/// every 30 ms, nudging speed to cancel drift.
class MixEngine extends PlaybackController {
  MixEngine({
    required this._sources,
    required this._analysis,
    this._planner = const TransitionPlanner(targetLoudnessDb: -18),
    this._scorer = const NextTrackScorer(),
  }) {
    for (final deck in _decks) {
      // Play/pause changes (including from headphones) refresh the pages.
      deck.audio.playingStream.listen((_) {
        if (deck == _active) notifyListeners();
      });
      deck.audio.processingStateStream.listen((state) {
        if (state == ProcessingState.completed && deck == _active && !_mixing) {
          _advance();
        }
      });
    }
  }

  final Map<String, MusicSource> _sources;
  final AnalysisService _analysis;
  final TransitionPlanner _planner;
  final NextTrackScorer _scorer;

  final _decks = [Deck(), Deck()];
  int _activeIndex = 0;
  Deck get _active => _decks[_activeIndex];
  Deck get _incoming => _decks[1 - _activeIndex];

  List<Track> _queue = const [];
  int _index = 0;
  bool _beatSense = true;
  BeatSenseStatus _status = BeatSenseStatus.off;

  TransitionPlan? _plan;
  bool _prepared = false;
  bool _mixing = false;
  bool _incomingStarted = false;
  double? _rampFrom;
  DateTime? _rampStart;
  double _rampSeconds = 0;
  int _generation = 0;

  Timer? _conductor;
  int _ticks = 0;
  bool _conducting = false;

  static const _tick = Duration(milliseconds: 30);

  /// Ignore drift below this (seconds); correct it by at most 2% speed.
  static const _driftTolerance = 0.012;

  @override
  Track? get track => _queue.isEmpty ? null : _queue[_index];
  @override
  List<Track> get queue => _queue;
  @override
  int get index => _index;
  @override
  Duration get position => _active.audio.position;
  @override
  Duration get duration =>
      _active.audio.duration ?? track?.duration ?? Duration.zero;
  @override
  bool get playing => _active.playing;
  @override
  TrackAnalysis? get analysis => _active.analysis;
  @override
  BeatSenseStatus get beatSense => _status;
  @override
  bool get beatSenseEnabled => _beatSense;

  @override
  set beatSenseEnabled(bool value) {
    if (_beatSense == value) return;
    _beatSense = value;
    if (!value) _cancelPlan();
    _status = value
        ? const BeatSenseStatus(BeatSenseState.analysing)
        : BeatSenseStatus.off;
    if (value) _prepareNext();
    notifyListeners();
  }

  @override
  Future<void> playTracks(List<Track> tracks, {int start = 0}) async {
    if (tracks.isEmpty) return;
    _queue = List.of(tracks);
    _index = start.clamp(0, tracks.length - 1);
    await _startCurrent();
  }

  Future<void> _startCurrent({double at = 0}) async {
    final generation = ++_generation;
    _cancelPlan();
    await _incoming.pause();
    final current = track!;
    final source = _sources[current.source];
    if (source == null) return;
    try {
      await _active.load(current, await source.resolve(current), at: at);
    } catch (e) {
      debugPrint('Could not play ${current.title}: $e');
      if (generation != _generation) return;
      message.value = source.id == 'ytm'
          ? 'YouTube wouldn\'t stream "${current.title}". Skipping.'
          : 'Couldn\'t play "${current.title}". Skipping.';
      if (_index + 1 < _queue.length) {
        _index++;
        unawaited(_startCurrent());
      }
      return;
    }
    if (generation != _generation) return;
    await _active.setLevel(1);
    _active.start();
    _ensureConductor();
    notifyListeners();
    _analyseCurrent(generation);
  }

  Future<void> _analyseCurrent(int generation) async {
    if (!_beatSense) return;
    _status = const BeatSenseStatus(BeatSenseState.analysing);
    notifyListeners();
    final deck = _active;
    final a = await _analysis.analyse(deck.track!);
    if (generation != _generation) return;
    deck.analysis = a;
    if (a != null && _plan == null) {
      await deck.applyGain(_planner.gainFor(a));
    }
    await _prepareNext();
  }

  /// Picks and analyses the next song and plans the transition into it.
  Future<void> _prepareNext() async {
    if (!_beatSense || _prepared) return;
    final generation = _generation;
    final current = _active.analysis;
    if (current == null) {
      _status = const BeatSenseStatus(BeatSenseState.unavailable);
      notifyListeners();
      return;
    }

    if (_index + 1 >= _queue.length) await _extendQueue(current);
    if (_index + 1 >= _queue.length || generation != _generation) return;

    final next = _queue[_index + 1];
    final nextAnalysis = await _analysis.analyse(next);
    if (generation != _generation) return;
    if (nextAnalysis == null) {
      _status = const BeatSenseStatus(BeatSenseState.unavailable);
      notifyListeners();
      return;
    }

    final plan = _planner.plan(current, nextAnalysis);
    final source = _sources[next.source]!;
    final deck = _incoming;
    try {
      await deck.load(next, await source.resolve(next), at: plan.entryAt);
    } catch (e) {
      debugPrint('Beat Sense: could not load ${next.title}: $e');
      _status = const BeatSenseStatus(BeatSenseState.unavailable);
      notifyListeners();
      return;
    }
    if (generation != _generation) return;
    deck.analysis = nextAnalysis;
    await deck.setLevel(0);
    await deck.setRate(plan.incomingRate);
    await deck.applyGain(plan.incomingGainDb);
    await _active.applyGain(plan.outgoingGainDb);

    _plan = plan;
    _prepared = true;
    _status = BeatSenseStatus(BeatSenseState.ready, plan: plan, next: next);
    notifyListeners();
  }

  /// At the end of the queue, Beat Sense keeps going: it asks the song's
  /// source for related songs and picks the one that mixes best.
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

  void _ensureConductor() {
    _conductor ??= Timer.periodic(_tick, (_) => _conduct());
  }

  Future<void> _conduct() async {
    if (_conducting) return;
    _conducting = true;
    try {
      await _conductStep();
    } finally {
      _conducting = false;
    }
  }

  Future<void> _conductStep() async {
    // ~10 position updates a second for the seek bar; pages don't rebuild.
    if (++_ticks % 3 == 0) positionListenable.value = _active.audio.position;
    _rampBack();

    final plan = _plan;
    if (plan == null || !_active.playing) return;
    final now = _active.seconds;

    // Start the incoming deck exactly on the exit downbeat.
    if (!_incomingStarted &&
        now >= plan.exitAt - _tick.inMicroseconds / 1e6 * 2) {
      if (now > plan.exitAt + 1) {
        // Seeked past the mix point: skip the blend for this song.
        _cancelPlan();
        return;
      }
      _incomingStarted = true;
      _mixing = true;
      final wait = Duration(microseconds: ((plan.exitAt - now) * 1e6).round());
      Future.delayed(wait.isNegative ? Duration.zero : wait, _incoming.start);
      _status = BeatSenseStatus(
        BeatSenseState.mixing,
        plan: plan,
        next: _incoming.track,
      );
      notifyListeners();
      return;
    }
    if (!_mixing) return;

    final progress = (now - plan.exitAt) / plan.length;
    final levels = plan.levelsAt(progress);
    await _active.setLevel(levels.outgoing);
    await _incoming.setLevel(levels.incoming);
    await _active.setBass(levels.outgoingBassDb);
    await _incoming.setBass(levels.incomingBassDb);

    if (plan.beatMatched && _incoming.playing) {
      final expected = plan.entryAt + (now - plan.exitAt) * plan.incomingRate;
      final drift = _incoming.seconds - expected;
      final correction = drift.abs() < _driftTolerance
          ? 0.0
          : (-drift * 0.5).clamp(-0.02, 0.02);
      await _incoming.setRate(plan.incomingRate * (1 + correction));
    }

    if (progress >= 1) await _finishMix(plan);
  }

  Future<void> _finishMix(TransitionPlan plan) async {
    final outgoing = _active;
    _activeIndex = 1 - _activeIndex;
    _index++;
    _mixing = false;
    _incomingStarted = false;
    _prepared = false;
    _plan = null;
    await outgoing.pause();
    await outgoing.setBass(0);
    await _active.setLevel(1);
    await _active.setBass(0);
    if (plan.rampBack > 0 && (plan.incomingRate - 1).abs() > 1e-3) {
      _rampFrom = plan.incomingRate;
      _rampStart = DateTime.now();
      _rampSeconds = plan.rampBack;
    }
    notifyListeners();
    _status = const BeatSenseStatus(BeatSenseState.analysing);
    unawaited(_prepareNext());
  }

  /// Eases the new song back to its own tempo after a tempo-matched mix.
  void _rampBack() {
    final from = _rampFrom, start = _rampStart;
    if (from == null || start == null || _mixing) return;
    final t =
        DateTime.now().difference(start).inMicroseconds / 1e6 / _rampSeconds;
    if (t >= 1) {
      _rampFrom = null;
      unawaited(_active.setRate(1));
      return;
    }
    unawaited(_active.setRate(from + (1 - from) * t));
  }

  void _cancelPlan() {
    _plan = null;
    _prepared = false;
    _incomingStarted = false;
    if (_mixing) {
      _mixing = false;
      unawaited(_incoming.pause());
      unawaited(_active.setLevel(1));
      unawaited(_active.setBass(0));
    }
  }

  void _advance() {
    if (_index + 1 >= _queue.length) return;
    _index++;
    unawaited(_startCurrent());
  }

  @override
  void play() {
    _active.start();
    if (_mixing) _incoming.start();
    _ensureConductor();
    notifyListeners();
  }

  @override
  void pause() {
    unawaited(_active.pause());
    if (_mixing) unawaited(_incoming.pause());
    notifyListeners();
  }

  @override
  void seek(double fraction) {
    final target = duration.inMicroseconds / 1e6 * fraction.clamp(0.0, 1.0);
    final plan = _plan;
    if (_mixing) _cancelPlan();
    if (plan != null && target > plan.exitAt) {
      _cancelPlan();
    }
    unawaited(
      _active.seek(target).then((_) {
        positionListenable.value = _active.audio.position;
      }),
    );
  }

  @override
  void skip(int seconds) {
    final total = duration.inMicroseconds / 1e6;
    if (total <= 0) return;
    seek((_active.seconds + seconds) / total);
  }

  @override
  void next() {
    if (_index + 1 >= _queue.length) return;
    _index++;
    unawaited(_startCurrent(at: _plan?.entryAt ?? 0));
  }

  @override
  void previous() {
    if (_active.seconds > 3 || _index == 0) {
      seek(0);
      return;
    }
    _index--;
    unawaited(_startCurrent());
  }

  @override
  void dispose() {
    _conductor?.cancel();
    for (final d in _decks) {
      unawaited(d.dispose());
    }
    super.dispose();
  }
}
