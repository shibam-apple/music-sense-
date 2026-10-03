/// Painted artwork styles used by the demo library and as fallbacks.
enum ArtStyle { futuristic, lake, dust }

/// Where a track's cover comes from.
sealed class ArtworkRef {
  const ArtworkRef();
}

/// Artwork painted in code (demo content and missing covers).
class PaintedArtwork extends ArtworkRef {
  const PaintedArtwork(this.style);
  final ArtStyle style;
}

/// Artwork at a URL (streaming services).
class NetworkArtwork extends ArtworkRef {
  const NetworkArtwork(this.url);
  final String url;
}

/// Artwork embedded in a local file, loaded by its MediaStore id.
class LocalArtwork extends ArtworkRef {
  const LocalArtwork(this.mediaId, {required this.fallback});
  final int mediaId;
  final ArtStyle fallback;
}

/// One playable song from any source.
class Track {
  const Track({
    required this.id,
    required this.source,
    required this.title,
    required this.artist,
    required this.artwork,
    this.album,
    this.duration = Duration.zero,
    this.year,
    this.added,
  });

  /// Unique within [source].
  final String id;

  /// The [MusicSource.id] that can play it.
  final String source;
  final String title;
  final String artist;
  final String? album;
  final ArtworkRef artwork;
  final Duration duration;
  final int? year;
  final DateTime? added;

  /// Unique across sources; used as the analysis cache key.
  String get key => '$source:$id';

  /// A stable fallback art style for this track.
  ArtStyle get fallbackStyle =>
      ArtStyle.values[title.hashCode.abs() % ArtStyle.values.length];

  @override
  bool operator ==(Object other) => other is Track && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

class Album {
  const Album({
    required this.title,
    required this.artist,
    required this.tracks,
  });

  final String title;
  final String artist;
  final List<Track> tracks;

  ArtworkRef get artwork => tracks.first.artwork;
  int get songCount => tracks.length;
  int get minutes =>
      tracks.fold(Duration.zero, (d, t) => d + t.duration).inMinutes;
}
