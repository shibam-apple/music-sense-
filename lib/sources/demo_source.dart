import '../library/models.dart';
import 'music_source.dart';

/// The design's sample library: shown on the web preview, in tests, and
/// on a phone until real sources have songs.
class DemoSource extends MusicSource {
  @override
  String get id => 'demo';

  @override
  String get name => 'Samples';

  static Track _t(String title, String artist, ArtStyle art,
          {String? album, int seconds = 200, required int daysAgo}) =>
      Track(
        id: title,
        source: 'demo',
        title: title,
        artist: artist,
        album: album,
        artwork: PaintedArtwork(art),
        duration: Duration(seconds: seconds),
        added: DateTime(2026, 10, 1).subtract(Duration(days: daysAgo)),
      );

  /// Album order matches the design (Tidelines first); dates put the
  /// design's "music collection" songs first in the recent list.
  static final tracks = () {
    var age = 10;
    Track filler(String title, String artist, ArtStyle art, String album, {int seconds = 200}) =>
        _t(title, artist, art, album: album, seconds: seconds, daysAgo: age++);
    const roman = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX'];
    return [
      _t('Alpine Lake', 'Mara Eon', ArtStyle.lake, album: 'Tidelines', seconds: 228, daysAgo: 1),
      for (final r in roman) filler('Tidelines $r', 'Mara Eon', ArtStyle.lake, 'Tidelines', seconds: 228),
      _t('Golden Hour Ride', 'Kiro Vale', ArtStyle.dust, album: 'Glass Coast', daysAgo: 2),
      _t('Dust Trails', 'Kiro Vale', ArtStyle.dust, album: 'Glass Coast', daysAgo: 3),
      for (var i = 1; i <= 10; i++) filler('Glass Coast $i', 'Kiro Vale', ArtStyle.dust, 'Glass Coast'),
      for (final (title, artist, art, n) in const [
        ('Paper Moons', 'Oto Ren', ArtStyle.futuristic, 8),
        ('Lantern Season', 'Ines Hale', ArtStyle.lake, 11),
        ('Static Bloom', 'Kiro Vale', ArtStyle.dust, 9),
        ('North Window', 'Mara Eon', ArtStyle.futuristic, 10),
      ])
        for (var i = 1; i <= n; i++) filler('$title $i', artist, art, title),
      _t('Futuristic', 'Rufus Stewart', ArtStyle.futuristic, album: 'Vol. 01', daysAgo: 0),
      _t('Futuristic (Reprise)', 'Rufus Stewart', ArtStyle.futuristic, album: 'Vol. 01', daysAgo: 4),
    ];
  }();

  @override
  Future<List<Track>> library() async => tracks;

  @override
  Future<StreamRef> resolve(Track track) =>
      throw UnsupportedError('Samples have no audio');
}
