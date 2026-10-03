import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../library/models.dart';
import '../library/names.dart';
import 'music_source.dart';

/// Songs stored on the device, read from Android's media library.
class LocalSource extends MusicSource {
  static const channel = MethodChannel('music_sense/media');

  @override
  String get id => 'local';

  @override
  String get name => 'On this phone';

  @override
  Future<bool> open() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    // Android 13+ asks for audio; older versions for storage.
    return await channel.invokeMethod<bool>('requestAudioPermission') ?? false;
  }

  @override
  Future<List<Track>> library() async {
    final rows = await channel.invokeListMethod<Map>('queryAudio') ?? const [];
    return [for (final r in rows) _track(r)];
  }

  Track _track(Map r) {
    final id = (r['id'] as num).toInt();
    final (title, tagged) = splitArtist(
      tidyTitle((r['title'] as String?) ?? 'Unknown'),
      _clean(r['artist'] as String?),
    );
    final artist = tagged ?? unknownArtist;
    final year = (r['year'] as num?)?.toInt();
    final added = (r['dateAdded'] as num?)?.toInt();
    return Track(
      id: '$id',
      source: this.id,
      title: title,
      artist: artist,
      album: _clean(r['album'] as String?),
      duration: Duration(milliseconds: (r['durationMs'] as num).toInt()),
      year: year == null || year == 0 ? null : year,
      added: added == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(added * 1000),
      artwork: LocalArtwork(
        id,
        fallback:
            ArtStyle.values[title.hashCode.abs() % ArtStyle.values.length],
      ),
    );
  }

  /// MediaStore reports missing tags as `<unknown>`.
  String? _clean(String? value) =>
      value == null || value.isEmpty || value == '<unknown>' ? null : value;

  @override
  Future<StreamRef> resolve(Track track) async =>
      StreamRef(Uri.parse('content://media/external/audio/media/${track.id}'));

  /// JPEG cover bytes for a local song, or null.
  static Future<Uint8List?> artwork(int mediaId, {int size = 512}) =>
      channel.invokeMethod<Uint8List>('artwork', {'id': mediaId, 'size': size});
}
