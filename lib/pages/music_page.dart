import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../library/library.dart';
import '../library/models.dart';
import '../library/names.dart';
import '../playback/playback_controller.dart';
import '../theme/tokens.dart';
import '../widgets/ambient.dart';
import '../widgets/artwork.dart';
import '../widgets/panorama.dart';
import '../widgets/tiles.dart';

/// 1 · Music — "music collection": recent artwork, the current song, then
/// every song, scrolling down through the bar.
class MusicPage extends StatelessWidget {
  const MusicPage({super.key});

  static const width = 245.0;

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final library = LibraryScope.of(context);
    final songs = library.recent;
    final current = player.track ?? (songs.isEmpty ? null : songs.first);

    void playFrom(Track t) {
      final at = songs.indexOf(t);
      player.playTracks(songs, start: at < 0 ? 0 : at);
    }

    return PanoramaPage(
      id: 'music',
      title: 'music collection',
      titleStyle: MsText.heroTitle,
      titleTop: 44,
      contentGap: 18,
      width: width,
      bodyGap: 18,
      header: Column(
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
                : Pressable(
                    tilt: 0.06,
                    onTap: () => player.track == null
                        ? playFrom(current)
                        : player.toggle(),
                    child: AnimatedSwitcher(
                      duration: MsMotion.medium,
                      child: LiveCover(
                        key: ValueKey(current.key),
                        art: current.artwork,
                      ),
                    ),
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
                    Text(
                      current?.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MsText.songTitleLarge.copyWith(fontSize: 21),
                    ),
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
              PlayPauseButton(
                playing: player.playing,
                onTap: () => player.track == null && current != null
                    ? playFrom(current)
                    : player.toggle(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PositionBuilder(
            builder: (context, p) => ProgressLine(value: p.progress),
          ),
        ],
      ),
      body: SongList(songs: songs, current: player.track, onTap: playFrom),
    );
  }
}

/// Every song as a lazily built list; the playing one is marked.
class SongList extends StatelessWidget {
  const SongList({
    super.key,
    required this.songs,
    required this.onTap,
    this.current,
    this.subtitle,
  });

  final List<Track> songs;
  final Track? current;
  final void Function(Track) onTap;
  final String Function(Track)? subtitle;

  @override
  Widget build(BuildContext context) {
    return SliverList.separated(
      itemCount: songs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, i) {
        final song = songs[i];
        final row = MediaRow(
          art: song.artwork,
          title: song.title,
          subtitle: subtitle?.call(song) ?? song.byline,
          active: song == current,
          onTap: () => onTap(song),
        );
        return ColumnFocus(
          child: i < 6 ? Reveal(order: 4 + i, child: row) : row,
        );
      },
    );
  }
}

String subtitleOf(Track? t) {
  if (t == null) return '';
  if (t.artist == unknownArtist || t.album == null) return t.byline;
  return '${t.artist} · ${t.album}';
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
          child: Text(
            status.label,
            key: ValueKey(status.label),
            style: MsText.overline,
          ),
        ),
      ],
    );
  }
}

/// Play/pause that morphs between its two shapes.
class PlayPauseButton extends StatefulWidget {
  const PlayPauseButton({
    super.key,
    required this.playing,
    required this.onTap,
    this.size = 26,
    this.box = 36,
  });

  final bool playing;
  final VoidCallback onTap;
  final double size;
  final double box;

  @override
  State<PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<PlayPauseButton>
    with SingleTickerProviderStateMixin {
  late final _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.playing ? 1 : 0,
  );

  @override
  void didUpdateWidget(PlayPauseButton old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) {
      widget.playing ? _morph.forward() : _morph.reverse();
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.playing ? 'Pause' : 'Play',
      child: Pressable(
        onTap: widget.onTap,
        tilt: 0,
        child: SizedBox.square(
          dimension: widget.box,
          child: Center(
            child: AnimatedIcon(
              icon: AnimatedIcons.play_pause,
              progress: CurvedAnimation(
                parent: _morph,
                curve: Curves.easeInOutCubic,
              ),
              size: widget.size,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        double at(Offset p) => (p.dx / w).clamp(0.0, 1.0);
        final value = (_drag ?? widget.value).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: seekable
              ? (d) => widget.onSeek!(at(d.localPosition))
              : null,
          onHorizontalDragStart: seekable
              ? (d) {
                  HapticFeedback.selectionClick();
                  setState(() => _drag = at(d.localPosition));
                }
              : null,
          onHorizontalDragUpdate: seekable
              ? (d) => setState(() => _drag = at(d.localPosition))
              : null,
          onHorizontalDragEnd: seekable
              ? (_) {
                  HapticFeedback.lightImpact();
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
                    gradient: LinearGradient(
                      colors: [
                        MsColors.accent,
                        Color.lerp(MsColors.accent, Accent.of(context), 0.5)!,
                      ],
                    ),
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
                          boxShadow: [
                            BoxShadow(color: Color(0x406F56F8), blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
