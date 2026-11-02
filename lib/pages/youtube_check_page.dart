import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../library/library.dart';
import '../library/models.dart';
import '../playback/playback_controller.dart';
import '../theme/tokens.dart';
import '../widgets/tiles.dart';

/// Checks YouTube Music on this phone, step by step: search, finding the
/// audio, downloading it, playing it. The report can be copied and sent
/// when something fails.
class YouTubeCheckPage extends StatefulWidget {
  const YouTubeCheckPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const YouTubeCheckPage()));

  @override
  State<YouTubeCheckPage> createState() => _YouTubeCheckPageState();
}

class _YouTubeCheckPageState extends State<YouTubeCheckPage> {
  final _lines = <(String, bool?)>[]; // text, passed (null: running)
  Track? _song;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  void _log(String text, [bool? ok]) {
    if (mounted) setState(() => _lines.add((text, ok)));
  }

  Future<void> _run() async {
    final library = LibraryScope.read(context);
    final youtube = library.youtube;
    setState(() {
      _lines.clear();
      _running = true;
      _song = null;
    });
    if (youtube == null) {
      _log('YouTube Music is not part of this build.', false);
      setState(() => _running = false);
      return;
    }
    _log(
      youtube.signedIn ? 'Signed in to YouTube Music' : 'Not signed in',
      true,
    );
    try {
      final found = await youtube.search('Daft Punk Get Lucky');
      if (found.isEmpty) throw StateError('no results');
      _song = found.first;
      _log('Search works: "${_song!.title}"', true);
    } catch (e) {
      _log('Search failed: $e', false);
      setState(() => _running = false);
      return;
    }
    final report = await youtube.diagnose(_song!.id);
    for (final line in report.split('\n').where((l) => l.trim().isNotEmpty)) {
      final ok = line.contains('HTTP 200') || line.contains('HTTP 206');
      _log(line, ok);
    }
    try {
      final watch = Stopwatch()..start();
      final ref = await youtube.resolve(_song!);
      _log(
        'Song ready to play in ${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s'
        '${ref.uri.scheme == 'file' ? ' (saved on the phone)' : ' (streaming)'}',
        true,
      );
    } catch (e) {
      _log('Couldn\'t get the song: $e', false);
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    const inset = MsSizes.pageInset;
    final report = _lines.map((l) => l.$1).join('\n');

    return Scaffold(
      backgroundColor: MsColors.background,
      body: ListView(
        padding: EdgeInsets.fromLTRB(inset, top + 10, inset, 40),
        children: [
          Row(
            children: [
              Transform.translate(
                offset: const Offset(-10, 0),
                child: Pressable(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const SizedBox.square(
                    dimension: 44,
                    child: Icon(
                      LucideIcons.chevronLeft300,
                      size: 26,
                      color: MsColors.ink,
                    ),
                  ),
                ),
              ),
              const Text('youtube check', style: MsText.pageTitle),
            ],
          ),
          const SizedBox(height: 22),
          for (final (text, ok) in _lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    ok == true
                        ? LucideIcons.circleCheck300
                        : LucideIcons.circleAlert300,
                    size: 18,
                    color: ok == true
                        ? MsColors.accent
                        : const Color(0xFFE0605A),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      style: MsText.rowTitle.copyWith(fontSize: 13.5),
                    ),
                  ),
                ],
              ),
            ),
          if (_running)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: MsColors.accent,
                backgroundColor: MsColors.track,
              ),
            ),
          const SizedBox(height: 20),
          SizedBox(
            height: 120,
            child: TileGrid(
              rows: [
                TileRow([
                  TileColumn([
                    MetroTile(
                      tone: TileTone.accent,
                      icon: Icons.play_arrow_rounded,
                      label: 'Play it',
                      onTap: _song == null || _running
                          ? null
                          : () =>
                                PlayerScope.read(context).playTracks([_song!]),
                    ),
                  ]),
                  TileColumn([
                    MetroTile(
                      icon: LucideIcons.rotateCw300,
                      label: 'Run again',
                      onTap: _running ? null : _run,
                    ),
                  ]),
                  TileColumn([
                    MetroTile(
                      tone: TileTone.light,
                      icon: LucideIcons.copy300,
                      label: 'Copy report',
                      onTap: report.isEmpty
                          ? null
                          : () {
                              Clipboard.setData(ClipboardData(text: report));
                              PlayerScope.read(context).message.value =
                                  'Report copied';
                            },
                    ),
                  ]),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
