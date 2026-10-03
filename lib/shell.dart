import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'pages/albums_page.dart';
import 'pages/artist_page.dart';
import 'pages/featured_page.dart';
import 'pages/music_page.dart';
import 'pages/new_page.dart';
import 'pages/playing_page.dart';
import 'state/player.dart';
import 'theme/tokens.dart';
import 'widgets/xmb_bar.dart';

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
  ];

  static const _pages = <Widget>[
    MusicPage(),
    AlbumsPage(),
    FeaturedPage(),
    NewPage(),
    PlayingPage(),
    ArtistPage(),
  ];

  static const _spring = SpringDescription(mass: 1, stiffness: 180, damping: 26);

  late final _page = AnimationController.unbounded(vsync: this);
  int _dragStartPage = 0;

  int get _last => _pages.length - 1;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _goTo(int index, {double velocity = 0}) {
    final target = index.clamp(0, _last).toDouble();
    _page.animateWith(
      SpringSimulation(_spring, _page.value, target, velocity),
    );
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
        PlayerScope.of(context).toggle();
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
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          child: Stack(
            children: [
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
                            bottom: 0,
                            width: width,
                            child: RepaintBoundary(child: page),
                          ),
                    ],
                  );
                },
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: MsSizes.barFromBottom - MsSizes.barHeight / 2,
                child: XmbBar(items: _items, page: _page, onSelect: _goTo),
              ),
            ],
          ),
        );
      }),
    );
  }

  bool _visible(int i, double p, double width) {
    final left = (i - p) * MsSizes.pageStride;
    return left < width && left + width > 0;
  }
}
