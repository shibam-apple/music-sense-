import 'dart:convert';

import 'package:http/http.dart' as http;

/// Minimal client for YouTube Music's internal "InnerTube" API, the same
/// API music.youtube.com calls. Unofficial: YouTube can change it at any
/// time, which is why parsing lives in [InnerTubeParser] and is lenient.
class InnerTubeClient {
  InnerTubeClient({
    http.Client? client,
    this.language = 'en',
    this.region = 'US',
    this.auth,
  }) : _http = client ?? http.Client();

  /// Signed-in headers (cookies + SAPISIDHASH), when the user signed in.
  final Map<String, String> Function()? auth;

  final http.Client _http;
  final String language;
  final String region;

  static const _base = 'https://music.youtube.com/youtubei/v1';
  static const _clientVersion = '1.20250929.01.00';

  /// Search filter for songs only (not videos, albums or artists).
  static const songsFilter = 'EgWKAQIIAWoMEA4QChADEAQQCRAF';

  Map<String, Object> get _context => {
    'client': {
      'clientName': 'WEB_REMIX',
      'clientVersion': _clientVersion,
      'hl': language,
      'gl': region,
    },
  };

  Future<Map<String, dynamic>> call(
    String endpoint,
    Map<String, Object> body,
  ) async {
    final response = await _http.post(
      Uri.parse('$_base/$endpoint?prettyPrint=false'),
      headers: {
        'Content-Type': 'application/json',
        'Origin': 'https://music.youtube.com',
        'Referer': 'https://music.youtube.com/',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/129.0 Safari/537.36',
        'X-YouTube-Client-Name': '67',
        'X-YouTube-Client-Version': _clientVersion,
        ...?auth?.call(),
      },
      body: jsonEncode({'context': _context, ...body}),
    );
    if (response.statusCode != 200) {
      final body = response.body;
      throw InnerTubeException(
        endpoint,
        response.statusCode,
        body.length > 300 ? body.substring(0, 300) : body,
      );
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> searchSongs(String query) =>
      call('search', {'query': query, 'params': songsFilter});

  Future<Map<String, dynamic>> home() =>
      call('browse', {'browseId': 'FEmusic_home'});

  Future<Map<String, dynamic>> charts() =>
      call('browse', {'browseId': 'FEmusic_charts'});

  /// The signed-in user's liked songs.
  Future<Map<String, dynamic>> likedSongs() =>
      call('browse', {'browseId': 'FEmusic_liked_videos'});

  /// The account menu: name, handle and photo of the signed-in user.
  Future<Map<String, dynamic>> accountMenu() =>
      call('account/account_menu', {});

  /// A playlist or album page by its browse id (e.g. `VL…`).
  Future<Map<String, dynamic>> browse(String browseId) =>
      call('browse', {'browseId': browseId});

  /// The radio that YouTube Music plays after [videoId].
  Future<Map<String, dynamic>> radio(String videoId) => call('next', {
    'videoId': videoId,
    'playlistId': 'RDAMVM$videoId',
    'isAudioOnly': true,
  });

  void close() => _http.close();
}

class InnerTubeException implements Exception {
  InnerTubeException(this.endpoint, this.status, [this.detail = '']);

  final String endpoint;
  final int status;
  final String detail;

  @override
  String toString() => 'InnerTube $endpoint failed with HTTP $status $detail';
}

/// A song as InnerTube describes it.
class YtSong {
  const YtSong({
    required this.videoId,
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    this.thumbnail,
  });

  final String videoId;
  final String title;
  final String artist;
  final String? album;
  final Duration? duration;
  final String? thumbnail;
}

/// A titled row of songs from the home or charts page.
class YtShelf {
  const YtShelf(this.title, this.songs, {this.playlists = const []});

  final String title;
  final List<YtSong> songs;

  /// Browse ids of playlists in the row. Signed-out home and charts pages
  /// list playlists rather than songs; their songs are one browse away.
  final List<String> playlists;
}

/// Pulls songs out of InnerTube responses by looking for the item
/// renderers wherever they sit, so changes to the wrappers around them
/// don't break parsing.
abstract final class InnerTubeParser {
  static const _itemKeys = {
    'musicResponsiveListItemRenderer',
    'musicTwoRowItemRenderer',
    'playlistPanelVideoRenderer',
  };

  static List<YtSong> songs(Object? json) {
    final out = <YtSong>[];
    final seen = <String>{};
    _walk(json, (key, node) {
      if (!_itemKeys.contains(key)) return;
      final song = _song(key, node);
      if (song != null && seen.add(song.videoId)) out.add(song);
    });
    return out;
  }

  /// Home and charts: carousels with a title, their songs and playlists.
  static List<YtShelf> shelves(Object? json) {
    final out = <YtShelf>[];
    _walk(json, (key, node) {
      if (key != 'musicCarouselShelfRenderer' && key != 'musicShelfRenderer') {
        return;
      }
      final title =
          _text(
            _path(node, [
              'header',
              'musicCarouselShelfBasicHeaderRenderer',
              'title',
            ]),
          ) ??
          _text(node['title']) ??
          '';
      final list = songs(node['contents']);
      final lists = playlists(node['contents']);
      if (list.isNotEmpty || lists.isNotEmpty) {
        out.add(YtShelf(title, list, playlists: lists));
      }
    });
    return out;
  }

  /// Name, handle and photo from an account menu response.
  static ({String? name, String? handle, String? photo}) profile(Object? json) {
    String? name, handle, photo;
    _walk(json, (key, node) {
      if (key != 'activeAccountHeaderRenderer') return;
      name ??= _text(node['accountName']);
      handle ??= _text(node['channelHandle']) ?? _text(node['email']);
      final thumbs = _path(node, ['accountPhoto', 'thumbnails']);
      if (thumbs is List && thumbs.isNotEmpty) {
        photo ??= (thumbs.last as Map)['url'] as String?;
      }
    });
    return (name: name, handle: handle, photo: photo);
  }

  /// Playlist links with their titles, in order.
  static List<(String id, String title)> playlistItems(Object? json) {
    final out = <(String, String)>[];
    _walk(json, (key, node) {
      if (key != 'musicTwoRowItemRenderer' &&
          key != 'musicResponsiveListItemRenderer') {
        return;
      }
      final id = _path(node, [
        'navigationEndpoint',
        'browseEndpoint',
        'browseId',
      ]);
      if (id is! String || !id.startsWith('VL') || out.any((e) => e.$1 == id)) {
        return;
      }
      out.add((id, _text(node['title']) ?? ''));
    });
    return out;
  }

  /// Playlist browse ids (`VL…`) anywhere in [json], in order.
  static List<String> playlists(Object? json) {
    final out = <String>[];
    _walk(json, (key, node) {
      if (key != 'browseEndpoint') return;
      final id = node['browseId'];
      if (id is String && id.startsWith('VL') && !out.contains(id)) out.add(id);
    });
    return out;
  }

  static YtSong? _song(String key, Map<String, dynamic> node) {
    final videoId = _videoId(node);
    if (videoId == null) return null;

    String? title;
    final details = <Map>[];
    Duration? duration;

    switch (key) {
      case 'musicResponsiveListItemRenderer':
        final columns = (node['flexColumns'] as List?) ?? const [];
        final texts = [
          for (final c in columns)
            _runMaps(
              _path(c, ['musicResponsiveListItemFlexColumnRenderer', 'text']),
            ),
        ];
        if (texts.isNotEmpty && texts.first.isNotEmpty) {
          title = texts.first.map((r) => r['text']).join();
        }
        for (final (i, runs) in texts.skip(1).indexed) {
          if (i > 0 && runs.isNotEmpty) details.add(const {'text': ' • '});
          details.addAll(runs);
        }
        final fixed = (node['fixedColumns'] as List?) ?? const [];
        for (final c in fixed) {
          duration ??= _duration(
            _text(
              _path(c, ['musicResponsiveListItemFixedColumnRenderer', 'text']),
            ),
          );
        }
      case 'musicTwoRowItemRenderer':
        title = _text(node['title']);
        details.addAll(_runMaps(node['subtitle']));
      case 'playlistPanelVideoRenderer':
        title = _text(node['title']);
        details.addAll(
          _runMaps(node['longBylineText'] ?? node['shortBylineText']),
        );
        duration = _duration(_text(node['lengthText']));
    }
    if (title == null || title.isEmpty) return null;

    // Prefer YouTube's own link types: artist and album runs say so.
    String? artist, album;
    for (final run in details) {
      final type = _pageType(run);
      if (type == 'MUSIC_PAGE_TYPE_ARTIST' ||
          type == 'MUSIC_PAGE_TYPE_USER_CHANNEL') {
        artist ??= run['text'] as String;
      } else if (type == 'MUSIC_PAGE_TYPE_ALBUM') {
        album ??= run['text'] as String;
      }
    }

    // Otherwise read the byline as groups split by " • ":
    // [type] • artists • album • duration (each part optional).
    final groups = <List<String>>[[]];
    for (final run in details) {
      final text = run['text'] as String;
      if (text.trim() == '•') {
        groups.add([]);
      } else {
        groups.last.add(text);
      }
    }
    final parts = <List<String>>[];
    for (final g in groups) {
      final joined = g.join().trim();
      if (joined.isEmpty) continue;
      final d = _duration(joined);
      if (d != null) {
        duration ??= d;
        continue;
      }
      if (_isCount(joined) || _typeLabels.contains(joined)) continue;
      parts.add(g.where((t) => t.trim().isNotEmpty).toList());
    }
    // The first name in the artist group is the main artist.
    artist ??= parts.isNotEmpty ? _firstName(parts.first) : null;
    album ??= parts.length > 1 && !_isYear(parts[1].join())
        ? parts[1].join().trim()
        : null;

    return YtSong(
      videoId: videoId,
      title: title,
      artist: artist ?? 'Unknown artist',
      album: album,
      duration: duration,
      thumbnail: _thumbnail(node),
    );
  }

  static const _typeLabels = {
    'Song',
    'Video',
    'Single',
    'EP',
    'Album',
    'Episode',
    'Playlist',
  };

  static String _firstName(List<String> runs) {
    for (final r in runs) {
      final t = r.trim();
      if (t.isNotEmpty && t != ',' && t != '&') return t;
    }
    return runs.join().trim();
  }

  static bool _isYear(String s) => RegExp(r'^\d{4}$').hasMatch(s.trim());

  static String? _pageType(Map run) => _path(run, [
    'navigationEndpoint',
    'browseEndpoint',
    'browseEndpointContextSupportedConfigs',
    'browseEndpointContextMusicConfig',
    'pageType',
  ]) as String?;

  static List<Map> _runMaps(Object? text) {
    if (text is! Map) return const [];
    final runs = text['runs'];
    if (runs is List) {
      return [
        for (final r in runs)
          if (r is Map && r['text'] is String) r,
      ];
    }
    if (text['simpleText'] is String) {
      return [
        {'text': text['simpleText']},
      ];
    }
    return const [];
  }

  static String? _videoId(Map<String, dynamic> node) {
    final direct =
        node['videoId'] ??
        _path(node, ['playlistItemData', 'videoId']) ??
        _path(node, ['navigationEndpoint', 'watchEndpoint', 'videoId']);
    if (direct is String) return direct;
    String? found;
    _walk(node, (key, child) {
      if (found == null &&
          key == 'watchEndpoint' &&
          child['videoId'] is String) {
        found = child['videoId'] as String;
      }
    });
    return found;
  }

  /// The largest square thumbnail, upscaled to 544 px where the URL allows.
  static String? _thumbnail(Map<String, dynamic> node) {
    List? list;
    _walk(node, (key, child) {
      if (list == null && key == 'thumbnail' && child['thumbnails'] is List) {
        list = child['thumbnails'] as List;
      }
    });
    if (list == null || list!.isEmpty) return null;
    final url = (list!.last as Map)['url'] as String?;
    if (url == null) return null;
    return url.replaceFirst(RegExp(r'=w\d+-h\d+'), '=w544-h544');
  }

  static Duration? _duration(String? text) {
    if (text == null) return null;
    final m = RegExp(r'^(?:(\d+):)?(\d{1,2}):(\d{2})$').firstMatch(text.trim());
    if (m == null) return null;
    return Duration(
      hours: int.tryParse(m.group(1) ?? '') ?? 0,
      minutes: int.parse(m.group(2)!),
      seconds: int.parse(m.group(3)!),
    );
  }

  static bool _isCount(String s) => RegExp(
    r'^[\d.,]+[KMB]? (plays|views)$',
    caseSensitive: false,
  ).hasMatch(s);

  static List<String> _runs(Object? text) {
    if (text is! Map) return const [];
    final runs = text['runs'];
    if (runs is List) {
      return [
        for (final r in runs)
          if (r is Map && r['text'] is String) r['text'] as String,
      ];
    }
    if (text['simpleText'] is String) return [text['simpleText'] as String];
    return const [];
  }

  static String? _text(Object? text) {
    final runs = _runs(text);
    return runs.isEmpty ? null : runs.join();
  }

  static Object? _path(Object? node, List<String> keys) {
    Object? current = node;
    for (final k in keys) {
      if (current is! Map) return null;
      current = current[k];
    }
    return current;
  }

  static void _walk(
    Object? node,
    void Function(String key, Map<String, dynamic> value) visit,
  ) {
    if (node is Map) {
      for (final e in node.entries) {
        final v = e.value;
        if (v is Map<String, dynamic>) visit(e.key as String, v);
        _walk(v, visit);
      }
    } else if (node is List) {
      for (final v in node) {
        _walk(v, visit);
      }
    }
  }
}
