import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../library/library.dart';
import '../library/models.dart';
import '../playback/playback_controller.dart';
import '../theme/tokens.dart';
import 'ambient.dart';
import 'artwork.dart';
import 'tiles.dart';

/// What the dock under the bar offers on one page: the XMB's options for
/// the selected category, laid out for a thumb.
class DockAction {
  const DockAction(this.icon, this.label, this.onTap, {this.on = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// A toggle that's currently on (filled).
  final bool on;
}

/// The XMB continued for touch: under the icon row, the song playing (or
/// coming next) and the selected category's options as Metro tiles. It
/// changes with the page, the way the XMB's column changes under each icon.
class XmbDock extends StatefulWidget {
  const XmbDock({
    super.key,
    required this.page,
    required this.actionsFor,
    required this.onOpenPlaying,
    required this.playingIndex,
  });

  final Animation<double> page;
  final List<DockAction> Function(BuildContext context, int page) actionsFor;
  final VoidCallback onOpenPlaying;
  final int playingIndex;

  static const height = 50.0;

  @override
  State<XmbDock> createState() => _XmbDockState();
}

class _XmbDockState extends State<XmbDock> {
  late int _index = widget.page.value.round();

  @override
  void initState() {
    super.initState();
    widget.page.addListener(_onPage);
  }

  @override
  void dispose() {
    widget.page.removeListener(_onPage);
    super.dispose();
  }

  void _onPage() {
    final i = widget.page.value.round();
    if (i != _index) setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.actionsFor(context, _index);
    return SizedBox(
      height: XmbDock.height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: AnimatedSwitcher(
          duration: MsMotion.medium,
          switchInCurve: MsMotion.emphasized,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (current, previous) =>
              Stack(children: [...previous, ?current]),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.35),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Row(
            key: ValueKey(_index),
            children: [
              Expanded(
                child: _NowPlayingTile(
                  showNext: _index == widget.playingIndex || _index == 0,
                  onOpen: widget.onOpenPlaying,
                ),
              ),
              for (final a in actions) ...[
                const SizedBox(width: 8),
                _ActionTile(action: a),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The song playing, or (where it's already on screen) the one after it.
class _NowPlayingTile extends StatelessWidget {
  const _NowPlayingTile({required this.showNext, required this.onOpen});

  final bool showNext;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final library = LibraryScope.of(context);
    final current = player.track;
    final status = player.beatSense;
    Track? next = player.upNext.firstOrNull;
    if (status.next case final Track t) next = t;
    final song = showNext ? next : (current ?? library.recent.firstOrNull);
    final caption = showNext
        ? (status.state == BeatSenseState.mixing
              ? 'Mixing in now'
              : status.state == BeatSenseState.ready
              ? 'Beat Sense · up next'
              : 'Up next')
        : song?.byline ?? '';

    return Semantics(
      button: true,
      label: showNext ? 'Up next: ${song?.title ?? ''}' : 'Open now playing',
      child: Pressable(
        tilt: 0.05,
        onTap: showNext ? player.next : onOpen,
        child: Container(
          height: XmbDock.height,
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x12000000)),
          ),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 38,
                child: song == null
                    ? const SizedBox()
                    : Artwork(art: song.artwork, radius: 9),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song?.title ?? 'Nothing playing',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MsText.rowTitle.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MsText.rowSubtitle.copyWith(
                        fontSize: 11,
                        color: showNext && status.state != BeatSenseState.off
                            ? MsColors.accent
                            : MsColors.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (showNext)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    LucideIcons.skipForward300,
                    size: 18,
                    color: MsColors.ink,
                  ),
                )
              else
                _MiniPlayPause(player: player),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniPlayPause extends StatelessWidget {
  const _MiniPlayPause({required this.player});

  final PlaybackController player;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: player.playing ? 'Pause' : 'Play',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (player.track == null) {
            final songs = LibraryScope.read(context).recent;
            if (songs.isNotEmpty) player.playTracks(songs);
          } else {
            player.toggle();
          }
        },
        child: SizedBox(
          width: 38,
          height: 38,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Progress ring around the button.
              PositionBuilder(
                builder: (context, p) => SizedBox.square(
                  dimension: 30,
                  child: CircularProgressIndicator(
                    value: p.progress.clamp(0.0, 1.0),
                    strokeWidth: 1.6,
                    color: Accent.of(context),
                    backgroundColor: MsColors.track,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: MsMotion.fast,
                transitionBuilder: (child, a) =>
                    ScaleTransition(scale: a, child: child),
                child: Icon(
                  player.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  key: ValueKey(player.playing),
                  size: 18,
                  color: MsColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});

  final DockAction action;

  @override
  Widget build(BuildContext context) {
    final on = action.on;
    return Semantics(
      button: true,
      toggled: on,
      label: action.label,
      child: Tooltip(
        message: action.label,
        child: Pressable(
          onTap: action.onTap,
          child: AnimatedContainer(
            duration: MsMotion.fast,
            curve: MsMotion.curve,
            width: XmbDock.height,
            height: XmbDock.height,
            decoration: BoxDecoration(
              color: on ? MsColors.accent : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: on ? MsColors.accent : const Color(0x12000000),
              ),
            ),
            child: Icon(
              action.icon,
              size: 19,
              color: on ? Colors.white : MsColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
