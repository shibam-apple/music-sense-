import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// One Metro panorama page that scrolls vertically like an XMB column: a
/// large lowercase title, a header (cover, tiles…), then a lazily built
/// [body] sliver. The column ends just above the XMB bar: content fades
/// out crisply there and under the status bar, never behind the icons.
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

  /// Space at the end so the last item can rise clear of the soft edge.
  static const endSpace = MsSizes.columnFade + 8;

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

        final statusBar = MediaQuery.paddingOf(context).top;
        return _ScrollTick(
          ticks: _scrolled,
          child: _EdgeFade(
            top: statusBar,
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

/// Fades a page's column out at its two ends: under the status bar and
/// where it meets the XMB bar. A mask, so whatever is behind (white, or the
/// album's colours) shows through cleanly.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.top, required this.child});

  final double top;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final h = rect.height;
        final topEnd = ((top + 6) / h).clamp(0.0, 0.2);
        final bottomStart = (1 - MsSizes.columnFade / h).clamp(0.5, 1.0);
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [topEnd * 0.4, topEnd, bottomStart, 1],
          colors: const [
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000),
          ],
        ).createShader(rect);
      },
      child: child,
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

/// The XMB column's focus: a list row is at full strength only in the
/// two-row band just above the bar; rows that scroll up past it recede, so
/// the column never puts more than two songs forward at once.
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
    // Where the column's soft edge begins; the focus band sits right above.
    final zoneBottom = height - MsSizes.columnBottom - MsSizes.columnFade * 0.5;
    final bandTop = zoneBottom - ColumnFocus.band;
    final past = ((bandTop - centre) / 40).clamp(0.0, 1.0);
    final next = 1 - 0.62 * Curves.easeOut.transform(past);
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
