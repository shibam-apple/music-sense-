import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../library/library.dart';
import '../library/models.dart';
import '../playback/playback_controller.dart';
import 'account_page.dart';
import '../theme/tokens.dart';
import '../widgets/ambient.dart';
import '../widgets/panorama.dart';
import '../widgets/tiles.dart';

/// 3 · Featured — live tiles for radio, moods, mixes, charts and the
/// song of the day.
class FeaturedPage extends StatelessWidget {
  const FeaturedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final library = LibraryScope.of(context);
    final player = PlayerScope.of(context);
    final tracks = library.recent;
    final featured = player.track ?? (tracks.isEmpty ? null : tracks.first);
    final chill = library.moodMix(Mood.chill);
    final energy = library.moodMix(Mood.energy);
    final charts = library.charts.isNotEmpty ? library.charts : tracks;
    final daily = library.isDemo
        ? tracks.where((t) => t.title == 'Alpine Lake').firstOrNull
        : library.songOfTheDay;
    final fresh = library.addedSince(
      DateTime.now().subtract(const Duration(days: 7)),
    );
    // Artist mixes plus the two mood mixes.
    final mixes = library.isDemo ? 8 : library.mixArtists.length + 2;

    void play(List<Track> list, {bool shuffle = false}) {
      if (list.isEmpty) return;
      player.playTracks(shuffle ? (List.of(list)..shuffle()) : list);
    }

    ArtworkRef art(List<Track> list, ArtStyle fallback) =>
        list.isEmpty ? PaintedArtwork(fallback) : list.first.artwork;

    // More to explore under the tiles: streaming shelves, else the library.
    final more = [
      for (final (_, songs) in library.shelves) ...songs,
      if (library.shelves.isEmpty) ...tracks.skip(1),
    ];

    return PanoramaPage(
      id: 'featured',
      title: 'featured',
      header: TileGrid(
        rows: [
          TileRow(height: 2, [
            TileColumn(span: 2, [
              Glint(
                child: MetroTile(
                  art:
                      featured?.artwork ??
                      const PaintedArtwork(ArtStyle.futuristic),
                  label: featured?.title ?? '',
                  caption: 'Featured · ${featured?.byline ?? ''}',
                  onTap: featured == null ? null : () => play([featured]),
                ),
              ),
            ]),
            TileColumn([
              // Radio: Beat Sense keeps picking and mixing related songs.
              MetroTile(
                tone: TileTone.accent,
                icon: LucideIcons.radio300,
                label: 'Radio',
                caption: player.beatSenseEnabled
                    ? 'Live now'
                    : 'Beat Sense off',
                onTap: featured == null ? null : () => play([featured]),
              ),
              MetroTile(
                art: art(chill, ArtStyle.lake),
                label: 'Chill',
                onTap: () => play(chill, shuffle: true),
              ),
            ]),
          ]),
          TileRow([
            TileColumn([
              MetroTile(
                number: '$mixes',
                label: 'Mixes',
                onTap: () => play(tracks, shuffle: true),
              ),
            ]),
            TileColumn([
              MetroTile(
                art: art(energy, ArtStyle.dust),
                label: 'Energy',
                onTap: () => play(energy, shuffle: true),
              ),
            ]),
            TileColumn([
              MetroTile(
                tone: TileTone.light,
                icon: LucideIcons.chartNoAxesColumn300,
                label: 'Charts',
                caption: library.charts.isNotEmpty
                    ? 'Top ${charts.length}'
                    : 'Top 100',
                onTap: () => play(charts),
              ),
            ]),
          ]),
          TileRow([
            TileColumn(span: 3, [
              // The wide grey tile: YouTube Music sign-in while signed out,
              // then the Beat Sense switch (concerts on the sample library).
              if (library.youtube != null && !AccountScope.of(context).signedIn)
                MetroTile(
                  tone: TileTone.light,
                  icon: LucideIcons.logIn300,
                  label: 'Sign in to YouTube Music',
                  caption: 'Your liked songs, mixes and streams',
                  onTap: () => signInToYouTube(context),
                )
              else if (library.isDemo)
                const MetroTile(
                  tone: TileTone.light,
                  icon: LucideIcons.ticket300,
                  label: 'Concerts near you',
                  caption: 'Rufus Stewart · Sep 11',
                )
              else
                MetroTile(
                  tone: TileTone.light,
                  icon: LucideIcons.audioWaveform300,
                  label: 'Beat Sense',
                  caption: player.beatSenseEnabled
                      ? 'On · mixing songs together'
                      : 'Off · tap to mix songs together',
                  onTap: () =>
                      player.beatSenseEnabled = !player.beatSenseEnabled,
                ),
            ]),
          ]),
          TileRow([
            TileColumn(span: 2, [
              MetroTile(
                art: daily?.artwork ?? const PaintedArtwork(ArtStyle.lake),
                label: daily?.title ?? '',
                caption: 'Song of the day',
                onTap: daily == null ? null : () => play([daily]),
              ),
            ]),
            TileColumn([
              MetroTile(
                tone: TileTone.accent,
                number: library.isDemo ? '+3' : '+${fresh.length}',
                label: 'New',
                onTap: () => play(fresh),
              ),
            ]),
          ]),
        ],
      ),
      body: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: MsSizes.tileGap,
          crossAxisSpacing: MsSizes.tileGap,
        ),
        // One quiet row under the tiles, as in the design.
        itemCount: more.length.clamp(0, 3),
        itemBuilder: (context, i) {
          final t = more[i];
          return MetroTile(
            art: t.artwork,
            label: t.title,
            caption: t.byline,
            onTap: () => player.playTracks(more, start: i),
          );
        },
      ),
    );
  }
}
