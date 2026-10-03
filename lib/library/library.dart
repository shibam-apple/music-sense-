import 'package:flutter/widgets.dart';

import '../beat_sense/analysis/track_analysis.dart';
import '../sources/demo_source.dart';
import '../sources/music_source.dart';
import '../sources/youtube_music/youtube_music_source.dart';
import 'models.dart';
import 'stats.dart';

/// The listener's music from every enabled source, shaped for the pages:
/// recent songs, albums, singles, artists and streaming shelves.
class LibraryController extends ChangeNotifier {
  LibraryController(this.sources, {this.analysisOf}) {
    stats.addListener(notifyListeners);
  }

  final List<MusicSource> sources;

  /// Beat Sense analysis already computed for a track, if any.
  final TrackAnalysis? Function(Track track)? analysisOf;

  final stats = ListeningStats();

  List<Track> _tracks = DemoSource.tracks;
  List<(String, List<Track>)> _shelves = const [];
  List<Track> _charts = const [];
  bool _demo = true;
  bool _loading = false;

  bool get isDemo => _demo;
  bool get loading => _loading;
  List<Track> get tracks => _tracks;

  /// Streaming home shelves (title, songs), e.g. YouTube Music's.
  List<(String, List<Track>)> get shelves => _shelves;
  List<Track> get charts => _charts;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    final found = <Track>[];
    for (final source in sources) {
      try {
        if (!await source.open()) continue;
        if (source is YouTubeMusicSource) {
          _shelves = await source.home();
          found.addAll([for (final (_, songs) in _shelves) ...songs]);
          _charts = await source.charts();
        } else {
          found.addAll(await source.library());
        }
      } catch (e) {
        debugPrint('Library: ${source.name} unavailable: $e');
      }
    }
    _demo = found.isEmpty;
    _tracks = _demo ? DemoSource.tracks : _dedupe(found);
    _loading = false;
    _albums = null;
    notifyListeners();
  }

  List<Track> _dedupe(List<Track> tracks) {
    final seen = <String>{};
    return [
      for (final t in tracks)
        if (seen.add('${t.title.toLowerCase()}|${t.artist.toLowerCase()}')) t,
    ];
  }

  /// Newest first where dates are known; source order otherwise.
  List<Track> get recent {
    final dated = _tracks.where((t) => t.added != null).toList()
      ..sort((a, b) => b.added!.compareTo(a.added!));
    return dated.length == _tracks.length ? dated : _tracks;
  }

  List<Album>? _albums;

  /// Albums with more than one song, biggest first.
  List<Album> get albums => _albums ??= () {
        final groups = <String, List<Track>>{};
        for (final t in _tracks) {
          if (t.album == null) continue;
          groups.putIfAbsent('${t.album}|${t.artist}', () => []).add(t);
        }
        final list = [
          for (final g in groups.values)
            if (g.length > 1)
              Album(title: g.first.album!, artist: g.first.artist, tracks: g),
        ];
        // Keep the source's order (newest first for local files).
        return list;
      }();

  /// Songs that stand alone: no album, or the only song of theirs here.
  List<Track> get singles {
    final inAlbums = {for (final a in albums) ...a.tracks.map((t) => t.key)};
    return [for (final t in _tracks) if (!inAlbums.contains(t.key)) t];
  }

  List<Track> byArtist(String artist) =>
      [for (final t in _tracks) if (t.artist == artist) t];

  List<Track> addedSince(DateTime when) =>
      [for (final t in _tracks) if (t.added != null && t.added!.isAfter(when)) t];

  /// Songs for a mood, by Beat Sense's energy reading. Songs not yet
  /// analysed fill in (in a stable order) until enough are known.
  List<Track> moodMix(Mood mood, {int size = 40}) {
    final picked = <Track>[];
    final rest = <Track>[];
    for (final t in _tracks) {
      final energy = analysisOf?.call(t)?.energy;
      final fits = energy == null
          ? null
          : mood == Mood.chill
              ? energy < 0.45
              : energy > 0.62;
      if (fits == true) {
        picked.add(t);
      } else if (fits == null) {
        rest.add(t);
      }
    }
    if (_demo) {
      // Samples have no audio: go by their artwork's mood.
      final style = mood == Mood.chill ? ArtStyle.lake : ArtStyle.dust;
      return [for (final t in _tracks) if ((t.artwork as PaintedArtwork).style == style) t];
    }
    rest.sort((a, b) => (a.key.hashCode ^ mood.index).compareTo(b.key.hashCode ^ mood.index));
    return [...picked, ...rest].take(size).toList();
  }

  /// Artists with enough songs for a mix of their own.
  List<String> get mixArtists {
    final counts = <String, int>{};
    for (final t in _tracks) {
      counts[t.artist] = (counts[t.artist] ?? 0) + 1;
    }
    return [for (final e in counts.entries) if (e.value >= 3) e.key];
  }

  /// One song per day, stable for the whole day.
  Track? get songOfTheDay {
    if (_tracks.isEmpty) return null;
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch ~/ 86400000;
    return _tracks[day % _tracks.length];
  }
}

enum Mood { chill, energy }

class LibraryScope extends InheritedNotifier<LibraryController> {
  const LibraryScope({
    super.key,
    required LibraryController library,
    required super.child,
  }) : super(notifier: library);

  static LibraryController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LibraryScope>()!.notifier!;
}
