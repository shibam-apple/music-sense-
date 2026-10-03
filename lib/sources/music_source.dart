import '../library/models.dart';

/// Where to fetch a track's audio from.
class StreamRef {
  const StreamRef(this.uri, {this.headers = const {}});

  final Uri uri;
  final Map<String, String> headers;
}

/// A provider of tracks: the device's files, a streaming service, …
/// Sources are plugins; the app works with whichever are enabled.
abstract class MusicSource {
  /// Short stable id, stored in [Track.source].
  String get id;

  /// Shown to the listener.
  String get name;

  /// Prepares the source (permissions, sessions). Returns false when the
  /// source cannot be used right now.
  Future<bool> open() async => true;

  /// The listener's tracks from this source.
  Future<List<Track>> library();

  Future<List<Track>> search(String query) async => const [];

  /// Songs that would follow [seed] well (a radio), used as Beat Sense
  /// candidates. Empty when the source has no recommendations.
  Future<List<Track>> related(Track seed) async => const [];

  Future<StreamRef> resolve(Track track);
}
