#!/usr/bin/env bash
# Runs integration_test/device_test.dart on the connected device/emulator:
# installs the test build, copies the Beat Test songs into Music, grants
# permissions (so no dialog blocks the test) and saves screenshots.
set -euo pipefail
cd "$(dirname "$0")/.."
app=com.musicsense.music_sense
apk=build/app/outputs/flutter-apk/app-debug.apk
mkdir -p build/screenshots

adb wait-for-device
adb shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done'

adb push build/test_songs/beat_test_120.mp3 build/test_songs/beat_test_124.mp3 /sdcard/Music/
for f in beat_test_120 beat_test_124; do
  adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
    -d "file:///sdcard/Music/$f.mp3" > /dev/null || true
done
# Give the media scanner a moment, then confirm it indexed the songs.
for i in $(seq 1 30); do
  if adb shell content query --uri content://media/external/audio/media \
      --projection title | grep -q "Beat Test"; then break; fi
  sleep 2
done
adb shell content query --uri content://media/external/audio/media --projection title:artist

adb install -r "$apk"
adb shell pm grant $app android.permission.READ_MEDIA_AUDIO
adb shell pm grant $app android.permission.POST_NOTIFICATIONS || true

flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/device_test.dart \
  --use-application-binary="$apk" \
  -d emulator-5554 2>&1 | tee build/device-test.log
