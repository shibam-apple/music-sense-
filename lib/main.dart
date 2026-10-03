import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:async';

import 'library/library.dart';
import 'pages/account_page.dart';
import 'sources/youtube_music/account.dart';
import 'playback/analysis_service.dart';
import 'playback/audio_handler.dart';
import 'playback/demo_player.dart';
import 'playback/mix_engine.dart';
import 'playback/playback_controller.dart';
import 'shell.dart';
import 'sources/local_source.dart';
import 'sources/music_source.dart';
import 'sources/youtube_music/youtube_music_source.dart';
import 'theme/tokens.dart';
import 'widgets/ambient.dart';
import 'widgets/artwork.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintedArtCache.warmUp();
  final device = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final account = YouTubeAccount();
  await account.load();
  final youtube = device && kYouTubeMusicEnabled
      ? YouTubeMusicSource(account: account)
      : null;
  final sources = <MusicSource>[if (device) LocalSource(), ?youtube];
  final analysis = AnalysisService({for (final s in sources) s.id: s});
  final library = LibraryController(sources, analysisOf: analysis.cached);

  final PlaybackController player;
  if (device) {
    player = MixEngine(
      sources: {for (final s in sources) s.id: s},
      analysis: analysis,
    );
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await AudioService.init(
      builder: () => MusicSenseAudioHandler(player),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.musicsense.playback',
        androidNotificationChannelName: 'Music Sense',
        androidNotificationOngoing: true,
      ),
    );
  } else {
    // Web preview and tests: the design's samples on a silent clock.
    player = DemoPlayer(library.recent);
  }
  await library.stats.attach(player);

  runApp(MusicSenseApp(player: player, library: library, account: account));
  if (device) {
    unawaited(youtube?.refreshProfile());
    await library.load();
  }
}

class MusicSenseApp extends StatelessWidget {
  const MusicSenseApp({
    super.key,
    required this.player,
    required this.library,
    required this.account,
  });

  final PlaybackController player;
  final LibraryController library;
  final YouTubeAccount account;

  @override
  Widget build(BuildContext context) {
    return AccountScope(
      account: account,
      child: PlayerScope(
        player: player,
        child: LibraryScope(
          library: library,
          child: NowPlayingAccent(
            child: BeatClock(
              child: MaterialApp(
                title: 'Music Sense',
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  fontFamily: MsText.family,
                  scaffoldBackgroundColor: MsColors.background,
                  splashFactory: NoSplash.splashFactory,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: MsColors.accent,
                    primary: MsColors.accent,
                    surface: MsColors.background,
                  ),
                ),
                home: const AnnotatedRegion<SystemUiOverlayStyle>(
                  value: SystemUiOverlayStyle(
                    statusBarColor: Color(0x00000000),
                    statusBarIconBrightness: Brightness.dark,
                    systemNavigationBarColor: Color(0x00000000),
                    systemNavigationBarIconBrightness: Brightness.dark,
                  ),
                  child: _Frame(child: PanoramaShell()),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// On wide windows (desktop, web) the phone layout is centred on a soft
/// canvas until tablet and desktop layouts are designed.
class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  static const _maxWidth = 430.0;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > _maxWidth + 40;
    return ColoredBox(
      color: wide ? const Color(0xFFF1F1F3) : MsColors.background,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(wide ? 28 : 0),
            child: Material(color: MsColors.background, child: child),
          ),
        ),
      ),
    );
  }
}
