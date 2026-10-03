import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:music_sense/main.dart' as app;
import 'package:music_sense/playback/analysis_service.dart';
import 'package:music_sense/playback/mix_engine.dart';
import 'package:music_sense/playback/playback_controller.dart';
import 'package:music_sense/sources/local_source.dart';

/// Runs on an Android device or emulator that has the two Beat Test songs
/// (tool/make_test_songs.sh) in its Music folder and audio permission
/// granted. Exercises the real decoder, analyser, players and UI.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(
    bool Function() done,
    Duration limit,
    String what,
  ) async {
    final end = DateTime.now().add(limit);
    while (!done()) {
      if (DateTime.now().isAfter(end)) fail('Timed out waiting for $what');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  testWidgets('finds, analyses and mixes local songs', (tester) async {
    final local = LocalSource();
    expect(await local.open(), isTrue, reason: 'audio permission');
    final songs =
        (await local.library())
            .where((t) => t.title.startsWith('Beat Test'))
            .toList()
          ..sort((a, b) => a.title.compareTo(b.title));
    expect(songs.map((t) => t.title), ['Beat Test 120', 'Beat Test 124']);
    expect(songs.first.artist, 'Music Sense Lab');
    expect(
      await LocalSource.artwork(int.parse(songs.first.id)),
      isNotNull,
      reason: 'embedded cover',
    );

    final analysis = AnalysisService({'local': local});
    final a = (await analysis.analyse(songs[0]))!;
    final b = (await analysis.analyse(songs[1]))!;
    debugPrint(
      'Beat Sense on device: ${a.bpm} BPM ${a.key}, ${b.bpm} BPM ${b.key}',
    );
    expect(a.bpm, closeTo(120, 1));
    expect(b.bpm, closeTo(124, 1));

    final engine = MixEngine(sources: {'local': local}, analysis: analysis);
    await engine.playTracks(songs);
    await waitFor(
      () => engine.beatSense.state == BeatSenseState.ready,
      const Duration(seconds: 30),
      'a planned transition',
    );
    final plan = engine.beatSense.plan!;
    debugPrint('Planned: $plan');
    expect(plan.beatMatched, isTrue);
    expect(plan.incomingRate, closeTo(120 / 124, 0.01));
    expect(engine.playing, isTrue);

    // Jump to just before the mix and let Beat Sense take over.
    final total = engine.duration.inMilliseconds / 1000;
    engine.seek((plan.exitAt - 3) / total);
    await waitFor(
      () => engine.beatSense.state == BeatSenseState.mixing,
      const Duration(seconds: 15),
      'the mix to start',
    );
    await waitFor(
      () => engine.index == 1,
      const Duration(seconds: 30),
      'the mix to finish',
    );
    expect(engine.track!.title, 'Beat Test 124');
    expect(engine.playing, isTrue);
    expect(engine.position.inMilliseconds / 1000, greaterThan(plan.entryAt));
    engine.pause();
    engine.dispose();
  });

  testWidgets('app shows the real library on every page', (tester) async {
    await app.main();
    // Let the library load and the entrance animations settle.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('music collection'), findsOneWidget);
    expect(find.textContaining('Beat Test'), findsWidgets);

    await binding.convertFlutterSurfaceToImage();
    const pages = ['Music', 'Albums', 'Featured', 'New', 'Playing', 'Artist'];
    for (final (i, label) in pages.indexed) {
      if (i > 0) await tester.tap(find.bySemanticsLabel(label));
      for (var f = 0; f < 25; f++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await binding.takeScreenshot('${i + 1}-${label.toLowerCase()}');
    }
  });
}
