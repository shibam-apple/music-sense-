import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/library.dart';
import '../widgets/panorama.dart';
import '../widgets/tiles.dart';

/// 4 · New — new releases, listening stats and the yearly replay.
class NewPage extends StatelessWidget {
  const NewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;

    return PanoramaPage(
      title: 'new',
      content: TileGrid(rows: [
        const TileRow(height: 1.64, [
          TileColumn(span: 3, [
            MetroTile(
              art: ArtStyle.lake,
              label: 'Tidelines',
              caption: 'New album · Mara Eon',
            ),
          ]),
        ]),
        const TileRow(height: 1.5, [
          TileColumn(span: 1.5, [
            MetroTile(
              tone: TileTone.accent,
              number: '42',
              label: 'hours played',
              caption: 'this month',
            ),
          ]),
          TileColumn(span: 1.5, [
            MetroTile(
              art: ArtStyle.dust,
              label: 'Glass Coast',
              caption: 'Kiro Vale',
            ),
          ]),
        ]),
        const TileRow([
          TileColumn([MetroTile(number: '6', label: 'Singles')]),
          TileColumn([MetroTile(art: ArtStyle.futuristic)]),
          TileColumn([
            MetroTile(tone: TileTone.light, number: '2', label: 'Pre-saves'),
          ]),
        ]),
        TileRow([
          TileColumn(span: 3, [
            MetroTile(
              icon: LucideIcons.loaderPinwheel300,
              label: 'Your $year Replay',
              caption: 'Updated weekly',
            ),
          ]),
        ]),
      ]),
      below: const TileGrid(rows: [
        TileRow([
          TileColumn(span: 1.5, [MetroTile(art: ArtStyle.futuristic)]),
          TileColumn(span: 1.5, [MetroTile(art: ArtStyle.lake)]),
        ]),
      ]),
    );
  }
}
