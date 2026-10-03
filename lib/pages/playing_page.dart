import 'package:flutter/material.dart';

import '../library/library.dart';
import '../playback/playback_controller.dart';
import '../theme/tokens.dart';
import '../widgets/ambient.dart';
import '../widgets/panorama.dart';
import '../widgets/tiles.dart';
import 'music_page.dart'
    show PlayPauseButton, ProgressLine, SongList, subtitleOf;

/// 5 · Playing — cover, seek bar, transport, and the queue below the bar.
class PlayingPage extends StatelessWidget {
  const PlayingPage({super.key});

  static const width = 262.0;

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final library = LibraryScope.of(context);
    final song = player.track ?? library.recent.firstOrNull;
    final status = player.beatSense;

    // Up next: the queue, or (with nothing queued) songs from the library.
    final upNext = player.upNext.isNotEmpty
        ? player.upNext
        : library.recent.where((t) => t != song).take(30).toList();

    return PanoramaPage(
      id: 'playing',
      title: 'now playing',
      width: width,
      bodyGap: 30,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: width,
            child: song == null
                ? const SizedBox()
                : AnimatedSwitcher(
                    duration: MsMotion.medium,
                    child: LiveCover(
                      key: ValueKey(song.key),
                      art: song.artwork,
                      radius: 14,
                      motes: true,
                    ),
                  ),
          ),
          const SizedBox(height: 22),
          AnimatedSwitcher(
            duration: MsMotion.medium,
            child: Column(
              key: ValueKey(song?.key),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song?.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MsText.songTitleLarge,
                ),
                const SizedBox(height: 3),
                Text(
                  subtitleOf(song),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MsText.rowSubtitle.copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PositionBuilder(
            builder: (context, p) => Column(
              children: [
                ProgressLine(value: p.progress, onSeek: p.seek),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(formatTime(p.position), style: MsText.time),
                    const Spacer(),
                    if (status.state == BeatSenseState.mixing ||
                        status.state == BeatSenseState.ready)
                      Text(
                        status.state == BeatSenseState.mixing
                            ? 'mixing'
                            : 'mix in ${formatTime(_untilMix(p))}',
                        style: MsText.time.copyWith(color: MsColors.accent),
                      ),
                    const Spacer(),
                    Text(
                      '-${formatTime(p.duration - p.position)}',
                      style: MsText.time,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Transport(
                icon: Icons.fast_rewind_rounded,
                size: 30,
                label: 'Previous',
                onTap: player.previous,
              ),
              const SizedBox(width: 40),
              PlayPauseButton(
                playing: player.playing,
                size: 44,
                box: 56,
                onTap: () => player.track == null && song != null
                    ? player.playTracks(
                        library.recent,
                        start: library.recent.indexOf(song),
                      )
                    : player.toggle(),
              ),
              const SizedBox(width: 40),
              _Transport(
                icon: Icons.fast_forward_rounded,
                size: 30,
                label: 'Next',
                onTap: player.next,
              ),
            ],
          ),
        ],
      ),
      body: SliverMainAxisGroup(
        slivers: [
          const SliverToBoxAdapter(child: SectionTitle('up next')),
          SongList(
            songs: upNext,
            onTap: (t) {
              final at = player.queue.indexOf(t);
              at >= 0
                  ? player.playTracks(player.queue, start: at)
                  : player.playTracks(upNext, start: upNext.indexOf(t));
            },
          ),
        ],
      ),
    );
  }

  Duration _untilMix(PlaybackController player) {
    final plan = player.beatSense.plan;
    if (plan == null) return player.duration - player.position;
    final seconds = plan.exitAt - player.position.inMicroseconds / 1e6;
    return Duration(milliseconds: (seconds.clamp(0, 36000) * 1000).round());
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
              child: Icon(
                icon,
                key: ValueKey(icon),
                size: size,
                color: MsColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
