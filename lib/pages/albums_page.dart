import 'package:flutter/material.dart';

import '../library/library.dart';
import '../library/models.dart';
import '../playback/playback_controller.dart';
import '../widgets/ambient.dart';
import '../widgets/panorama.dart';
import '../widgets/tiles.dart';
import 'album_page.dart';

/// 2 · Albums — the hero album with its stats, then every album.
class AlbumsPage extends StatelessWidget {
  const AlbumsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final library = LibraryScope.of(context);
    final player = PlayerScope.of(context);
    final albums = library.albums;
    void play(Album a) => player.playTracks(a.tracks);
    void open(Album a, String place) =>
        AlbumPage.open(context, a, AlbumPage.tagFor(a, place));

    if (albums.isEmpty) {
      return const PanoramaPage(id: 'albums', title: 'albums');
    }
    final hero = albums.first;
    final rest = albums.skip(1).toList();

    return PanoramaPage(
      id: 'albums',
      title: 'albums',
      header: TileGrid(
        rows: [
          TileRow(height: 2, [
            TileColumn(span: 2, [
              Glint(
                delay: const Duration(seconds: 2),
                child: MetroTile(
                  art: hero.artwork,
                  label: hero.title,
                  caption: hero.artist,
                  selected: true,
                  heroTag: AlbumPage.tagFor(hero, 'albums-hero'),
                  onTap: () => open(hero, 'albums-hero'),
                  onLongPress: () => play(hero),
                ),
              ),
            ]),
            TileColumn([
              MetroTile(
                number: '${hero.songCount}',
                label: 'songs',
                onTap: () => play(hero),
              ),
              MetroTile(
                tone: TileTone.accent,
                number: '${hero.minutes}',
                label: 'minutes',
                onTap: () => player.playTracks(List.of(hero.tracks)..shuffle()),
              ),
            ]),
          ]),
        ],
      ),
      body: SliverList.separated(
        itemCount: rest.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (context, i) {
          final album = rest[i];
          final row = MediaRow(
            art: album.artwork,
            title: album.title,
            subtitle: '${album.artist} · ${album.songCount} songs',
            active: player.track != null && album.tracks.contains(player.track),
            heroTag: AlbumPage.tagFor(album, 'albums'),
            onTap: () => open(album, 'albums'),
            onLongPress: () => play(album),
          );
          return ColumnFocus(
            child: i < 6 ? Reveal(order: 3 + i, child: row) : row,
          );
        },
      ),
    );
  }
}
