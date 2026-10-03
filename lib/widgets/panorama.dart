import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// One Metro panorama page that scrolls vertically like an XMB column: a
/// large lowercase title, a header (cover, tiles…), then a lazily built
/// [body] sliver that runs down through the bar. The shell fades whatever
/// passes under and below the bar.
class PanoramaPage extends StatefulWidget {
  const PanoramaPage({
    super.key,
    required this.id,
    this.title,
    this.titleStyle = MsText.pageTitle,
    this.titleTop = MsSizes.titleTop,
    this.width = MsSizes.contentWidth,
    this.contentGap = 26,
    this.header,
    this.body,
    this.bodyGap = 16,
    this.backdrop,
    this.backdropHeight = 0,
  });

  /// Stable id: keeps the scroll position and receives scroll-to-top.
  final String id;
  final String? title;
  final TextStyle titleStyle;
  final double titleTop;
  final double width;
  final double contentGap;
  final Widget? header;

  /// A sliver (list or grid) under the header.
  final Widget? body;
  final double bodyGap;

  /// Full-width art behind the top of the page (the artist hero); it
  /// scrolls with the page.
  final Widget? backdrop;
  final double backdropHeight;

  /// Space at the end so the last items can scroll up past the bar.
  static const endSpace = MsSizes.barFromBottom + MsSizes.barHeight / 2 + 24;

  @override
  State<PanoramaPage> createState() => _PanoramaPageState();
}

class _PanoramaPageState extends State<PanoramaPage> {
  late final _controller = ScrollController()..addListener(_onScroll);

  /// Bumped on every scroll so list rows can re-check their focus.
  final _scrolled = ValueNotifier<int>(0);

  void _onScroll() => _scrolled.value++;
  ScrollToTop? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = ScrollToTop.maybeOf(context);
    if (scope != _scope) {
      _scope?.requests.removeListener(_onRequest);
      _scope = scope?..requests.addListener(_onRequest);
    }
  }

  void _onRequest() {
    if (_scope?.requests.value.$1 == widget.id && _controller.hasClients) {
      _controller.animateTo(
        0,
        duration: MsMotion.slow,
        curve: MsMotion.emphasized,
      );
    }
  }

  @override
  void dispose() {
    _scope?.requests.removeListener(_onRequest);
    _controller.dispose();
    _scrolled.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final right = (constraints.maxWidth - MsSizes.pageInset - widget.width)
            .clamp(0.0, double.infinity);
        final padding = EdgeInsets.only(left: MsSizes.pageInset, right: right);

        final top = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.title != null) ...[
              Text(
                widget.title!,
                style: widget.titleStyle,
                maxLines: 1,
                softWrap: false,
              ),
              SizedBox(height: widget.contentGap),
            ],
            ?widget.header,
          ],
        );

        return _ScrollTick(
          ticks: _scrolled,
          child: CustomScrollView(
            key: PageStorageKey('page-${widget.id}'),
            controller: _controller,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: widget.backdrop == null
                    ? Padding(
                        padding: padding.copyWith(top: widget.titleTop),
                        child: top,
                      )
                    : Stack(
                        children: [
                          SizedBox(
                            height: widget.backdropHeight,
                            width: double.infinity,
                            child: widget.backdrop,
                          ),
                          Padding(
                            padding: padding.copyWith(top: widget.titleTop),
                            child: top,
                          ),
                        ],
                      ),
              ),
              if (widget.body != null)
                SliverPadding(
                  padding: padding.copyWith(top: widget.bodyGap),
                  sliver: widget.body,
                ),
              const SliverToBoxAdapter(
                child: SizedBox(height: PanoramaPage.endSpace),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ScrollTick extends InheritedWidget {
  const _ScrollTick({required this.ticks, required super.child});

  final ValueListenable<int> ticks;

  @override
  bool updateShouldNotify(_ScrollTick oldWidget) => oldWidget.ticks != ticks;
}

/// Lets the shell ask a page to scroll back to the top (tapping the active
/// XMB icon). The value is (page id, request number).
class ScrollToTop extends InheritedWidget {
  const ScrollToTop({super.key, required this.requests, required super.child});

  final ValueNotifier<(String, int)> requests;

  static ScrollToTop? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScrollToTop>();

  @override
  bool updateShouldNotify(ScrollToTop oldWidget) =>
      oldWidget.requests != requests;
}

/// Fades the XMB column where it runs under and below the bar: content is
/// hidden behind the bar's band and washed out beneath it, as in the
/// design. A single overlay drawn once for all pages.
class ColumnFade extends StatelessWidget {
  const ColumnFade({super.key, this.color = MsColors.background});

  /// The page colour under the bar (white, or the album wash on Playing).
  final Color color;

  @override
  Widget build(BuildContext context) {
    const bar = MsSizes.barFromBottom;
    const half = MsSizes.barHeight / 2;
    Color a(double alpha) => color.withValues(alpha: alpha);
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          height: bar + half + 18,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // From the top of the fade: soft edge, solid behind the
                // icons and labels, then a translucent wash below.
                stops: const [0, 0.08, 0.46, 0.53, 1],
                colors: [a(0), a(0.95), a(0.95), a(0.55), a(0.6)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small lowercase section heading inside a page ("up next", "top songs").
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Row(
        children: [
          Text(text, style: MsText.pageTitle.copyWith(fontSize: 19)),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ],
      ),
    );
  }
}

/// The XMB column's focus: a list row is fully visible only in the two-row
/// band just above the bar; rows that scroll up past it fade away, so the
/// column never shows more than two songs at once. (Below the bar, the
/// shell's wash takes over.)
class ColumnFocus extends StatefulWidget {
  const ColumnFocus({super.key, required this.child});

  final Widget child;

  /// Height of the focus band: two rows (54) and the gap between them.
  static const band = 2 * 54.0 + 16 + 10;

  @override
  State<ColumnFocus> createState() => _ColumnFocusState();
}

class _ColumnFocusState extends State<ColumnFocus> {
  final _opacity = ValueNotifier<double>(1);
  ValueListenable<int>? _ticks;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ticks = context
        .dependOnInheritedWidgetOfExactType<_ScrollTick>()
        ?.ticks;
    if (ticks != _ticks) {
      _ticks?.removeListener(_schedule);
      _ticks = ticks?..addListener(_schedule);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  bool _scheduled = false;

  /// Scroll events arrive before the new layout; measure after it.
  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _update();
    });
  }

  void _update() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return;
    final centre = box.localToGlobal(Offset(0, box.size.height / 2)).dy;
    final height = MediaQuery.sizeOf(context).height;
    // Where the bar's fade begins; the focus band sits right above it.
    final zoneBottom =
        height - MsSizes.barFromBottom - MsSizes.barHeight / 2 - 18;
    final bandTop = zoneBottom - ColumnFocus.band;
    final past = ((bandTop - centre) / 30).clamp(0.0, 1.0);
    final next = 1 - 0.88 * Curves.easeOut.transform(past);
    if ((next - _opacity.value).abs() > 0.01) _opacity.value = next;
  }

  @override
  void dispose() {
    _ticks?.removeListener(_schedule);
    _opacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _opacity,
      child: widget.child,
      builder: (context, opacity, child) =>
          opacity >= 0.99 ? child! : Opacity(opacity: opacity, child: child),
    );
  }
}
