import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../library/library.dart';
import '../library/models.dart';
import '../playback/playback_controller.dart';
import '../theme/tokens.dart';
import '../widgets/tiles.dart';

/// Search: songs on this phone and on YouTube Music, as you type.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: MsMotion.medium,
      reverseTransitionDuration: MsMotion.fast,
      pageBuilder: (_, _, _) => const SearchPage(),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: MsMotion.emphasized),
              ),
          child: child,
        ),
      ),
    ),
  );

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _query = TextEditingController();
  Timer? _debounce;
  int _generation = 0;
  List<Track> _local = const [];
  List<Track> _online = const [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _debounce?.cancel();
    final q = text.trim().toLowerCase();
    final library = LibraryScope.read(context);
    setState(() {
      _local = q.isEmpty
          ? const []
          : library.tracks
                .where(
                  (t) =>
                      t.source == 'local' &&
                      ('${t.title} ${t.artist} ${t.album ?? ''}')
                          .toLowerCase()
                          .contains(q),
                )
                .take(4)
                .toList();
      if (q.isEmpty) {
        _online = const [];
        _error = null;
      }
    });
    if (q.isEmpty || library.youtube == null) return;
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    final youtube = LibraryScope.read(context).youtube;
    if (youtube == null) return;
    final generation = ++_generation;
    setState(() => _searching = true);
    try {
      final found = await youtube.search(q);
      if (!mounted || generation != _generation) return;
      setState(() {
        _online = found;
        _error = null;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(
        () => _error = 'Couldn\'t search YouTube Music. Check your connection.',
      );
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _searching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final hasYouTube = LibraryScope.of(context).youtube != null;
    final top = MediaQuery.paddingOf(context).top;
    const inset = MsSizes.pageInset;

    Widget section(String title, List<Track> songs) => SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(inset, 22, inset, 12),
            child: Text(title, style: MsText.pageTitle.copyWith(fontSize: 19)),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: inset),
          sliver: SliverList.separated(
            itemCount: songs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (context, i) {
              final t = songs[i];
              return Reveal(
                key: ValueKey(t.key),
                order: i.clamp(0, 6),
                child: MediaRow(
                  art: t.artwork,
                  title: t.title,
                  subtitle: t.album == null
                      ? t.byline
                      : '${t.byline} · ${t.album}',
                  active: player.track == t,
                  onTap: () => player.playTracks(songs, start: i),
                ),
              );
            },
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: MsColors.background,
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(inset - 10, top + 10, 16, 0),
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    label: 'Back',
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
                  const SizedBox(width: 4),
                  const Text('search', style: MsText.pageTitle),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(inset, 16, inset, 0),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: MsColors.tileLight,
                  borderRadius: BorderRadius.circular(MsSizes.tileRadius + 2),
                ),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.search300,
                      size: 18,
                      color: MsColors.inkSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _query,
                        autofocus: true,
                        onChanged: _changed,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (q) {
                          _debounce?.cancel();
                          if (q.trim().isNotEmpty) _search(q.trim());
                        },
                        cursorColor: MsColors.accent,
                        style: MsText.rowTitle,
                        decoration: InputDecoration.collapsed(
                          hintText: hasYouTube
                              ? 'Songs, artists, albums'
                              : 'Songs on this phone',
                          hintStyle: MsText.rowTitle.copyWith(
                            color: MsColors.inkTertiary,
                          ),
                        ),
                      ),
                    ),
                    if (_searching)
                      const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: MsColors.accent,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_local.isNotEmpty) section('on this phone', _local),
          if (_online.isNotEmpty) section('youtube music', _online),
          if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(inset, 24, inset, 0),
                child: Text(_error!, style: MsText.rowSubtitle),
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 40),
          ),
        ],
      ),
    );
  }
}
