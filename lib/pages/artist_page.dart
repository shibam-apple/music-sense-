import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../library/library.dart';
import '../library/models.dart';
import '../playback/playback_controller.dart';
import '../theme/tokens.dart';
import '../widgets/ambient.dart';
import '../widgets/artwork.dart';
import '../widgets/panorama.dart';
import '../widgets/tiles.dart';
import 'music_page.dart' show SongList;

/// 6 · Artist — the current song's artist: full-bleed moving cover,
/// actions, latest release and top songs.
class ArtistPage extends StatelessWidget {
  const ArtistPage({super.key});

  static const heroHeight = 380.0;

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final library = LibraryScope.of(context);
    const width = MsSizes.contentWidth;

    final current = player.track ?? library.recent.firstOrNull;
    final artist = current?.artist ?? '';
    final songs = library.byArtist(artist);
    final latest = songs.isEmpty ? current : songs.first;
    final albums = library.albums.where((a) => a.artist == artist).toList();
    final release = albums.isNotEmpty ? albums.first : null;
    // Most played first, then the rest in library order.
    final played = library.stats.topOf(songs);
    final ranked = [...played, ...songs.where((t) => !played.contains(t))];

    return PanoramaPage(
      id: 'artist',
      title: null,
      titleTop: heroHeight - 72,
      width: width,
      backdrop: _Hero(
        art: latest?.artwork ?? const PaintedArtwork(ArtStyle.dust),
      ),
      backdropHeight: heroHeight,
      bodyGap: 30,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Chip(
            icon: library.isDemo ? LucideIcons.ticket300 : LucideIcons.music300,
            label: library.isDemo
                ? 'Upcoming concerts'
                : '${songs.length} ${songs.length == 1 ? 'song' : 'songs'} in your library',
          ),
          const SizedBox(height: 10),
          Text(
            artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MsText.heroTitle,
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              _CircleButton(
                filled: true,
                size: 54,
                icon: Icons.play_arrow_rounded,
                label: 'Play $artist',
                onTap: songs.isEmpty ? null : () => player.playTracks(songs),
              ),
              const SizedBox(width: 12),
              const _CircleButton(icon: LucideIcons.info300, label: 'About'),
              const SizedBox(width: 12),
              const _FollowButton(),
            ],
          ),
          const SizedBox(height: 26),
          if (latest != null)
            Reveal(
              child: _ReleaseCard(
                art: release?.artwork ?? latest.artwork,
                date: _date(latest.added),
                title: release?.title ?? latest.title,
                subtitle: release == null
                    ? 'Single · 1 song'
                    : 'Album · ${release.songCount} songs',
                onAdd: () => player.playTracks(release?.tracks ?? [latest]),
              ),
            ),
        ],
      ),
      body: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: SectionTitle(
              'top songs',
              trailing: const Icon(
                LucideIcons.chevronRight300,
                size: 16,
                color: MsColors.inkSecondary,
              ),
            ),
          ),
          SongList(
            songs: ranked,
            current: player.track,
            subtitle: subtitleOfSong,
            onTap: (t) => player.playTracks(ranked, start: ranked.indexOf(t)),
          ),
        ],
      ),
    );
  }

  static String subtitleOfSong(Track t) {
    final s = [t.album, t.year?.toString()].whereType<String>().join(' · ');
    return s.isEmpty ? t.artist : s;
  }

  static String _date(DateTime? d) {
    if (d == null) return '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

/// The artist hero: the cover large, drifting and slowly zooming like a
/// PS5 game backdrop, fading into the page.
class _Hero extends StatefulWidget {
  const _Hero({required this.art});

  final ArtworkRef art;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> with SingleTickerProviderStateMixin {
  late final _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: AnimatedBuilder(
            animation: _drift,
            builder: (context, child) {
              final t = Curves.easeInOut.transform(_drift.value);
              return Transform.scale(
                scale: 1.08 + 0.1 * t,
                alignment: Alignment(-0.3 + 0.6 * t, -0.2),
                child: child,
              );
            },
            child: AnimatedSwitcher(
              duration: MsMotion.slow,
              child: Artwork(
                key: ValueKey(widget.art),
                art: widget.art,
                radius: 0,
              ),
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.55, 0.92],
              colors: [Color(0x00FFFFFF), MsColors.background],
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: MsColors.ink),
          const SizedBox(width: 6),
          Text(
            label,
            style: MsText.rowSubtitle.copyWith(
              color: MsColors.ink,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.label,
    this.filled = false,
    this.size = 42,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Accent.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap ?? () {},
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? MsColors.ink : Colors.transparent,
            border: filled
                ? null
                : Border.all(color: MsColors.inkTertiary, width: 1),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: filled ? 26 : 18,
            color: filled ? Colors.white : MsColors.ink,
          ),
        ),
      ),
    );
  }
}

/// The star: fills with a little pop when tapped.
class _FollowButton extends StatefulWidget {
  const _FollowButton();

  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton> {
  bool _on = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: _on,
      label: 'Follow',
      child: Pressable(
        onTap: () => setState(() => _on = !_on),
        child: AnimatedContainer(
          duration: MsMotion.fast,
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _on
                ? MsColors.accent.withValues(alpha: 0.1)
                : Colors.transparent,
            border: Border.all(
              color: _on ? MsColors.accent : MsColors.inkTertiary,
              width: 1,
            ),
          ),
          child: TweenAnimationBuilder<double>(
            key: ValueKey(_on),
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 380),
            curve: Curves.elasticOut,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Icon(
              _on ? Icons.star_rounded : LucideIcons.star300,
              size: _on ? 22 : 18,
              color: _on ? MsColors.accent : MsColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({
    required this.art,
    required this.date,
    required this.title,
    required this.subtitle,
    required this.onAdd,
  });

  final ArtworkRef art;
  final String date, title, subtitle;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MsColors.tileLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 64,
            child: Glint(
              delay: const Duration(seconds: 4),
              child: Artwork(art: art),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (date.isNotEmpty)
                  Text(date, style: MsText.rowSubtitle.copyWith(fontSize: 11)),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MsText.rowTitle.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: MsText.rowSubtitle),
              ],
            ),
          ),
          _CircleButton(
            icon: LucideIcons.plus300,
            label: 'Play $title',
            size: 32,
            onTap: onAdd,
          ),
        ],
      ),
    );
  }
}
