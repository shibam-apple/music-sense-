import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_sense/library/library.dart';
import 'package:music_sense/library/models.dart';
import 'package:music_sense/main.dart';
import 'package:music_sense/playback/demo_player.dart';
import 'package:music_sense/sources/youtube_music/account.dart';
import 'package:music_sense/sources/youtube_music/youtube_music_source.dart';

/// YouTube Music with canned search results instead of the network.
class _FakeYouTube extends YouTubeMusicSource {
  _FakeYouTube({super.account});

  final queries = <String>[];

  @override
  Future<List<Track>> search(String query) async {
    queries.add(query);
    return const [
      Track(
        id: '4D7u5KF7SP8',
        source: 'ytm',
        title: 'Get Lucky',
        artist: 'Daft Punk',
        album: 'Random Access Memories',
        duration: Duration(minutes: 4),
        artwork: PaintedArtwork(ArtStyle.futuristic),
      ),
      Track(
        id: 'a5uQMwRMHcs',
        source: 'ytm',
        title: 'Instant Crush',
        artist: 'Daft Punk',
        album: 'Random Access Memories',
        duration: Duration(minutes: 4),
        artwork: PaintedArtwork(ArtStyle.lake),
      ),
    ];
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('search finds YouTube Music songs as you type', (tester) async {
    tester.view.physicalSize = const Size(390, 845);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final account = YouTubeAccount();
    final youtube = _FakeYouTube(account: account);
    addTearDown(youtube.close);
    final library = LibraryController([youtube]);
    final player = DemoPlayer(library.recent);
    addTearDown(player.dispose);
    await tester.pumpWidget(
      MusicSenseApp(player: player, library: library, account: account),
    );
    await settle(tester);

    await tester.tap(find.bySemanticsLabel('Search'));
    await settle(tester);
    expect(find.text('search'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'get lucky');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);

    expect(youtube.queries, ['get lucky']);
    expect(find.text('youtube music'), findsOneWidget);
    expect(find.text('Get Lucky'), findsOneWidget);

    await tester.tap(find.text('Get Lucky'));
    await settle(tester);
    expect(player.track?.title, 'Get Lucky');
    player.pause();
    await settle(tester);
  });

  testWidgets('Artist page lists YouTube songs and starts a DJ set', (tester) async {
    tester.view.physicalSize = const Size(390, 845);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final account = YouTubeAccount();
    final youtube = _FakeYouTube(account: account);
    addTearDown(youtube.close);
    final library = LibraryController([youtube]);
    final player = DemoPlayer(library.recent);
    addTearDown(player.dispose);
    player.beatSenseEnabled = false;
    await tester.pumpWidget(
      MusicSenseApp(player: player, library: library, account: account),
    );
    await settle(tester);

    await tester.tap(find.bySemanticsLabel('Artist'));
    await settle(tester);
    final scroll = find.byType(Scrollable).hitTestable().first;
    await tester.scrollUntilVisible(
      find.text('on youtube music'),
      200,
      scrollable: scroll,
    );
    await settle(tester);
    expect(find.text('Get Lucky'), findsOneWidget);

    await tester.tap(find.text('DJ'));
    await settle(tester);
    expect(player.beatSenseEnabled, isTrue);
    expect(player.djMode, isTrue);
    expect(player.track?.title, 'Get Lucky');
    player.pause();
    await settle(tester);
  });
}
