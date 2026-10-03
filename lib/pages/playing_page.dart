import 'package:flutter/material.dart';

import '../data/library.dart';
import '../state/player.dart';
import '../theme/tokens.dart';
import '../widgets/artwork.dart';
import '../widgets/panorama.dart';
import '../widgets/tiles.dart';
import 'music_page.dart' show ProgressLine;

/// 5 · Playing — cover, seek bar, transport, and the queue below the bar.
class PlayingPage extends StatelessWidget {
  const PlayingPage({super.key});

  static const width = 262.0;

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final song = player.song;
    final next = MockLibrary.upNext.first;

    return PanoramaPage(
      title: 'now playing',
      width: width,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: width,
            child: AnimatedSwitcher(
              duration: MsMotion.medium,
              child: Artwork(
                key: ValueKey(song.title),
                style: song.art,
                radius: 14,
                shadow: true,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(song.title, style: MsText.songTitleLarge),
          const SizedBox(height: 3),
          Text(
            '${song.artist} · ${song.album ?? ''}',
            style: MsText.rowSubtitle.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 14),
          ProgressLine(value: player.progress, onSeek: player.seek),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(formatTime(player.position), style: MsText.time),
              const Spacer(),
              Text('-${formatTime(player.duration - player.position)}',
                  style: MsText.time),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Transport(
                icon: Icons.fast_rewind_rounded,
                size: 30,
                label: 'Back 10 seconds',
                onTap: () => player.skip(-10),
              ),
              const SizedBox(width: 40),
              _Transport(
                icon: player.playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 44,
                label: player.playing ? 'Pause' : 'Play',
                onTap: player.toggle,
              ),
              const SizedBox(width: 40),
              _Transport(
                icon: Icons.fast_forward_rounded,
                size: 30,
                label: 'Forward 10 seconds',
                onTap: () => player.skip(10),
              ),
            ],
          ),
        ],
      ),
      below: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('up next', style: MsText.pageTitle.copyWith(fontSize: 19)),
          const SizedBox(height: 14),
          MediaRow(art: next.art, title: next.title, subtitle: next.artist),
        ],
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.icon,
    required this.size,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        child: SizedBox.square(
          dimension: 52,
          child: Center(
            child: AnimatedSwitcher(
              duration: MsMotion.fast,
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(icon,
                  key: ValueKey(icon), size: size, color: MsColors.ink),
            ),
          ),
        ),
      ),
    );
  }
}
