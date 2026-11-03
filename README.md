# Music Sense

A free music player with an interface that mixes the PlayStation XMB and the
Windows Metro style. Its signature feature, Beat Sense, will mix each song
into the next with matched beats.

The product spec (features, Beat Sense algorithm, sources, AI features and
roadmap) is in the shared spec doc.

![The six screens](docs/screens.png)

## Status

Android first. What's in the app now:

- **The six screens from the design**, wired to real music, with the same
  layout and navigation: Metro panorama pages, and the XMB icon bar sliding
  with each swipe.
- **Beat Sense**, the automatic mixing engine (`lib/beat_sense/`):
  - *Analysis:* tempo, beat grid, bars, 8-bar phrases, musical key (Camelot),
    loudness, energy, and where the intro and outro are. It's plain Dart,
    runs in a background isolate and is cached per song.
  - *Planning:* picks the next song by tempo, key, energy and taste, and plans
    the transition. It starts on a phrase boundary and enters long intros
    part-way, so the drop lands as the blend ends. It matches tempo within
    ±8% (half and double time count as the same tempo) and evens out
    loudness. Transition styles: bass swap, blend, cut on the beat, or a
    plain crossfade when a song has no steady beat.
  - *Playback (`lib/playback/mix_engine.dart`):* two decks. The incoming song
    starts on the downbeat, a 30 ms conductor drives volume and the bass
    swap, speed is nudged to cancel drift, and tempo eases back after the
    mix. When the queue runs out, Beat Sense keeps going with the best-fitting
    related song.
- **Sources** (`lib/sources/`):
  - *Local files:* Android MediaStore, with covers and audio decoding in
    `MediaBridge.kt`.
  - *YouTube Music:* optional plugin with home feed, charts, search and radio
    through YouTube Music's unofficial API. On Android, songs are found with
    [NewPipe Extractor](https://github.com/TeamNewPipe/NewPipeExtractor) (the
    library behind the NewPipe app) and downloaded to a 500 MB cache before
    playing, so seeking, Beat Sense and replays work like local files;
    youtube_explode is the fallback. Account → *Check YouTube playback* runs
    each step on the phone and gives a report to copy. NewPipe Extractor is
    GPL-3.0, so builds that include it are GPL-3.0 too.
    Build without it with `--dart-define=YT_MUSIC=false`.
- **Polish, in PlayStation style:**
  - the page glow, the XMB waves and the shadows take their colour from the
    current cover
  - the waves swell on the beat, with sparkles drifting along them
  - a light sweep crosses covers, the covers "breathe" with the beat, and
    motes of light rise off the Playing cover
  - the artist backdrop slowly zooms
  - haptic ticks as each icon snaps into the slot
- Background playback, notification and lock-screen controls (audio_service).

The web build and the tests run on the design's sample songs with a silent
clock; real playback needs an Android device.

### Not verified yet

These need a real device and network access this project's build
environment didn't have:
- the APK build
- audio playback and mixing on a phone
- YouTube Music against live YouTube, including the phone's stream code
  (`tool/youtube_stream_check.sh`, run on the JVM)

The Kotlin is type-checked against Android 15 APIs with
`tool/check_android_kotlin.sh`. Because YouTube Music uses an unofficial API,
expect it to need occasional fixes when YouTube changes it.

## Run

Requires Flutter 3.47 or newer.

```sh
flutter pub get
flutter run                                  # Android phone, or Chrome for the preview
flutter build apk --release                  # GitHub build, with YouTube Music
flutter build appbundle --dart-define=YT_MUSIC=false   # Play Store build
flutter test                                 # 36 tests: analysis, planner, parser, UI
```

## Layout

```
lib/
  beat_sense/          analysis (FFT, tempo, beats, key) and planning
  playback/            mix engine, decks, analysis cache, demo player, media session
  sources/             local files, YouTube Music plugin, samples
  library/             models, library aggregation, listening stats
  pages/               the six pages
  widgets/             XMB bar, panorama page, tiles, artwork, ambient effects
  shell.dart           panorama + XMB bar, swipe physics, haptics, keyboard
android/.../MediaBridge.kt   MediaStore, covers, audio decoding for analysis
```

Fonts: [Inter](https://rsms.me/inter/) (SIL Open Font License, see
`assets/fonts/LICENSE.txt`). Icons: [Lucide](https://lucide.dev).

## Beat Sense engine

On Android, songs play through Beat Sense's own audio engine (Kotlin,
`android/app/src/main/kotlin/.../engine/`) instead of two separate players:

- **One mixer, one clock.** Both songs render in the same audio callback;
  during a transition the incoming song's position is computed from the
  outgoing one's (`incoming = entry + (outgoing − exit) × rate`), so beats
  stay locked to well under a millisecond with no drift to correct.
- **Tempo and key** by WSOLA on resampled grains: tempo changes keep the
  pitch, key shifts keep the tempo, and normal speed is bit-exact.
- **DJ EQ and filter:** a Linkwitz-Riley 3-band isolator (kills at 24 dB/oct)
  and a sweepable high/low-pass per deck, plus a limiter on the sum.
- **Transition scripts** from the Dart planner (`lib/beat_sense/mix_script.dart`):
  timed lanes for each deck's volume, low/mid/high and filter — e.g. the
  new song enters with its bass killed and highs down, the bass changes
  hands on the middle downbeat, the old song is filtered out.
- **Key matching:** the incoming song can be shifted a semitone so the two
  keys sit next to each other on the Camelot wheel.

`tool/engine_check.sh` runs the engine's checks on the JVM (pass-through,
EQ flatness and kills, filter, tempo/pitch accuracy, beat lock, limiter).
Account → *Beat Sense engine* switches back to the classic players.

