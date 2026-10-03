/// The artwork styles the mock library uses. Real artwork will come from
/// file tags or the streaming service; until then each style is painted.
enum ArtStyle { futuristic, lake, dust }

class Song {
  const Song({
    required this.title,
    required this.artist,
    required this.art,
    this.album,
    this.duration = const Duration(minutes: 3, seconds: 20),
  });

  final String title;
  final String artist;
  final String? album;
  final ArtStyle art;
  final Duration duration;
}

class Album {
  const Album({
    required this.title,
    required this.artist,
    required this.art,
    required this.songCount,
    this.minutes = 0,
  });

  final String title;
  final String artist;
  final ArtStyle art;
  final int songCount;
  final int minutes;
}

/// Mock data matching the design file, used until the real library lands.
abstract final class MockLibrary {
  static const futuristic = Song(
    title: 'Futuristic',
    artist: 'Rufus Stewart',
    album: 'Vol. 01',
    art: ArtStyle.futuristic,
    duration: Duration(minutes: 3, seconds: 20),
  );

  static const recentArt = [
    ArtStyle.futuristic,
    ArtStyle.lake,
    ArtStyle.dust,
    ArtStyle.lake,
    ArtStyle.futuristic,
    ArtStyle.dust,
    ArtStyle.lake,
  ];

  static const songs = [
    Song(title: 'Alpine Lake', artist: 'Mara Eon', art: ArtStyle.lake),
    Song(title: 'Golden Hour Ride', artist: 'Kiro Vale', art: ArtStyle.dust),
    Song(title: 'Dust Trails', artist: 'Kiro Vale', art: ArtStyle.dust),
    Song(
      title: 'Futuristic (Reprise)',
      artist: 'Rufus Stewart',
      art: ArtStyle.futuristic,
    ),
  ];

  static const heroAlbum = Album(
    title: 'Tidelines',
    artist: 'Mara Eon',
    art: ArtStyle.lake,
    songCount: 10,
    minutes: 38,
  );

  static const albums = [
    Album(
        title: 'Glass Coast',
        artist: 'Kiro Vale',
        art: ArtStyle.dust,
        songCount: 12),
    Album(
        title: 'Paper Moons',
        artist: 'Oto Ren',
        art: ArtStyle.futuristic,
        songCount: 8),
    Album(
        title: 'Lantern Season',
        artist: 'Ines Hale',
        art: ArtStyle.lake,
        songCount: 11),
    Album(
        title: 'Static Bloom',
        artist: 'Kiro Vale',
        art: ArtStyle.dust,
        songCount: 9),
    Album(
        title: 'North Window',
        artist: 'Mara Eon',
        art: ArtStyle.futuristic,
        songCount: 10),
  ];

  static const upNext = [
    Song(title: 'Alpine Lake', artist: 'Mara Eon', art: ArtStyle.lake),
    Song(title: 'Golden Hour Ride', artist: 'Kiro Vale', art: ArtStyle.dust),
  ];
}
