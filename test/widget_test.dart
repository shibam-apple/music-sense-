import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_sense/main.dart';

/// The wave animates forever, so pumpAndSettle never returns; step frames.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  Future<void> pumpPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 845);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MusicSenseApp());
    await settle(tester);
  }

  testWidgets('opens on the music collection with the XMB bar',
      (tester) async {
    await pumpPhone(tester);
    expect(find.text('music collection'), findsOneWidget);
    expect(find.text('NOW PLAYING'), findsOneWidget);
    for (final label in ['Music', 'Albums', 'Featured', 'New', 'Playing']) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('tapping a bar icon moves the panorama to that page',
      (tester) async {
    await pumpPhone(tester);
    await tester.tap(find.bySemanticsLabel('Featured'));
    await settle(tester);
    expect(find.text('featured'), findsOneWidget);
    expect(find.text('Concerts near you'), findsOneWidget);
  });

  testWidgets('swiping left moves to the next page', (tester) async {
    await pumpPhone(tester);
    await tester.fling(
        find.text('music collection'), const Offset(-200, 0), 1200);
    await settle(tester);
    final albums = tester.getTopLeft(find.text('albums'));
    expect(albums.dx, closeTo(32, 1));
  });

  testWidgets('play / pause toggles on the playing page', (tester) async {
    await pumpPhone(tester);
    await tester.tap(find.bySemanticsLabel('Playing'));
    await settle(tester);
    expect(find.bySemanticsLabel('Play'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.pump(const Duration(seconds: 1));
  });
}
