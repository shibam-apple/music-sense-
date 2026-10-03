import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'shell.dart';
import 'state/player.dart';
import 'theme/tokens.dart';

void main() {
  runApp(const MusicSenseApp());
}

class MusicSenseApp extends StatefulWidget {
  const MusicSenseApp({super.key});

  @override
  State<MusicSenseApp> createState() => _MusicSenseAppState();
}

class _MusicSenseAppState extends State<MusicSenseApp> {
  final _player = PlayerState();

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerScope(
      player: _player,
      child: MaterialApp(
        title: 'Music Sense',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: MsText.family,
          scaffoldBackgroundColor: MsColors.background,
          colorScheme: ColorScheme.fromSeed(
            seedColor: MsColors.accent,
            primary: MsColors.accent,
            surface: MsColors.background,
          ),
        ),
        home: const AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark,
          child: _Frame(child: PanoramaShell()),
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
