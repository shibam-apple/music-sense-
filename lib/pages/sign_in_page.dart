import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../sources/youtube_music/account.dart';
import '../theme/tokens.dart';
import '../widgets/tiles.dart';

/// Google's own sign-in page for YouTube Music, in a WebView. Music Sense
/// never sees the password: once Google redirects back to YouTube Music,
/// the session cookies are read from Android's cookie store and kept,
/// encrypted, on the phone.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.account});

  final YouTubeAccount account;

  static Future<bool> open(BuildContext context, YouTubeAccount account) async {
    final ok = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        transitionDuration: MsMotion.medium,
        reverseTransitionDuration: MsMotion.fast,
        pageBuilder: (_, _, _) => SignInPage(account: account),
        transitionsBuilder: (_, animation, _, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: MsMotion.emphasized),
              ),
          child: FadeTransition(opacity: animation, child: child),
        ),
      ),
    );
    return ok ?? false;
  }

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  static const _start =
      'https://accounts.google.com/ServiceLogin?ltmpl=music&service=youtube'
      '&passive=true&continue=https%3A%2F%2Fmusic.youtube.com%2F';

  // A plain Chrome user agent: Google refuses sign-in from agents that
  // announce an embedded WebView.
  static const _agent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/129.0.0.0 Mobile Safari/537.36';

  late final WebViewController _web;
  double _progress = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_agent)
      ..setBackgroundColor(MsColors.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p / 100),
          onPageFinished: _check,
          onUrlChange: (change) => _check(change.url ?? ''),
        ),
      )
      ..loadRequest(Uri.parse(_start));
  }

  Future<void> _check(String url) async {
    if (_done || !url.startsWith(YouTubeAccount.origin)) return;
    if (await widget.account.captureFromWebView()) {
      _done = true;
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MsColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(MsSizes.pageInset, 18, 16, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('sign in', style: MsText.pageTitle),
                  ),
                  Semantics(
                    button: true,
                    label: 'Close',
                    child: Pressable(
                      onTap: () => Navigator.of(context).pop(false),
                      child: const SizedBox.square(
                        dimension: 40,
                        child: Icon(
                          LucideIcons.x300,
                          size: 22,
                          color: MsColors.ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MsSizes.pageInset,
              ),
              child: Text(
                'Sign in with Google to play YouTube Music. Your password goes '
                'only to Google.',
                style: MsText.rowSubtitle.copyWith(fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            AnimatedOpacity(
              opacity: _progress < 1 ? 1 : 0,
              duration: MsMotion.fast,
              child: LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                minHeight: 2,
                color: MsColors.accent,
                backgroundColor: MsColors.track,
              ),
            ),
            Expanded(child: WebViewWidget(controller: _web)),
          ],
        ),
      ),
    );
  }
}
