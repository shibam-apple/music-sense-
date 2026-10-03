import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/library.dart';
import '../widgets/panorama.dart';
import '../widgets/tiles.dart';

/// 3 · Featured — live tiles for radio, moods, mixes, charts and concerts.
class FeaturedPage extends StatelessWidget {
  const FeaturedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PanoramaPage(
      title: 'featured',
      content: TileGrid(rows: [
        TileRow(height: 2, [
          TileColumn(span: 2, [
            MetroTile(
              art: ArtStyle.futuristic,
              label: 'Futuristic',
              caption: 'Featured · Rufus Stewart',
            ),
          ]),
          TileColumn([
            MetroTile(
              tone: TileTone.accent,
              icon: LucideIcons.radio300,
              label: 'Radio',
              caption: 'Live now',
            ),
            MetroTile(art: ArtStyle.lake, label: 'Chill'),
          ]),
        ]),
        TileRow([
          TileColumn([MetroTile(number: '8', label: 'Mixes')]),
          TileColumn([MetroTile(art: ArtStyle.dust, label: 'Energy')]),
          TileColumn([
            MetroTile(
              tone: TileTone.light,
              icon: LucideIcons.chartNoAxesColumn300,
              label: 'Charts',
              caption: 'Top 100',
            ),
          ]),
        ]),
        TileRow([
          TileColumn(span: 3, [
            MetroTile(
              tone: TileTone.light,
              icon: LucideIcons.ticket300,
              label: 'Concerts near you',
              caption: 'Rufus Stewart · Sep 11',
            ),
          ]),
        ]),
        TileRow([
          TileColumn(span: 2, [
            MetroTile(
              art: ArtStyle.lake,
              label: 'Alpine Lake',
              caption: 'Song of the day',
            ),
          ]),
          TileColumn([
            MetroTile(tone: TileTone.accent, number: '+3', label: 'New'),
          ]),
        ]),
      ]),
      below: TileGrid(rows: [
        TileRow([
          TileColumn([MetroTile(art: ArtStyle.dust)]),
          TileColumn([MetroTile(art: ArtStyle.lake)]),
          TileColumn([MetroTile(art: ArtStyle.futuristic)]),
        ]),
      ]),
    );
  }
}
