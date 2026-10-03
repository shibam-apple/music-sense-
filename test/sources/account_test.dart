import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_sense/sources/youtube_music/account.dart';

void main() {
  test('signed-in headers carry the cookies and a SAPISIDHASH', () {
    final account = YouTubeAccount.withCookies(
      'SID=a; HSID=b; SAPISID=secret123; __Secure-3PAPISID=x',
    );
    final h = account.headers();
    expect(h['Cookie'], contains('SAPISID=secret123'));
    expect(h['X-Origin'], YouTubeAccount.origin);
    final auth = h['Authorization']!;
    expect(auth, startsWith('SAPISIDHASH '));
    final parts = auth.substring('SAPISIDHASH '.length).split('_');
    final ts = parts[0];
    final expected = sha1
        .convert(utf8.encode('$ts secret123 ${YouTubeAccount.origin}'))
        .toString();
    expect(parts[1], expected);
  });

  test('signed out sends nothing', () {
    expect(YouTubeAccount().headers(), isEmpty);
    expect(YouTubeAccount().signedIn, isFalse);
  });
}
