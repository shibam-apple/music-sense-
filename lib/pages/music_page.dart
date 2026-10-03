import 'package:flutter/material.dart';

import '../library/library.dart';
import '../library/models.dart';
import '../playback/playback_controller.dart';
import '../theme/tokens.dart';
import '../widgets/ambient.dart';
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
    final library = LibraryScope.of(context);
    final songs = library.recent;
    final current = player.track ?? (songs.isEmpty ? null : songs.first);
    final list = [
      for (final t in songs)
        if (t != current) t,
    ];

    void playFrom(Track t) {
      final at = songs.indexOf(t);
      player.playTracks(songs, start: at < 0 ? 0 : at);
    }

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
              for (final (i, t) in songs.take(7).indexed) ...[
                if (i > 0) const SizedBox(width: 4),
                SizedBox.square(
                  dimension: 31.5,
                  child: Reveal(
                    order: i,
                    child: Pressable(
                      onTap: () => playFrom(t),
                      child: Artwork(art: t.artwork, radius: 4),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          SizedBox.square(
            dimension: width,
            child: current == null
                ? const SizedBox()
                : AnimatedSwitcher(
                    duration: MsMotion.medium,
                    child: LiveCover(key: ValueKey(current.key), art: current.artwork),
                  ),
          ),
          const SizedBox(height: 18),
          NowPlayingLabel(status: player.beatSense),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(current?.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MsText.songTitleLarge.copyWith(fontSize: 21)),
                    const SizedBox(height: 2),
                    Text(
                      subtitleOf(current),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MsText.rowSubtitle.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
              _PlayPause(
                playing: player.playing,
                onTap: () => player.track == null && current != null
                    ? playFrom(current)
                    : player.toggle(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ProgressLine(value: player.progress),
          const SizedBox(height: 18),
          for (final (i, song) in list.take(2).indexed) ...[
            if (i > 0) const SizedBox(height: 16),
            Reveal(
              order: 4 + i,
              child: MediaRow(
                art: song.artwork,
                title: song.title,
                subtitle: song.artist,
                onTap: () => playFrom(song),
              ),
            ),
          ],
        ],
      ),
      below: Column(
        children: [
          for (final (i, song) in list.skip(2).take(2).indexed) ...[
            if (i > 0) const SizedBox(height: 16),
            MediaRow(art: song.artwork, title: song.title, subtitle: song.artist),
          ],
        ],
      ),
    );
  }
}

String subtitleOf(Track? t) {
  if (t == null) return '';
  return t.album == null ? t.artist : '${t.artist} · ${t.album}';
}

/// "NOW PLAYING", or Beat Sense's state while it's on, with dancing bars.
class NowPlayingLabel extends StatelessWidget {
  const NowPlayingLabel({super.key, required this.status});

  final BeatSenseStatus status;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const PlayingBars(),
        const SizedBox(width: 5),
        AnimatedSwitcher(
          duration: MsMotion.fast,
          child: Text(status.label, key: ValueKey(status.label), style: MsText.overline),
        ),
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
    return Semantics(
      button: true,
      label: playing ? 'Pause' : 'Play',
      child: Pressable(
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
      ),
    );
  }
}

/// A thin seek line: accent fill over a light track. When seekable it
/// shows a thumb while dragged.
class ProgressLine extends StatefulWidget {
  const ProgressLine({super.key, required this.value, this.onSeek});

  final double value;
  final ValueChanged<double>? onSeek;

  @override
  State<ProgressLine> createState() => _ProgressLineState();
}

class _ProgressLineState extends State<ProgressLine> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final seekable = widget.onSeek != null;
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      double at(Offset p) => (p.dx / w).clamp(0.0, 1.0);
      final value = (_drag ?? widget.value).clamp(0.0, 1.0);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: seekable ? (d) => widget.onSeek!(at(d.localPosition)) : null,
        onHorizontalDragStart: seekable ? (d) => setState(() => _drag = at(d.localPosition)) : null,
        onHorizontalDragUpdate: seekable ? (d) => setState(() => _drag = at(d.localPosition)) : null,
        onHorizontalDragEnd: seekable
            ? (_) {
                widget.onSeek!(_drag ?? widget.value);
                setState(() => _drag = null);
              }
            : null,
        child: SizedBox(
          height: 16,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 2.5,
                decoration: BoxDecoration(
                  color: MsColors.track,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                width: w * value,
                height: 2.5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(colors: [
                    MsColors.accent,
                    Color.lerp(MsColors.accent, Accent.of(context), 0.5)!,
                  ]),
                ),
              ),
              if (seekable)
                Positioned(
                  left: w * value - 6,
                  child: AnimatedScale(
                    scale: _drag == null ? 0 : 1,
                    duration: MsMotion.fast,
                    curve: MsMotion.curve,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: MsColors.accent,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Color(0x406F56F8), blurRadius: 8)],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}
