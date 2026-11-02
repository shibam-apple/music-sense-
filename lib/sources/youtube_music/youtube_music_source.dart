import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../library/models.dart';
import '../local_source.dart';
import '../music_source.dart';
import 'account.dart';
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
  YouTubeMusicSource({
    this.account,
    InnerTubeClient? client,
    YoutubeExplode? explode,
  }) : _api = client ?? InnerTubeClient(auth: account?.headers),
       _yt =
           explode ??
           YoutubeExplode(
             httpClient: account == null
                 ? null
                 : YoutubeHttpClient(SignedInClient(account)),
           );

  /// The user's sign-in, if any: personal home, liked songs, and streams
  /// that YouTube only serves to signed-in users.
  final YouTubeAccount? account;

  bool get signedIn => account?.signedIn ?? false;

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
    // Prefer a songs chart over the music-videos one.
    final items = InnerTubeParser.playlistItems(raw);
    if (items.isEmpty) return direct;
    final songs = items.where((e) => e.$2.toLowerCase().contains('song'));
    return playlist((songs.isNotEmpty ? songs.first : items.first).$1);
  }

  Future<List<Track>> playlist(String browseId) async =>
      InnerTubeParser.songs(await _api.browse(browseId)).map(_track).toList();

  /// Signed in: liked songs first, then the home feed. Signed out: the
  /// home feed's songs stand in for a library.
  @override
  Future<List<Track>> library() async => [
    if (signedIn) ...await likedSongs(),
    for (final (_, tracks) in await home()) ...tracks,
  ];

  Future<List<Track>> likedSongs() async {
    if (!signedIn) return const [];
    return InnerTubeParser.songs(await _api.likedSongs()).map(_track).toList();
  }

  /// Fills in the account's name and photo after sign-in.
  Future<void> refreshProfile() async {
    final a = account;
    if (a == null || !a.signedIn) return;
    try {
      final p = InnerTubeParser.profile(await _api.accountMenu());
      a.setProfile(name: p.name, handle: p.handle, photo: p.photo);
    } catch (e) {
      debugPrint('YouTube Music: profile unavailable: $e');
    }
  }

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

  /// The real platform (tests report Android as their target platform but
  /// have no native side).
  static bool get _onAndroid => !kIsWeb && Platform.isAndroid;

  /// Songs being fetched right now, so the player and Beat Sense share one
  /// download.
  final _fetching = <String, Future<StreamRef>>{};

  @override
  Future<StreamRef> resolve(Track track) {
    final cached = _streams[track.id];
    if (cached != null && DateTime.now().isBefore(cached.$2)) {
      return Future.value(cached.$1);
    }
    return _fetching.putIfAbsent(track.id, () async {
      try {
        final ref = await _resolve(track);
        _streams[track.id] = (
          ref,
          DateTime.now().add(const Duration(hours: 4)),
        );
        return ref;
      } finally {
        _fetching.remove(track.id);
      }
    });
  }

  Future<StreamRef> _resolve(Track track) async {
    if (!_onAndroid) return _resolveExplode(track);
    // On the phone: NewPipe Extractor finds the stream and the song is
    // downloaded to the cache, then plays like a local file.
    try {
      final r = await LocalSource.channel.invokeMapMethod<String, Object?>(
        'youtubeFetch',
        {'id': track.id, 'cookies': account?.cookieHeader},
      );
      return StreamRef(Uri.file(r!['path']! as String));
    } on PlatformException catch (e) {
      final failure = StreamFailure(
        e.message ?? 'YouTube wouldn\'t play this song.',
        kind: e.code,
      );
      // These are about the song itself; another client won't help.
      const songSpecific = {
        'premium',
        'age',
        'region',
        'private',
        'paid',
        'network',
      };
      if (songSpecific.contains(e.code)) throw failure;
      debugPrint('YouTube Music: NewPipe failed (${e.code}), trying fallback');
      try {
        return await _resolveExplode(track);
      } catch (_) {
        throw failure;
      }
    }
  }

  /// The older path: youtube_explode stream URLs, client by client.
  Future<StreamRef> _resolveExplode(Track track) async {
    // Signed in, the TV client goes first: it honours the session, which
    // gets past YouTube's "confirm you're not a bot" check.
    final preferred = signedIn ? [YoutubeApiClient.tv, ...clients] : clients;
    final order = [?_working, ...preferred.where((c) => c != _working)];
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
        _working = client;
        return StreamRef(best.url, headers: {'User-Agent': ?agent});
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? StateError('No stream for ${track.id}');
  }

  /// A step-by-step report on playing [videoId] from this phone, for the
  /// YouTube check on the Account page.
  Future<String> diagnose(String videoId) async {
    if (_onAndroid) {
      try {
        return await LocalSource.channel.invokeMethod<String>(
              'youtubeDiagnose',
              {'id': videoId, 'cookies': account?.cookieHeader},
            ) ??
            '';
      } on PlatformException catch (e) {
        return 'failed: ${e.message}';
      }
    }
    final p = await probe(videoId);
    return p.entries.map((e) => '${e.key}: ${e.value}').join('\n');
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
