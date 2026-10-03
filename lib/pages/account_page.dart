import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../library/library.dart';
import '../playback/playback_controller.dart';
import '../sources/youtube_music/account.dart';
import '../theme/tokens.dart';
import '../widgets/panorama.dart';
import '../widgets/tiles.dart';
import 'sign_in_page.dart';

/// 7 · Account — YouTube Music sign-in and the app's few settings, as
/// Metro tiles like every other page.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.of(context);
    final library = LibraryScope.of(context);
    final player = PlayerScope.of(context);
    final youtube = library.youtube;

    Future<void> signIn() => signInToYouTube(context);

    Future<void> signOut() async {
      await account.signOut();
      await library.load();
      player.message.value = 'Signed out of YouTube Music.';
    }

    final beatSense = MetroTile(
      tone: TileTone.light,
      icon: LucideIcons.audioWaveform300,
      label: 'Beat Sense',
      caption: player.beatSenseEnabled ? 'On' : 'Off',
      onTap: () => player.beatSenseEnabled = !player.beatSenseEnabled,
    );

    return PanoramaPage(
      id: 'account',
      title: 'account',
      header: TileGrid(
        rows: [
          if (account.signedIn) ...[
            TileRow(height: 1.2, [
              TileColumn(span: 3, [_ProfileTile(account: account)]),
            ]),
            TileRow(height: 1.5, [
              TileColumn(span: 1.5, [
                MetroTile(
                  tone: TileTone.accent,
                  number: '${library.liked.length}',
                  label: 'liked songs',
                  onTap: library.liked.isEmpty
                      ? null
                      : () => player.playTracks(library.liked),
                ),
              ]),
              TileColumn(span: 1.5, [beatSense]),
            ]),
            TileRow([
              TileColumn(span: 3, [
                MetroTile(
                  tone: TileTone.light,
                  icon: LucideIcons.logOut300,
                  label: 'Sign out',
                  caption: 'YouTube Music',
                  onTap: signOut,
                ),
              ]),
            ]),
          ] else ...[
            TileRow(height: 1.5, [
              TileColumn(span: 3, [
                MetroTile(
                  tone: TileTone.accent,
                  icon: LucideIcons.logIn300,
                  label: 'Sign in to YouTube Music',
                  caption: 'Your liked songs, mixes and streams',
                  onTap: youtube == null ? null : signIn,
                ),
              ]),
            ]),
            TileRow(height: 1.5, [
              TileColumn(span: 1.5, [beatSense]),
              TileColumn(span: 1.5, [
                MetroTile(
                  number: '${library.localCount}',
                  label: 'on this phone',
                ),
              ]),
            ]),
          ],
        ],
      ),
    );
  }
}

/// Opens Google sign-in for YouTube Music, then reloads the library with
/// the signed-in account. Used by the grey sign-in tiles.
Future<void> signInToYouTube(BuildContext context) async {
  final account = AccountScope.of(context);
  final library = LibraryScope.of(context);
  final player = PlayerScope.of(context);
  if (await SignInPage.open(context, account)) {
    await library.youtube?.refreshProfile();
    await library.load();
    player.message.value = 'Signed in to YouTube Music.';
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.account});

  final YouTubeAccount account;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MsColors.tileDark,
        borderRadius: BorderRadius.circular(MsSizes.tileRadius),
      ),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox.square(
              dimension: 52,
              child: account.photo == null
                  ? const ColoredBox(
                      color: MsColors.accent,
                      child: Icon(
                        LucideIcons.user300,
                        color: Colors.white,
                        size: 24,
                      ),
                    )
                  : Image.network(account.photo!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name ?? 'Signed in',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MsText.tileLabel.copyWith(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  account.handle ?? 'YouTube Music',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MsText.tileCaption.copyWith(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AccountScope extends InheritedNotifier<YouTubeAccount> {
  const AccountScope({
    super.key,
    required YouTubeAccount account,
    required super.child,
  }) : super(notifier: account);

  static YouTubeAccount of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountScope>()!.notifier!;
}
