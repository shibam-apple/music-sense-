import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// One Metro panorama page: a large lowercase title, the page content above
/// the XMB bar, and the column's continuation below the bar, faded.
class PanoramaPage extends StatelessWidget {
  const PanoramaPage({
    super.key,
    required this.title,
    required this.content,
    this.below,
    this.titleStyle = MsText.pageTitle,
    this.titleTop = MsSizes.titleTop,
    this.width = MsSizes.contentWidth,
    this.contentGap = 26,
  });

  final String? title;
  final TextStyle titleStyle;
  final double titleTop;
  final double width;
  final double contentGap;
  final Widget content;

  /// The part of the column that runs on below the bar.
  final Widget? below;

  /// Space reserved above the bar's centre line.
  static const _barClearance =
      MsSizes.barFromBottom + MsSizes.barHeight / 2 - 10;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: MsSizes.pageInset,
          top: titleTop,
          bottom: _barClearance,
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Text(title!, style: titleStyle, maxLines: 1, softWrap: false),
                SizedBox(height: contentGap),
              ],
              Expanded(
                // On short screens the page scales down rather than running
                // under the bar.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: width, child: content),
                ),
              ),
            ],
          ),
        ),
        if (below != null)
          Positioned(
            left: MsSizes.pageInset,
            width: width,
            bottom: 0,
            height: MsSizes.barFromBottom - MsSizes.barHeight / 2 - 12,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxHeight: double.infinity,
                child: Faded(child: below!),
              ),
            ),
          ),
      ],
    );
  }
}

/// The XMB column below the bar: desaturated and dimmed.
class Faded extends StatelessWidget {
  const Faded({super.key, required this.child});

  final Widget child;

  static const _greyscale = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.5,
        child: ColorFiltered(colorFilter: _greyscale, child: child),
      ),
    );
  }
}
