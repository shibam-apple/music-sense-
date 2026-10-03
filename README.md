# Music Sense

A free music player with an interface that mixes the PlayStation XMB and the
Windows Metro style. Its signature feature, Beat Sense, will mix each song
into the next with matched beats.

The product spec (features, Beat Sense algorithm, sources, AI features and
roadmap) is in the shared spec doc.

![The six screens](docs/screens.png)

## Status

Phase 1, UI shell. The six screens from the design are built and navigable:

| Page | What it shows |
| --- | --- |
| Music | Recent artwork, current song, song list |
| Albums | Hero album with song and minute tiles, album list |
| Featured | Live tiles: radio, moods, mixes, charts, concerts, song of the day |
| New | New releases, hours played, singles, pre-saves, yearly replay |
| Playing | Cover, seek bar, transport controls, up next |
| Artist | Full-bleed photo, actions, latest release, top songs |

Navigation follows the design: pages sit side by side as a Metro panorama
(the next page peeks in from the right) and the XMB icon bar slides with the
swipe so the active icon always sits in the glowing slot. Swipes settle with
spring physics; arrow keys and the space bar work on desktop and web.

Playback, the library and artwork are mocked for now. Artwork is painted in
code (`lib/widgets/artwork.dart`) until real covers come from the library.

## Run

Requires Flutter 3.47 or newer.

```sh
flutter pub get
flutter run            # pick a device: Android, iOS, Windows, macOS, Linux or Chrome
flutter test
```

## Layout

```
lib/
  main.dart            app entry, theme, phone frame on wide windows
  shell.dart           panorama + XMB bar, swipe physics, keyboard
  theme/tokens.dart    colours, type, sizes and motion from the design
  pages/               one file per page
  widgets/             XMB bar, panorama page, Metro tiles, artwork
  state/player.dart    playback state (mock clock until the audio engine)
  data/library.dart    models and mock library
```

Fonts: [Inter](https://rsms.me/inter/) (SIL Open Font License, see
`assets/fonts/LICENSE.txt`). Icons: [Lucide](https://lucide.dev).
