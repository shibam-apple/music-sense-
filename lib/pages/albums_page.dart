import 'package:flutter/material.dart';

import '../library/library.dart';
import '../library/models.dart';
import '../playback/playback_controller.dart';
import '../widgets/ambient.dart';
import '../widgets/panorama.dart';
import '../widgets/tiles.dart';

/// 2 · Albums — the hero album with its stats, then the album list.
class AlbumsPage extends StatelessWidget {
  const AlbumsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final library = LibraryScope.of(context);
    final player = PlayerScope.of(context);
    final albums = library.albums;
    void play(Album a) => player.playTracks(a.tracks);

    if (albums.isEmpty) {
      return const PanoramaPage(title: 'albums', content: SizedBox());
    }
    final hero = albums.first;

    return PanoramaPage(
      title: 'albums',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TileGrid(rows: [
            TileRow(height: 2, [
              TileColumn(span: 2, [
                Glint(
                  delay: const Duration(seconds: 2),
                  child: MetroTile(
                    art: hero.artwork,
                    label: hero.title,
                    caption: hero.artist,
                    selected: true,
                    onTap: () => play(hero),
                  ),
                ),
              ]),
              TileColumn([
                MetroTile(number: '${hero.songCount}', label: 'songs'),
                MetroTile(
                  tone: TileTone.accent,
                  number: '${hero.minutes}',
                  label: 'minutes',
                ),
              ]),
            ]),
          ]),
          const SizedBox(height: 16),
          for (final (i, album) in albums.skip(1).take(4).indexed) ...[
            if (i > 0) const SizedBox(height: 16),
            Reveal(order: 3 + i, child: _albumRow(album, () => play(album))),
          ],
        ],
      ),
      below: albums.length > 5 ? _albumRow(albums[5], null) : null,
    );
  }

  Widget _albumRow(Album album, VoidCallback? onTap) => MediaRow(
        art: album.artwork,
        title: album.title,
        subtitle: '${album.artist} · ${album.songCount} songs',
        onTap: onTap,
      );
}
