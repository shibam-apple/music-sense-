import 'package:flutter/material.dart';

import '../library/models.dart';
import '../theme/tokens.dart';
import 'ambient.dart';
import 'artwork.dart';

enum TileTone { dark, accent, light }

/// A flat Metro tile: a big number or artwork, with a label in the corner.
class MetroTile extends StatelessWidget {
  const MetroTile({
    super.key,
    this.tone = TileTone.dark,
    this.art,
    this.number,
    this.label,
    this.caption,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  final TileTone tone;
  final ArtworkRef? art;
  final String? number;
  final String? label;
  final String? caption;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final onArt = art != null;
    final foreground =
        tone == TileTone.light && !onArt ? MsColors.ink : Colors.white;
    final background = switch (tone) {
      TileTone.dark => MsColors.tileDark,
      TileTone.accent => MsColors.accent,
      TileTone.light => MsColors.tileLight,
    };
    final captionColor = switch (tone) {
      TileTone.accent when !onArt => Colors.white.withValues(alpha: 0.7),
      TileTone.light when !onArt => MsColors.inkSecondary,
      _ => Colors.white.withValues(alpha: 0.75),
    };

    return Pressable(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(MsSizes.tileRadius),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (onArt) ...[
              Artwork(art: art!),
              if (label != null)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.all(Radius.circular(MsSizes.tileRadius)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.45, 1],
                      colors: [Color(0x00000000), Color(0x99000000)],
                    ),
                  ),
                ),
            ],
            if (selected)
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(MsSizes.tileRadius),
                  border: Border.all(color: MsColors.accent, width: 2.5),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon != null) Icon(icon, size: 17, color: foreground),
                  const Spacer(),
                  if (number != null)
                    Text(number!,
                        style: MsText.tileNumber.copyWith(color: foreground)),
                  if (number != null) const SizedBox(height: 5),
                  if (label != null)
                    Text(
                      label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MsText.tileLabel.copyWith(
                        color: foreground,
                        fontWeight:
                            number != null ? FontWeight.w500 : FontWeight.w600,
                      ),
                    ),
                  if (caption != null)
                    Text(
                      caption!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MsText.tileCaption.copyWith(color: captionColor),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lays tiles on the design's three-column grid. [span] and [rows] are in
/// grid cells; a cell is square.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.rows});

  final List<TileRow> rows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const gap = MsSizes.tileGap;
      final cell = (constraints.maxWidth - gap * 2) / 3;
      double extent(double cells) => cell * cells + gap * (cells - 1);

      return Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) const SizedBox(height: gap),
            SizedBox(
              height: extent(row.height),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (j, column) in row.columns.indexed) ...[
                    if (j > 0) const SizedBox(width: gap),
                    SizedBox(
                      width: column.span == 0
                          ? (constraints.maxWidth -
                                  gap * (row.columns.length - 1)) /
                              row.columns.length
                          : extent(column.span),
                      child: Column(
                        children: [
                          for (final (k, tile) in column.tiles.indexed) ...[
                            if (k > 0) const SizedBox(height: gap),
                            Expanded(
                              child: Reveal(
                                order: i * 3 + j + k,
                                child: tile,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    });
  }
}

class TileRow {
  const TileRow(this.columns, {this.height = 1});

  final List<TileColumn> columns;

  /// Row height in grid cells.
  final double height;
}

class TileColumn {
  /// [span] is the width in cells; 0 shares the row equally.
  const TileColumn(this.tiles, {this.span = 1});

  final List<Widget> tiles;
  final double span;
}

/// A list row: square artwork, title and subtitle.
class MediaRow extends StatelessWidget {
  const MediaRow({
    super.key,
    required this.art,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.active = false,
  });

  final ArtworkRef art;

  /// The row is the song playing now: accent title and dancing bars.
  final bool active;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            SizedBox.square(dimension: 54, child: Artwork(art: art)),
            const SizedBox(width: 17),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: active
                          ? MsText.rowTitle.copyWith(color: MsColors.accent)
                          : MsText.rowTitle),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MsText.rowSubtitle),
                ],
              ),
            ),
            if (active) ...[
              const SizedBox(width: 12),
              const PlayingBars(size: 13),
            ],
          ],
        ),
      ),
    );
  }
}

/// Metro press feedback: the element sinks slightly while pressed.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: MsMotion.fast,
        curve: MsMotion.curve,
        child: widget.child,
      ),
    );
  }
}

/// Fades and lifts its child in once, staggered by [order].
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.order = 0});

  final Widget child;
  final int order;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: MsMotion.slow,
  );
  late final _curve =
      CurvedAnimation(parent: _controller, curve: MsMotion.emphasized);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 60 * widget.order), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - _curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
