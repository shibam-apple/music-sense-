import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/library.dart';
import '../state/player.dart';
import '../theme/tokens.dart';
import '../widgets/artwork.dart';
import '../widgets/panorama.dart';
import '../widgets/tiles.dart';

/// 1 · Music — "music collection": recent artwork, the current song and the
/// song list.
class MusicPage extends StatelessWidget {
  const MusicPage({super.key});

  static const width = 245.0;

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final songs = MockLibrary.songs;

    return PanoramaPage(
      title: 'music collection',
      titleStyle: MsText.heroTitle,
      titleTop: 44,
      contentGap: 18,
      width: width,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final (i, art) in MockLibrary.recentArt.indexed) ...[
                if (i > 0) const SizedBox(width: 4),
                SizedBox.square(
                  dimension: 31.5,
                  child: Reveal(
                    order: i,
                    child: Artwork(style: art, radius: 4),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          SizedBox.square(
            dimension: width,
            child: Artwork(style: player.song.art, radius: 12, shadow: true),
          ),
          const SizedBox(height: 18),
          const _NowPlayingLabel(),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(player.song.title,
                        style: MsText.songTitleLarge.copyWith(fontSize: 21)),
                    const SizedBox(height: 2),
                    Text(
                      '${player.song.artist} · ${player.song.album ?? ''}',
                      style: MsText.rowSubtitle.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
              _PlayPause(playing: player.playing, onTap: player.toggle),
            ],
          ),
          const SizedBox(height: 12),
          ProgressLine(value: player.progress),
          const SizedBox(height: 18),
          for (final (i, song) in songs.take(2).indexed) ...[
            if (i > 0) const SizedBox(height: 16),
            Reveal(
              order: 4 + i,
              child: MediaRow(
                art: song.art,
                title: song.title,
                subtitle: song.artist,
                onTap: () => player.playSong(song),
              ),
            ),
          ],
        ],
      ),
      below: Column(
        children: [
          for (final (i, song) in songs.skip(2).indexed) ...[
            if (i > 0) const SizedBox(height: 16),
            MediaRow(art: song.art, title: song.title, subtitle: song.artist),
          ],
        ],
      ),
    );
  }
}

class _NowPlayingLabel extends StatelessWidget {
  const _NowPlayingLabel();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(LucideIcons.chartNoAxesColumn400,
            size: 11, color: MsColors.accent),
        SizedBox(width: 4),
        Text('NOW PLAYING', style: MsText.overline),
      ],
    );
  }
}

class _PlayPause extends StatelessWidget {
  const _PlayPause({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: SizedBox.square(
        dimension: 36,
        child: AnimatedSwitcher(
          duration: MsMotion.fast,
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            key: ValueKey(playing),
            size: 26,
            color: MsColors.ink,
          ),
        ),
      ),
    );
  }
}

/// A thin seek line: accent fill over a light track.
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value, this.onSeek});

  final double value;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      void seek(Offset local) =>
          onSeek?.call(local.dx / constraints.maxWidth);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: onSeek == null ? null : (d) => seek(d.localPosition),
        onHorizontalDragUpdate:
            onSeek == null ? null : (d) => seek(d.localPosition),
        child: SizedBox(
          height: 14,
          child: Center(
            child: Stack(
              children: [
                Container(height: 2.5, color: MsColors.track),
                FractionallySizedBox(
                  widthFactor: value.clamp(0.0, 1.0),
                  child: Container(
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: MsColors.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
