import 'package:flutter/material.dart';

import '../data/library.dart';
import '../widgets/panorama.dart';
import '../widgets/tiles.dart';

/// 2 · Albums — the hero album with its stats, then the album list.
class AlbumsPage extends StatelessWidget {
  const AlbumsPage({super.key});

  @override
  Widget build(BuildContext context) {
    const hero = MockLibrary.heroAlbum;
    final albums = MockLibrary.albums;

    return PanoramaPage(
      title: 'albums',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TileGrid(rows: [
            TileRow(height: 2, [
              TileColumn(span: 2, [
                MetroTile(
                  art: hero.art,
                  label: hero.title,
                  caption: hero.artist,
                  selected: true,
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
          for (final (i, album) in albums.take(4).indexed) ...[
            if (i > 0) const SizedBox(height: 16),
            Reveal(order: 3 + i, child: _albumRow(album)),
          ],
        ],
      ),
      below: _albumRow(albums.last),
    );
  }

  Widget _albumRow(Album album) => MediaRow(
        art: album.art,
        title: album.title,
        subtitle: '${album.artist} · ${album.songCount} songs',
      );
}
