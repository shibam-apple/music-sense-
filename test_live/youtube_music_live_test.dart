// ignore_for_file: avoid_print
// Live checks against YouTube Music. Needs internet access to YouTube, so
// it runs in CI (`flutter test test_live`), not in the normal test suite.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:music_sense/library/models.dart';
import 'package:music_sense/sources/youtube_music/innertube.dart';
import 'package:music_sense/sources/youtube_music/youtube_music_source.dart';

void main() {
  final source = YouTubeMusicSource();
  final api = InnerTubeClient();
  tearDownAll(() {
    source.close();
    api.close();
  });

  void describe(String what, Map<String, dynamic> json) {
    final top = json.keys.join(', ');
    final renderers = <String>{};
    void walk(Object? n, int depth) {
      if (depth > 14) return;
      if (n is Map) {
        for (final e in n.entries) {
          if ((e.key as String).endsWith('Renderer')) {
            renderers.add(e.key as String);
          }
          walk(e.value, depth + 1);
        }
      } else if (n is List) {
        for (final v in n) {
          walk(v, depth + 1);
        }
      }
    }

    walk(json, 0);
    print('[$what] top-level keys: $top');
    print('[$what] renderers: ${renderers.take(40).join(', ')}');
  }

  late List<Track> searched;

  test('search returns songs', () async {
    final raw = await api.searchSongs('Daft Punk Get Lucky');
    describe('search', raw);
    searched = await source.search('Daft Punk Get Lucky');
    for (final t in searched.take(5)) {
      print(
        '  search: ${t.id} | ${t.title} | ${t.artist} | ${t.album} | ${t.duration} | ${(t.artwork as dynamic).url ?? ''}',
      );
    }
    expect(searched, isNotEmpty);
    expect(searched.first.id, hasLength(11));
  });

  test('home feed has shelves', () async {
    final raw = await api.home();
    describe('home', raw);
    final shelves = await source.home();
    for (final (title, songs) in shelves.take(6)) {
      print(
        '  shelf "$title": ${songs.length} songs, e.g. ${songs.take(2).map((s) => '${s.title} / ${s.artist}').join('; ')}',
      );
    }
    expect(shelves, isNotEmpty);
  });

  test('charts', () async {
    final raw = await api.charts();
    describe('charts', raw);
    final charts = await source.charts();
    print(
      '  charts: ${charts.length} songs, e.g. ${charts.take(3).map((s) => '${s.title} / ${s.artist}').join('; ')}',
    );
    expect(charts, isNotEmpty);
  });

  test('radio continues from a song', () async {
    final related = await source.related(searched.first);
    print(
      '  radio: ${related.length} songs, e.g. ${related.take(3).map((s) => '${s.title} / ${s.artist}').join('; ')}',
    );
    expect(related, isNotEmpty);
  });

  test('which stream clients work', () async {
    final results = await source.probe(searched.first.id);
    results.forEach((client, result) => print('  client $client: $result'));
  });

  test('stream resolves and downloads', () async {
    final t = searched.first;
    final ref = await source.resolve(t);
    print(
      '  stream host: ${ref.uri.host}, itag ${ref.uri.queryParameters['itag']}, mime ${ref.uri.queryParameters['mime']}',
    );
    final client = HttpClient();
    final req = await client.getUrl(ref.uri);
    ref.headers.forEach(req.headers.set);
    req.headers.set('Range', 'bytes=0-65535');
    final res = await req.close();
    final bytes = await res.fold<int>(0, (n, chunk) => n + chunk.length);
    print('  stream GET: HTTP ${res.statusCode}, $bytes bytes');
    client.close();
    expect(res.statusCode, anyOf(200, 206));
    expect(bytes, greaterThan(1000));
  });

  test('raw InnerTube search status', () async {
    final r = await http.post(
      Uri.parse(
        'https://music.youtube.com/youtubei/v1/search?prettyPrint=false',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20250929.01.00',
            'hl': 'en',
            'gl': 'US',
          },
        },
        'query': 'test',
      }),
    );
    print('  raw search: HTTP ${r.statusCode}, ${r.body.length} bytes');
  });
}
