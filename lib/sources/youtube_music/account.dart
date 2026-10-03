import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../local_source.dart';

/// The listener's YouTube Music sign-in. The session is the cookie set
/// Google gives the sign-in page; it is kept in the Android Keystore
/// (encrypted) and only ever sent to YouTube.
class YouTubeAccount extends ChangeNotifier {
  YouTubeAccount({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  @visibleForTesting
  YouTubeAccount.withCookies(String cookies, {FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(),
      _cookies = cookies;

  static const _key = 'ytm_cookies';
  static const origin = 'https://music.youtube.com';

  final FlutterSecureStorage _storage;
  String? _cookies;
  String? name;
  String? handle;
  String? photo;

  bool get signedIn => _cookies != null;

  Future<void> load() async {
    try {
      _cookies = await _storage.read(key: _key);
    } catch (_) {
      _cookies = null;
    }
    notifyListeners();
  }

  /// Reads the session the sign-in WebView left in Android's cookie store.
  /// Returns false while the page hasn't signed in yet.
  Future<bool> captureFromWebView() async {
    final cookies = await LocalSource.channel.invokeMethod<String>(
      'getCookies',
      {'url': origin},
    );
    if (cookies == null || _cookieValue(cookies, 'SAPISID') == null) {
      return false;
    }
    _cookies = cookies;
    await _storage.write(key: _key, value: cookies);
    notifyListeners();
    return true;
  }

  Future<void> signOut() async {
    _cookies = null;
    name = handle = photo = null;
    await _storage.delete(key: _key);
    try {
      await LocalSource.channel.invokeMethod('clearCookies');
    } on MissingPluginException {
      // Not on a device.
    }
    notifyListeners();
  }

  void setProfile({String? name, String? handle, String? photo}) {
    this.name = name;
    this.handle = handle;
    this.photo = photo;
    notifyListeners();
  }

  /// Headers that make InnerTube treat a request as the signed-in user:
  /// the cookies plus a SAPISIDHASH, as music.youtube.com itself sends.
  Map<String, String> headers({String forOrigin = origin}) {
    final cookies = _cookies;
    if (cookies == null) return const {};
    final sapisid =
        _cookieValue(cookies, 'SAPISID') ??
        _cookieValue(cookies, '__Secure-3PAPISID');
    final out = <String, String>{'Cookie': cookies};
    if (sapisid != null) {
      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final hash = sha1.convert(utf8.encode('$ts $sapisid $forOrigin'));
      out['Authorization'] = 'SAPISIDHASH ${ts}_$hash';
      out['X-Origin'] = forOrigin;
      out['X-Goog-AuthUser'] = '0';
    }
    return out;
  }

  /// Cookies only (for youtube.com requests made by the stream resolver).
  String? get cookieHeader => _cookies;

  static String? _cookieValue(String cookies, String name) {
    for (final part in cookies.split(';')) {
      final i = part.indexOf('=');
      if (i > 0 && part.substring(0, i).trim() == name) {
        return part.substring(i + 1).trim();
      }
    }
    return null;
  }
}

/// An HTTP client that adds the signed-in session to YouTube requests, so
/// stream lookups count as the user's rather than an anonymous robot's.
class SignedInClient extends http.BaseClient {
  SignedInClient(this.account, [http.Client? inner])
    : _inner = inner ?? http.Client();

  final YouTubeAccount account;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final host = request.url.host;
    final cookies = account.cookieHeader;
    if (cookies != null &&
        (host.endsWith('youtube.com') || host.endsWith('google.com'))) {
      request.headers.putIfAbsent('Cookie', () => cookies);
      final origin =
          'https://${host == 'music.youtube.com' ? host : 'www.youtube.com'}';
      account.headers(forOrigin: origin).forEach((k, v) {
        if (k != 'Cookie') request.headers.putIfAbsent(k, () => v);
      });
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
