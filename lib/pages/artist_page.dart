import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/library.dart';
import '../state/player.dart';
import '../theme/tokens.dart';
import '../widgets/artwork.dart';
import '../widgets/panorama.dart';
import '../widgets/tiles.dart';

/// 6 · Artist — full-bleed photo, actions, latest release and top songs.
class ArtistPage extends StatelessWidget {
  const ArtistPage({super.key});

  static const heroHeight = 380.0;

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final width =
        MediaQuery.sizeOf(context).width - MsSizes.pageInset * 2;

    return Stack(
      children: [
        const Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: heroHeight,
          child: _Hero(),
        ),
        PanoramaPage(
          title: null,
          titleTop: heroHeight - 72,
          width: width,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Chip(icon: LucideIcons.ticket300, label: 'Upcoming concerts'),
              const SizedBox(height: 10),
              const Text('Rufus Stewart', style: MsText.heroTitle),
              const SizedBox(height: 22),
              Row(
                children: [
                  _CircleButton(
                    filled: true,
                    size: 54,
                    icon: Icons.play_arrow_rounded,
                    label: 'Play artist',
                    onTap: () => player.playSong(MockLibrary.futuristic),
                  ),
                  const SizedBox(width: 12),
                  const _CircleButton(icon: LucideIcons.info300, label: 'About'),
                  const SizedBox(width: 12),
                  const _CircleButton(icon: LucideIcons.star300, label: 'Follow'),
                ],
              ),
              const SizedBox(height: 26),
              const Reveal(child: _ReleaseCard()),
            ],
          ),
          below: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('top songs',
                      style: MsText.pageTitle.copyWith(fontSize: 19)),
                  const SizedBox(width: 4),
                  const Icon(LucideIcons.chevronRight300,
                      size: 16, color: MsColors.inkSecondary),
                ],
              ),
              const SizedBox(height: 14),
              const MediaRow(
                art: ArtStyle.futuristic,
                title: 'Futuristic',
                subtitle: 'Vol. 01 · 2026',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        Artwork(style: ArtStyle.dust, radius: 0),
        DecoratedBox(
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
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: MsColors.ink),
          const SizedBox(width: 6),
          Text(label,
              style: MsText.rowSubtitle.copyWith(
                  color: MsColors.ink, fontWeight: FontWeight.w500)),
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
            border:
                filled ? null : Border.all(color: MsColors.inkTertiary, width: 1),
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

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard();

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
          const SizedBox.square(
            dimension: 64,
            child: Artwork(style: ArtStyle.futuristic),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sep 11, 2026',
                    style: MsText.rowSubtitle.copyWith(fontSize: 11)),
                const SizedBox(height: 2),
                Text('Futuristic – Vol. 01',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MsText.rowTitle.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                const Text('Single · 1 song', style: MsText.rowSubtitle),
              ],
            ),
          ),
          const _CircleButton(icon: LucideIcons.plus300, label: 'Add', size: 32),
        ],
      ),
    );
  }
}
