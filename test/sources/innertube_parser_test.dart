import 'package:flutter_test/flutter_test.dart';
import 'package:music_sense/sources/youtube_music/innertube.dart';

Map<String, Object> runs(List<String> texts) => {
  'runs': [
    for (final t in texts) {'text': t},
  ],
};

Map<String, Object> thumbs(String url) => {
  'thumbnail': {
    'thumbnails': [
      {'url': '$url=w60-h60-l90-rj', 'width': 60},
      {'url': '$url=w120-h120-l90-rj', 'width': 120},
    ],
  },
};

/// Shaped like a songs-filtered search response.
final search = {
  'contents': {
    'tabbedSearchResultsRenderer': {
      'tabs': [
        {
          'tabRenderer': {
            'content': {
              'sectionListRenderer': {
                'contents': [
                  {
                    'musicShelfRenderer': {
                      'title': runs(['Songs']),
                      'contents': [
                        {
                          'musicResponsiveListItemRenderer': {
                            'thumbnail': {
                              'musicThumbnailRenderer': thumbs('https://lh3/a'),
                            },
                            'flexColumns': [
                              {
                                'musicResponsiveListItemFlexColumnRenderer': {
                                  'text': runs(['Midnight City']),
                                },
                              },
                              {
                                'musicResponsiveListItemFlexColumnRenderer': {
                                  'text': runs([
                                    'M83',
                                    ' • ',
                                    'Hurry Up, We\'re Dreaming',
                                    ' • ',
                                    '4:04',
                                  ]),
                                },
                              },
                            ],
                            'playlistItemData': {'videoId': 'dX3k_QDnzHE'},
                          },
                        },
                        {
                          'musicResponsiveListItemRenderer': {
                            'flexColumns': [
                              {
                                'musicResponsiveListItemFlexColumnRenderer': {
                                  'text': runs(['Wait']),
                                },
                              },
                              {
                                'musicResponsiveListItemFlexColumnRenderer': {
                                  'text': runs([
                                    'Song',
                                    ' • ',
                                    'M83',
                                    ' • ',
                                    '5:43',
                                  ]),
                                },
                              },
                            ],
                            'overlay': {
                              'musicItemThumbnailOverlayRenderer': {
                                'content': {
                                  'musicPlayButtonRenderer': {
                                    'playNavigationEndpoint': {
                                      'watchEndpoint': {
                                        'videoId': 'lAwYodrBr2Q',
                                      },
                                    },
                                  },
                                },
                              },
                            },
                          },
                        },
                      ],
                    },
                  },
                ],
              },
            },
          },
        },
      ],
    },
  },
};

final home = {
  'contents': {
    'singleColumnBrowseResultsRenderer': {
      'tabs': [
        {
          'tabRenderer': {
            'content': {
              'sectionListRenderer': {
                'contents': [
                  {
                    'musicCarouselShelfRenderer': {
                      'header': {
                        'musicCarouselShelfBasicHeaderRenderer': {
                          'title': runs(['Quick picks']),
                        },
                      },
                      'contents': [
                        {
                          'musicTwoRowItemRenderer': {
                            'title': runs(['Starboy']),
                            'subtitle': runs([
                              'Song',
                              ' • ',
                              'The Weeknd',
                              ' • ',
                              '2.1B plays',
                            ]),
                            'thumbnailRenderer': {
                              'musicThumbnailRenderer': thumbs('https://lh3/b'),
                            },
                            'navigationEndpoint': {
                              'watchEndpoint': {'videoId': '34Na4j8AVgA'},
                            },
                          },
                        },
                        {
                          // An album: no videoId, must be skipped.
                          'musicTwoRowItemRenderer': {
                            'title': runs(['After Hours']),
                            'navigationEndpoint': {
                              'browseEndpoint': {'browseId': 'MPREb_x'},
                            },
                          },
                        },
                      ],
                    },
                  },
                ],
              },
            },
          },
        },
      ],
    },
  },
};

final radio = {
  'contents': {
    'playlistPanelRenderer': {
      'contents': [
        {
          'playlistPanelVideoRenderer': {
            'title': runs(['Blinding Lights']),
            'longBylineText': runs([
              'The Weeknd',
              ' • ',
              'After Hours',
              ' • ',
              '2020',
            ]),
            'lengthText': runs(['3:21']),
            'videoId': '4NRXx6U8ABQ',
            ...thumbs('https://lh3/c'),
          },
        },
      ],
    },
  },
};

void main() {
  test('reads songs from a search response', () {
    final songs = InnerTubeParser.songs(search);
    expect(songs, hasLength(2));
    final first = songs.first;
    expect(first.videoId, 'dX3k_QDnzHE');
    expect(first.title, 'Midnight City');
    expect(first.artist, 'M83');
    expect(first.album, "Hurry Up, We're Dreaming");
    expect(first.duration, const Duration(minutes: 4, seconds: 4));
    expect(first.thumbnail, 'https://lh3/a=w544-h544-l90-rj');
    // The "Song" type label is dropped; the id is found inside the overlay.
    expect(songs[1].artist, 'M83');
    expect(songs[1].videoId, 'lAwYodrBr2Q');
  });

  test('reads titled shelves from the home page and skips albums', () {
    final shelves = InnerTubeParser.shelves(home);
    expect(shelves.single.title, 'Quick picks');
    final song = shelves.single.songs.single;
    expect(song.title, 'Starboy');
    expect(song.artist, 'The Weeknd');
    expect(song.album, isNull, reason: 'play counts are not albums');
  });

  test('reads the radio queue', () {
    final song = InnerTubeParser.songs(radio).single;
    expect(song.title, 'Blinding Lights');
    expect(song.artist, 'The Weeknd');
    expect(song.album, 'After Hours');
    expect(song.duration, const Duration(minutes: 3, seconds: 21));
  });

  test('featured artists stay artists; the album comes from its link', () {
    Map<String, Object> run(String text, [String? pageType]) => {
      'text': text,
      if (pageType != null)
        'navigationEndpoint': {
          'browseEndpoint': {
            'browseEndpointContextSupportedConfigs': {
              'browseEndpointContextMusicConfig': {'pageType': pageType},
            },
          },
        },
    };
    final json = {
      'musicResponsiveListItemRenderer': {
        'flexColumns': [
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': runs(['Get Lucky']),
            },
          },
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  run('Song'),
                  run(' • '),
                  run('Daft Punk', 'MUSIC_PAGE_TYPE_ARTIST'),
                  run(', '),
                  run('Pharrell Williams', 'MUSIC_PAGE_TYPE_ARTIST'),
                  run(' • '),
                  run('Random Access Memories', 'MUSIC_PAGE_TYPE_ALBUM'),
                  run(' • '),
                  run('6:10'),
                ],
              },
            },
          },
        ],
        'playlistItemData': {'videoId': '4D7u5KF7SP8'},
      },
    };
    final song = InnerTubeParser.songs(json).single;
    expect(song.artist, 'Daft Punk');
    expect(song.album, 'Random Access Memories');
    expect(song.duration, const Duration(minutes: 6, seconds: 10));
  });

  test('featured artists without links: first name is the artist', () {
    final json = {
      'musicResponsiveListItemRenderer': {
        'flexColumns': [
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': runs(['Get Lucky']),
            },
          },
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': runs([
                'Daft Punk',
                ', ',
                'Pharrell Williams',
                ' & ',
                'Nile Rodgers',
                ' • ',
                'Random Access Memories',
                ' • ',
                '6:10',
              ]),
            },
          },
        ],
        'playlistItemData': {'videoId': '4D7u5KF7SP8'},
      },
    };
    final song = InnerTubeParser.songs(json).single;
    expect(song.artist, 'Daft Punk');
    expect(song.album, 'Random Access Memories');
  });

  test('finds playlist links on signed-out pages', () {
    final json = {
      'musicCarouselShelfRenderer': {
        'header': {
          'musicCarouselShelfBasicHeaderRenderer': {
            'title': runs(['Charts']),
          },
        },
        'contents': [
          {
            'musicTwoRowItemRenderer': {
              'title': runs(['Top 100 Songs Global']),
              'navigationEndpoint': {
                'browseEndpoint': {
                  'browseId': 'VLPL4fGSI1pDJn6puJdseH2Rt9sMvt9E2M4i',
                },
              },
            },
          },
        ],
      },
    };
    final shelf = InnerTubeParser.shelves(json).single;
    expect(shelf.title, 'Charts');
    expect(shelf.songs, isEmpty);
    expect(shelf.playlists, ['VLPL4fGSI1pDJn6puJdseH2Rt9sMvt9E2M4i']);
  });

  test('ignores unknown shapes without throwing', () {
    expect(
      InnerTubeParser.songs({
        'weird': [
          1,
          'x',
          null,
          {'a': {}},
        ],
      }),
      isEmpty,
    );
    expect(InnerTubeParser.shelves(null), isEmpty);
  });
}
