import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../library/models.dart';
import '../playback/playback_controller.dart';
import '../theme/tokens.dart';
import '../widgets/ambient.dart';
import '../widgets/artwork.dart';
import '../widgets/tiles.dart';

/// One album: its cover (flown in from the tile you tapped), play and
/// shuffle, and the songs in order, on the album's own colours.
class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key, required this.album, required this.heroTag});

  final Album album;
  final Object heroTag;

  /// A Hero tag for [album]'s cover at [place] (tags must be unique per
  /// screen, and the same album can show in several places).
  static String tagFor(Album album, String place) =>
      'album:$place:${album.artist}:${album.title}';

  static Future<void> open(BuildContext context, Album album, Object heroTag) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 520),
        reverseTransitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, _, _) => AlbumPage(album: album, heroTag: heroTag),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: MsMotion.emphasized,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0.08, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  late (Color, Color) _scheme =
      ArtworkPalette.peekScheme(widget.album.artwork) ??
      (MsColors.accent, MsColors.accentSoft);

  @override
  void initState() {
    super.initState();
    ArtworkPalette.schemeOf(widget.album.artwork).then((s) {
      if (mounted && s != _scheme) setState(() => _scheme = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final player = PlayerScope.of(context);
    final wash = albumWash(_scheme);
    final padding = MediaQuery.paddingOf(context);
    const inset = MsSizes.pageInset;
    final cover = (MediaQuery.sizeOf(context).width - inset * 2).clamp(
      0.0,
      300.0,
    );
    final year = album.tracks.map((t) => t.year).whereType<int>().firstOrNull;
    final meta = [
      '${album.songCount} ${album.songCount == 1 ? 'song' : 'songs'}',
      if (album.minutes > 0) '${album.minutes} min',
      ?year?.toString(),
    ].join(' · ');

    void play({bool shuffle = false, int start = 0}) {
      player.playTracks(
        shuffle ? (List.of(album.tracks)..shuffle()) : album.tracks,
        start: start,
      );
    }

    return Scaffold(
      backgroundColor: MsColors.background,
      body: AnimatedContainer(
        duration: MsMotion.slow,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0, 0.55, 1],
            colors: [wash.top, wash.bottom, MsColors.background],
          ),
        ),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  inset - 10,
                  padding.top + 10,
                  inset,
                  0,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    button: true,
                    label: 'Back',
                    child: Pressable(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const SizedBox.square(
                        dimension: 44,
                        child: Icon(
                          LucideIcons.chevronLeft300,
                          size: 26,
                          color: MsColors.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(inset, 8, inset, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox.square(
                      dimension: cover,
                      child: Hero(
                        tag: widget.heroTag,
                        child: Artwork(
                          art: album.artwork,
                          radius: 14,
                          shadow: true,
                          shadowColor: _scheme.$1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Reveal(
                      order: 1,
                      child: Text(
                        album.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MsText.heroTitle.copyWith(fontSize: 30),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Reveal(
                      order: 2,
                      child: Text(
                        '${album.artist} · $meta',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MsText.rowSubtitle.copyWith(fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Reveal(
                      order: 3,
                      child: Row(
                        children: [
                          Expanded(
                            child: _Pill(
                              icon: Icons.play_arrow_rounded,
                              label: 'Play',
                              filled: true,
                              onTap: play,
                            ),
                          ),
                          const SizedBox(width: MsSizes.tileGap),
                          Expanded(
                            child: _Pill(
                              icon: LucideIcons.shuffle300,
                              label: 'Shuffle',
                              onTap: () => play(shuffle: true),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                inset,
                0,
                inset,
                padding.bottom + 40,
              ),
              sliver: SliverList.builder(
                itemCount: album.tracks.length,
                itemBuilder: (context, i) {
                  final t = album.tracks[i];
                  final row = _TrackRow(
                    number: i + 1,
                    track: t,
                    active: player.track == t,
                    onTap: () => play(start: i),
                  );
                  return i < 8 ? Reveal(order: 4 + i, child: row) : row;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : MsColors.ink;
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        tilt: 0.08,
        onTap: onTap,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: filled ? MsColors.ink : Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(MsSizes.tileRadius + 2),
            border: filled ? null : Border.all(color: const Color(0x14000000)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: filled ? 22 : 18, color: fg),
              const SizedBox(width: 6),
              Text(label, style: MsText.tileLabel.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.number,
    required this.track,
    required this.active,
    required this.onTap,
  });

  final int number;
  final Track track;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      tilt: 0.03,
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: active
                  ? const PlayingBars(size: 13)
                  : Text('$number', style: MsText.time.copyWith(fontSize: 13)),
            ),
            Expanded(
              child: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MsText.rowTitle.copyWith(
                  color: active ? MsColors.accent : MsColors.ink,
                ),
              ),
            ),
            if (track.duration > Duration.zero) ...[
              const SizedBox(width: 12),
              Text(
                formatTime(track.duration),
                style: MsText.time.copyWith(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
