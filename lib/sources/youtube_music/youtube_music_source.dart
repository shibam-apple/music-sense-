import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../library/models.dart';
import '../music_source.dart';
import 'innertube.dart';

/// Whether this build includes YouTube Music. The Play Store build passes
/// `--dart-define=YT_MUSIC=false`, which removes the plugin entirely.
const kYouTubeMusicEnabled = bool.fromEnvironment(
  'YT_MUSIC',
  defaultValue: true,
);

/// YouTube Music through its unofficial API. Optional and off the Play
/// Store build: it relies on YouTube internals that change without notice.
class YouTubeMusicSource extends MusicSource {
  YouTubeMusicSource({InnerTubeClient? client, YoutubeExplode? explode})
    : _api = client ?? InnerTubeClient(),
      _yt = explode ?? YoutubeExplode();

  final InnerTubeClient _api;
  final YoutubeExplode _yt;

  /// Stream URLs expire after a few hours; cache them briefly.
  final _streams = <String, (StreamRef, DateTime)>{};

  @override
  String get id => 'ytm';

  @override
  String get name => 'YouTube Music';

  /// Home shelves for the Featured and New pages. Signed out, YouTube
  /// Music's home lists playlists; each shelf takes its first playlist's
  /// songs.
  Future<List<(String, List<Track>)>> home({int maxShelves = 5}) async {
    final shelves = InnerTubeParser.shelves(await _api.home()).take(maxShelves);
    final filled = await Future.wait(
      shelves.map((s) async {
        if (s.songs.isNotEmpty) return (s.title, s.songs.map(_track).toList());
        if (s.playlists.isEmpty) return (s.title, <Track>[]);
        return (s.title, await playlist(s.playlists.first));
      }),
    );
    return [
      for (final f in filled)
        if (f.$2.isNotEmpty) f,
    ];
  }

  /// Top songs: the charts page links to chart playlists.
  Future<List<Track>> charts() async {
    final raw = await _api.charts();
    final direct = InnerTubeParser.songs(raw).map(_track).toList();
    if (direct.length >= 10) return direct;
    final lists = InnerTubeParser.playlists(raw);
    if (lists.isEmpty) return direct;
    return playlist(lists.first);
  }

  Future<List<Track>> playlist(String browseId) async =>
      InnerTubeParser.songs(await _api.browse(browseId)).map(_track).toList();

  /// Without sign-in there is no personal library; the home feed's songs
  /// stand in for it.
  @override
  Future<List<Track>> library() async => [
    for (final (_, tracks) in await home()) ...tracks,
  ];

  @override
  Future<List<Track>> search(String query) async =>
      InnerTubeParser.songs(await _api.searchSongs(query)).map(_track).toList();

  @override
  Future<List<Track>> related(Track seed) async =>
      InnerTubeParser.songs(await _api.radio(seed.id))
          .where((s) => s.videoId != seed.id)
          .map(_track)
          .toList();

  /// Clients to ask for streams, best first. YouTube regularly blocks one
  /// or another, so each is tried in turn and the last one that worked is
  /// tried first next time.
  static final clients = <YoutubeApiClient>[
    YoutubeApiClient.androidSdkless,
    YoutubeApiClient.tv,
    YoutubeApiClient.androidVr,
    YoutubeApiClient.ios,
    YoutubeApiClient.androidMusic,
    YoutubeApiClient.mweb,
    YoutubeApiClient.safari,
  ];
  YoutubeApiClient? _working;

  @override
  Future<StreamRef> resolve(Track track) async {
    final cached = _streams[track.id];
    if (cached != null && DateTime.now().isBefore(cached.$2)) return cached.$1;

    final order = [?_working, ...clients.where((c) => c != _working)];
    Object? lastError;
    for (final client in order) {
      try {
        final manifest = await _yt.videos.streamsClient.getManifest(
          track.id,
          ytClients: [client],
        );
        if (manifest.audioOnly.isEmpty) continue;
        // Prefer AAC (mp4) for the widest decoder support, else the best Opus.
        final audio = manifest.audioOnly.where(
          (s) => s.container == StreamContainer.mp4,
        );
        final best = (audio.isNotEmpty ? audio : manifest.audioOnly)
            .withHighestBitrate();
        // Stream URLs are tied to the client that asked; fetch them the same way.
        final agent =
            (client.payload['context']?['client']?['userAgent']) as String?;
        final ref = StreamRef(best.url, headers: {'User-Agent': ?agent});
        _working = client;
        _streams[track.id] = (
          ref,
          DateTime.now().add(const Duration(hours: 4)),
        );
        return ref;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? StateError('No stream for ${track.id}');
  }

  /// Which clients can stream [videoId] right now; for diagnostics.
  Future<Map<String, String>> probe(String videoId) async {
    final out = <String, String>{};
    for (final client in clients) {
      final name = client.payload['context']['client']['clientName'] as String;
      try {
        final m = await _yt.videos.streamsClient.getManifest(
          videoId,
          ytClients: [client],
        );
        out[name] = 'ok: ${m.audioOnly.length} audio streams';
      } catch (e) {
        out[name] = 'failed: ${e.toString().split('\n').first}';
      }
    }
    return out;
  }

  Track _track(YtSong s) => Track(
    id: s.videoId,
    source: id,
    title: s.title,
    artist: s.artist,
    album: s.album,
    duration: s.duration ?? Duration.zero,
    artwork: s.thumbnail != null
        ? NetworkArtwork(s.thumbnail!)
        : PaintedArtwork(ArtStyle.values[s.title.hashCode.abs() % 3]),
  );

  void close() {
    _api.close();
    _yt.close();
  }
}
