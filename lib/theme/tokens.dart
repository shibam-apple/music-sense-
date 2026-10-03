import 'package:flutter/material.dart';

/// Design tokens taken from the Music Sense design (XMB × Metro).
///
/// The design is drawn on a 390 × 845 phone frame; all sizes are logical px.
abstract final class MsColors {
  static const background = Color(0xFFFFFFFF);
  static const ink = Color(0xFF0B0A0F);
  static const inkSecondary = Color(0xFF8A8992);
  static const inkTertiary = Color(0xFFB4B3BA);
  static const accent = Color(0xFF6F56F8);
  static const accentSoft = Color(0xFFB9ADFF);
  static const tileDark = Color(0xFF0B0A0F);
  static const tileLight = Color(0xFFF3F2F7);
  static const track = Color(0xFFE9E8EE);
  static const wave = Color(0xFFD9D3FA);
  static const iconIdle = Color(0xFFA3A2AA);
}

abstract final class MsSizes {
  /// Left inset of every panorama page.
  static const pageInset = 32.0;

  /// Width of the content column inside a page.
  static const contentWidth = 276.0;

  /// Distance from one page's left edge to the next. The rest of the screen
  /// shows the next page peeking in, as in a Metro panorama.
  static const pageStride = 318.0;

  /// Top of the page title.
  static const titleTop = 92.0;

  /// Gap between Metro tiles.
  static const tileGap = 8.0;
  static const tileRadius = 10.0;

  /// Vertical centre of the XMB icon bar, measured from the bottom.
  static const barFromBottom = 168.0;
  static const barHeight = 96.0;

  /// Where the pages' column ends, measured from the bottom: just above
  /// the XMB icons. Nothing scrolls behind the bar.
  static const columnBottom = barFromBottom + 26;

  /// Height of the soft edge where the column meets the bar.
  static const columnFade = 34.0;

  /// The dock under the bar, measured from the bottom to its top edge.
  static const dockTop = barFromBottom - barHeight / 2 - 6;

  /// Horizontal distance between XMB icons and the x of the active slot.
  static const barSpacing = 65.0;
  static const barSlotX = 63.0;
}

abstract final class MsText {
  static const family = 'Inter';

  static const pageTitle = TextStyle(
    fontFamily: family,
    fontSize: 27,
    fontWeight: FontWeight.w300,
    letterSpacing: -0.6,
    color: MsColors.ink,
    height: 1.1,
  );

  static const heroTitle = TextStyle(
    fontFamily: family,
    fontSize: 34,
    fontWeight: FontWeight.w300,
    letterSpacing: -1.0,
    color: MsColors.ink,
    height: 1.1,
  );

  static const songTitleLarge = TextStyle(
    fontFamily: family,
    fontSize: 23,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: MsColors.ink,
  );

  static const rowTitle = TextStyle(
    fontFamily: family,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
    color: MsColors.ink,
  );

  static const rowSubtitle = TextStyle(
    fontFamily: family,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: MsColors.inkSecondary,
  );

  static const tileNumber = TextStyle(
    fontFamily: family,
    fontSize: 30,
    fontWeight: FontWeight.w300,
    letterSpacing: -0.8,
    height: 1.0,
  );

  static const tileLabel = TextStyle(
    fontFamily: family,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  static const tileCaption = TextStyle(
    fontFamily: family,
    fontSize: 10.5,
    fontWeight: FontWeight.w400,
  );

  static const overline = TextStyle(
    fontFamily: family,
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: MsColors.accent,
  );

  static const barLabel = TextStyle(
    fontFamily: family,
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    color: MsColors.ink,
  );

  static const time = TextStyle(
    fontFamily: family,
    fontSize: 10.5,
    fontWeight: FontWeight.w400,
    color: MsColors.inkSecondary,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

abstract final class MsMotion {
  static const fast = Duration(milliseconds: 220);
  static const medium = Duration(milliseconds: 420);
  static const slow = Duration(milliseconds: 700);
  static const curve = Curves.easeOutCubic;
  static const emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
}
