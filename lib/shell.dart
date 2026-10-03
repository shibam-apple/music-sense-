import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'pages/account_page.dart';
import 'pages/albums_page.dart';
import 'pages/artist_page.dart';
import 'pages/featured_page.dart';
import 'pages/music_page.dart';
import 'pages/new_page.dart';
import 'pages/playing_page.dart';
import 'library/library.dart';
import 'library/models.dart';
import 'playback/playback_controller.dart';
import 'theme/tokens.dart';
import 'widgets/ambient.dart';
import 'widgets/panorama.dart';
import 'widgets/toast.dart';
import 'widgets/xmb_bar.dart';
import 'widgets/xmb_dock.dart';

/// The home screen: a Metro panorama of pages driven by one fractional page
/// position, which also slides the XMB bar. Swipes settle with a spring.
class PanoramaShell extends StatefulWidget {
  const PanoramaShell({super.key});

  @override
  State<PanoramaShell> createState() => _PanoramaShellState();
}

class _PanoramaShellState extends State<PanoramaShell>
    with SingleTickerProviderStateMixin {
  static const _items = [
    XmbItem(LucideIcons.music300, 'Music'),
    XmbItem(LucideIcons.discAlbum300, 'Albums'),
    XmbItem(LucideIcons.layoutDashboard300, 'Featured'),
    XmbItem(LucideIcons.sparkles300, 'New'),
    XmbItem(LucideIcons.disc3300, 'Playing'),
    XmbItem(LucideIcons.user300, 'Artist'),
    XmbItem(LucideIcons.circleUserRound300, 'Account'),
  ];

  static const _pages = <Widget>[
    MusicPage(),
    AlbumsPage(),
    FeaturedPage(),
    NewPage(),
    PlayingPage(),
    ArtistPage(),
    AccountPage(),
  ];

  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 180,
    damping: 26,
  );

  late final _page = AnimationController.unbounded(vsync: this)
    ..addListener(_tickOnSnap);
  int _dragStartPage = 0;
  int _snapped = 0;

  /// A light haptic tick each time a new icon reaches the XMB slot.
  void _tickOnSnap() {
    final nearest = _page.value.round();
    if (nearest != _snapped && (_page.value - nearest).abs() < 0.08) {
      _snapped = nearest;
      HapticFeedback.selectionClick();
    }
  }

  int get _last => _pages.length - 1;

  static const _playingIndex = 4;
  static const _ids = [
    'music',
    'albums',
    'featured',
    'new',
    'playing',
    'artist',
    'account',
  ];
  final _scrollTop = ValueNotifier<(String, int)>(('', 0));

  /// Tapping an icon goes to its page; tapping the active one scrolls that
  /// page back to the top.
  void _select(int index) {
    if (index == _page.value.round() && !_page.isAnimating) {
      HapticFeedback.selectionClick();
      _scrollTop.value = (_ids[index], _scrollTop.value.$2 + 1);
      return;
    }
    _goTo(index);
  }

  @override
  void dispose() {
    _page.dispose();
    _scrollTop.dispose();
    super.dispose();
  }

  void _goTo(int index, {double velocity = 0}) {
    final target = index.clamp(0, _last).toDouble();
    _page.animateWith(SpringSimulation(_spring, _page.value, target, velocity));
  }

  void _onDragStart(DragStartDetails _) {
    _page.stop();
    _dragStartPage = _page.value.round();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    var delta = -details.primaryDelta! / MsSizes.pageStride;
    final value = _page.value;
    // Resist past the first and last page.
    if ((value <= 0 && delta < 0) || (value >= _last && delta > 0)) {
      delta *= 0.35;
    }
    _page.value = value + delta;
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = -details.velocity.pixelsPerSecond.dx / MsSizes.pageStride;
    var target = _page.value.round();
    if (velocity.abs() > 1.2) {
      target = _dragStartPage + velocity.sign.toInt();
    }
    target = target.clamp(_dragStartPage - 1, _dragStartPage + 1);
    _goTo(target, velocity: velocity);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final current = _page.value.round();
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        _goTo(current + 1);
      case LogicalKeyboardKey.arrowLeft:
        _goTo(current - 1);
      case LogicalKeyboardKey.space:
        PlayerScope.read(context).toggle();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return ScrollToTop(
            requests: _scrollTop,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: Stack(
                children: [
                  const Positioned.fill(child: AmbientBackdrop()),
                  // The album's colours fill the screen as Playing comes
                  // into view, so its neighbours never meet it at a seam.
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _page,
                      child: const AlbumBackground(),
                      builder: (context, child) {
                        final t = _nearPlaying;
                        if (t <= 0) return const SizedBox();
                        return t >= 1
                            ? child!
                            : Opacity(opacity: t, child: child);
                      },
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _page,
                    builder: (context, _) {
                      final p = _page.value;
                      return Stack(
                        children: [
                          for (final (i, page) in _pages.indexed)
                            if (_visible(i, p, width))
                              Positioned(
                                key: ValueKey(i),
                                left: (i - p) * MsSizes.pageStride,
                                top: 0,
                                bottom: MsSizes.columnBottom,
                                // One panorama step wide, so a page (and
                                // its backgrounds) never bleeds into the next.
                                width: i == _last ? width : MsSizes.pageStride,
                                child: RepaintBoundary(child: page),
                              ),
                        ],
                      );
                    },
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: MsSizes.barFromBottom + MsSizes.barHeight / 2 + 8,
                    child: PlayerToast(),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: MsSizes.barFromBottom - MsSizes.barHeight / 2,
                    child: XmbBar(
                      items: _items,
                      page: _page,
                      onSelect: _select,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: constraints.maxHeight - MsSizes.dockTop,
                    child: XmbDock(
                      page: _page,
                      playingIndex: _playingIndex,
                      onOpenPlaying: () => _goTo(_playingIndex),
                      actionsFor: _actionsFor,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 1 on the Playing page, falling to 0 one page away.
  double get _nearPlaying =>
      (1 - (_page.value - _playingIndex).abs()).clamp(0.0, 1.0);

  /// The dock's options for each page (the XMB's column under its icon).
  List<DockAction> _actionsFor(BuildContext context, int page) {
    final player = PlayerScope.of(context);
    final library = LibraryScope.of(context);

    void shuffle(List<Track> songs, String what) {
      if (songs.isEmpty) return;
      player.playTracks(List.of(songs)..shuffle());
      player.message.value = 'Shuffling $what';
    }

    final beatSense = DockAction(
      LucideIcons.audioWaveform300,
      player.beatSenseEnabled ? 'Beat Sense on' : 'Beat Sense off',
      () {
        player.beatSenseEnabled = !player.beatSenseEnabled;
        player.message.value = player.beatSenseEnabled
            ? 'Beat Sense on · songs will mix'
            : 'Beat Sense off';
      },
      on: player.beatSenseEnabled,
    );
    final artist = player.track?.artist;
    return switch (_ids[page.clamp(0, _ids.length - 1)]) {
      'music' => [
        DockAction(
          LucideIcons.shuffle300,
          'Shuffle all songs',
          () => shuffle(library.recent, 'all songs'),
        ),
        beatSense,
      ],
      'albums' => [
        DockAction(LucideIcons.shuffle300, 'Shuffle an album', () {
          final albums = List.of(library.albums)..shuffle();
          if (albums.isEmpty) return;
          player.playTracks(albums.first.tracks);
          player.message.value = 'Playing ${albums.first.title}';
        }),
        beatSense,
      ],
      'featured' || 'new' => [
        DockAction(
          LucideIcons.radio300,
          'Start radio',
          () => shuffle(library.recent, 'radio'),
        ),
        beatSense,
      ],
      'playing' => [
        DockAction(
          LucideIcons.user300,
          'Go to artist',
          () => _goTo(_playingIndex + 1),
        ),
        beatSense,
      ],
      'artist' => [
        DockAction(
          LucideIcons.shuffle300,
          'Shuffle artist',
          () => shuffle(
            artist == null ? library.recent : library.byArtist(artist),
            artist ?? 'all songs',
          ),
        ),
        beatSense,
      ],
      _ => [beatSense],
    };
  }

  bool _visible(int i, double p, double width) {
    final left = (i - p) * MsSizes.pageStride;
    return left < width && left + width > 0;
  }
}
