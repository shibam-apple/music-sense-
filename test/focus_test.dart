import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_sense/library/library.dart';
import 'package:music_sense/main.dart';
import 'package:music_sense/playback/demo_player.dart';
import 'package:music_sense/sources/youtube_music/account.dart';
import 'package:music_sense/theme/tokens.dart';
import 'package:music_sense/widgets/panorama.dart';

void main() {
  testWidgets('only the two rows above the bar are in focus after scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 845);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final library = LibraryController(const []);
    final player = DemoPlayer(library.recent);
    addTearDown(player.dispose);
    await tester.pumpWidget(
      MusicSenseApp(
        player: player,
        library: library,
        account: YouTubeAccount(),
      ),
    );
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.drag(find.text('Alpine Lake').first, const Offset(0, -400));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    const barTop = 845 - MsSizes.barFromBottom - MsSizes.barHeight / 2;
    var crisp = 0;
    for (final e in find.byType(ColumnFocus).evaluate()) {
      final box = e.renderObject! as RenderBox;
      final at = box.localToGlobal(Offset.zero);
      if (at.dx > 100) continue; // rows of the page peeking in on the right
      final centre = at.dy + box.size.height / 2;
      if (centre > barTop) continue; // under the bar's wash
      final fades = find.descendant(
        of: find.byWidget(e.widget),
        matching: find.byType(Opacity),
      );
      final opacity = fades.evaluate().isEmpty
          ? 1.0
          : (fades.evaluate().first.widget as Opacity).opacity;
      if (opacity > 0.95) crisp++;
    }
    expect(crisp, 2);
  });
}
