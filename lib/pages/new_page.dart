import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../library/library.dart';
import '../library/models.dart';
import '../playback/playback_controller.dart';
import '../theme/tokens.dart';
import '../widgets/ambient.dart';
import '../widgets/panorama.dart';
import '../widgets/tiles.dart';
import 'album_page.dart';

/// 4 · New — new releases, listening stats and the yearly replay.
class NewPage extends StatelessWidget {
  const NewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final library = LibraryScope.of(context);
    final player = PlayerScope.of(context);
    final year = DateTime.now().year;

    // Albums ordered by their newest song.
    DateTime newest(Album a) => a.tracks
        .map((t) => t.added ?? DateTime(1970))
        .reduce((x, y) => x.isAfter(y) ? x : y);
    final albums = library.isDemo
        ? library.albums
        : ([...library.albums]..sort((a, b) => newest(b).compareTo(newest(a))));
    final singles = library.singles;
    final week = library.addedSince(
      DateTime.now().subtract(const Duration(days: 7)),
    );
    final hours = library.isDemo ? 42 : library.stats.hoursThisMonth.round();
    final replay = library.stats.topOf(library.tracks);

    void play(List<Track> list) {
      if (list.isNotEmpty) player.playTracks(list);
    }

    void open(Album a) =>
        AlbumPage.open(context, a, AlbumPage.tagFor(a, 'new'));

    final hero = albums.isNotEmpty ? albums.first : null;
    final second = albums.length > 1 ? albums[1] : null;
    final latestSingle = singles.isNotEmpty
        ? singles.first
        : library.recent.firstOrNull;

    final older = albums.skip(2).toList();

    return PanoramaPage(
      id: 'new',
      title: 'new',
      header: TileGrid(
        rows: [
          TileRow(height: 1.64, [
            TileColumn(span: 3, [
              Glint(
                delay: const Duration(seconds: 3),
                child: MetroTile(
                  art: hero?.artwork ?? const PaintedArtwork(ArtStyle.lake),
                  label: hero?.title ?? '',
                  caption: hero == null ? null : 'New album · ${hero.artist}',
                  heroTag: hero == null ? null : AlbumPage.tagFor(hero, 'new'),
                  onTap: hero == null ? null : () => open(hero),
                  onLongPress: hero == null ? null : () => play(hero.tracks),
                ),
              ),
            ]),
          ]),
          TileRow(height: 1.5, [
            TileColumn(span: 1.5, [
              MetroTile(
                tone: TileTone.accent,
                number: '$hours',
                label: 'hours played',
                caption: 'this month',
              ),
            ]),
            TileColumn(span: 1.5, [
              MetroTile(
                art: second?.artwork ?? const PaintedArtwork(ArtStyle.dust),
                label: second?.title ?? '',
                caption: second?.artist,
                heroTag: second == null
                    ? null
                    : AlbumPage.tagFor(second, 'new'),
                onTap: second == null ? null : () => open(second),
                onLongPress: second == null ? null : () => play(second.tracks),
              ),
            ]),
          ]),
          TileRow([
            TileColumn([
              MetroTile(
                number: library.isDemo ? '6' : '${singles.length}',
                label: 'Singles',
                onTap: () => play(singles),
              ),
            ]),
            TileColumn([
              MetroTile(
                art:
                    latestSingle?.artwork ??
                    const PaintedArtwork(ArtStyle.futuristic),
                onTap: latestSingle == null ? null : () => play([latestSingle]),
              ),
            ]),
            TileColumn([
              library.isDemo
                  ? const MetroTile(
                      tone: TileTone.light,
                      number: '2',
                      label: 'Pre-saves',
                    )
                  : MetroTile(
                      tone: TileTone.light,
                      number: '${week.length}',
                      label: 'This week',
                      onTap: () => play(week),
                    ),
            ]),
          ]),
          TileRow([
            TileColumn(span: 3, [
              MetroTile(
                icon: LucideIcons.loaderPinwheel300,
                label: 'Your $year Replay',
                caption: 'Updated weekly',
                onTap: () => play(replay.isNotEmpty ? replay : library.recent),
              ),
            ]),
          ]),
        ],
      ),
      body: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: MsSizes.tileGap,
          crossAxisSpacing: MsSizes.tileGap,
          childAspectRatio: 1.5,
        ),
        itemCount: older.length.clamp(0, 2),
        itemBuilder: (context, i) {
          final a = older[i];
          return MetroTile(
            art: a.artwork,
            label: a.title,
            caption: a.artist,
            heroTag: AlbumPage.tagFor(a, 'new'),
            onTap: () => open(a),
            onLongPress: () => play(a.tracks),
          );
        },
      ),
    );
  }
}
