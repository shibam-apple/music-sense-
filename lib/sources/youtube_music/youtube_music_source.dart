import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../library/models.dart';
import '../music_source.dart';
import 'innertube.dart';

/// Whether this build includes YouTube Music. The Play Store build passes
/// `--dart-define=YT_MUSIC=false`, which removes the plugin entirely.
const kYouTubeMusicEnabled = bool.fromEnvironment('YT_MUSIC', defaultValue: true);

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

  /// Home and charts shelves, for the Featured and New pages.
  Future<List<(String, List<Track>)>> home() async {
    final shelves = InnerTubeParser.shelves(await _api.home());
    return [for (final s in shelves) (s.title, s.songs.map(_track).toList())];
  }

  Future<List<Track>> charts() async =>
      InnerTubeParser.songs(await _api.charts()).map(_track).toList();

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

  @override
  Future<StreamRef> resolve(Track track) async {
    final cached = _streams[track.id];
    if (cached != null && DateTime.now().isBefore(cached.$2)) return cached.$1;

    final manifest = await _yt.videos.streamsClient.getManifest(
      track.id,
      ytClients: [YoutubeApiClient.androidVr, YoutubeApiClient.ios],
    );
    // Prefer AAC (mp4) for the widest decoder support, else the best Opus.
    final audio = manifest.audioOnly.where((s) => s.container == StreamContainer.mp4);
    final best = (audio.isNotEmpty ? audio : manifest.audioOnly).withHighestBitrate();
    final ref = StreamRef(best.url);
    _streams[track.id] = (ref, DateTime.now().add(const Duration(hours: 4)));
    return ref;
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
