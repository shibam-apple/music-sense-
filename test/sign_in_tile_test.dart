import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_sense/library/library.dart';
import 'package:music_sense/main.dart';
import 'package:music_sense/playback/demo_player.dart';
import 'package:music_sense/sources/youtube_music/account.dart';
import 'package:music_sense/sources/youtube_music/youtube_music_source.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets(
    'signed out, Featured offers YouTube Music sign-in in its grey tile',
    (tester) async {
      tester.view.physicalSize = const Size(390, 845);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final account = YouTubeAccount();
      final youtube = YouTubeMusicSource(account: account);
      addTearDown(youtube.close);
      final library = LibraryController([youtube]);
      final player = DemoPlayer(library.recent);
      addTearDown(player.dispose);
      await tester.pumpWidget(
        MusicSenseApp(player: player, library: library, account: account),
      );
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Featured'));
      await settle(tester);
      expect(find.text('Sign in to YouTube Music'), findsWidgets);
      expect(find.text('Concerts near you'), findsNothing);
    },
  );
}
