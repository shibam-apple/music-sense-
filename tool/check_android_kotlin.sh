#!/usr/bin/env bash
# Type-checks the app's Kotlin against Android 15 APIs without the Android
# SDK, for environments where dl.google.com is unavailable. Downloads the
# Kotlin compiler and Robolectric's android-all jar from Maven Central.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
work="${TMPDIR:-/tmp}/ms-kotlin-check"
mkdir -p "$work/stub/com/ryanheise/audioservice" "$work/stub/androidx/lifecycle"
cd "$work"
M=https://repo1.maven.org/maven2
K=2.4.20
engine="$(cat "$(dirname "$(command -v flutter)")/internal/engine.version")"
get() { [ -f "$1" ] || curl -sSfL -o "$1" "$2"; }
get android-all.jar $M/org/robolectric/android-all/15-robolectric-13954326/android-all-15-robolectric-13954326.jar
get flutter_embedding.jar "https://storage.googleapis.com/download.flutter.io/io/flutter/flutter_embedding_release/1.0.0-$engine/flutter_embedding_release-1.0.0-$engine.jar"
for a in kotlin-compiler-embeddable kotlin-stdlib kotlin-script-runtime kotlin-reflect kotlin-daemon-embeddable; do
  get $a.jar $M/org/jetbrains/kotlin/$a/$K/$a-$K.jar
done
get trove4j.jar $M/org/jetbrains/intellij/deps/trove4j/1.0.20200330/trove4j-1.0.20200330.jar
get annotations.jar $M/org/jetbrains/annotations/13.0/annotations-13.0.jar
get coroutines.jar $M/org/jetbrains/kotlinx/kotlinx-coroutines-core-jvm/1.8.0/kotlinx-coroutines-core-jvm-1.8.0.jar
# Minimal stand-ins for classes that come from AndroidX and plugins.
echo 'package com.ryanheise.audioservice
open class AudioServiceActivity : io.flutter.embedding.android.FlutterActivity()' > stub/com/ryanheise/audioservice/AudioServiceActivity.kt
echo 'package androidx.lifecycle
abstract class Lifecycle
interface LifecycleOwner { val lifecycle: Lifecycle }' > stub/androidx/lifecycle/Stubs.kt
rm -rf out
java -cp kotlin-compiler-embeddable.jar:kotlin-stdlib.jar:kotlin-script-runtime.jar:kotlin-reflect.jar:kotlin-daemon-embeddable.jar:trove4j.jar:annotations.jar:coroutines.jar \
  org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -jvm-target 17 \
  -classpath android-all.jar:flutter_embedding.jar:kotlin-stdlib.jar -d out \
  "$here"/android/app/src/main/kotlin/com/musicsense/music_sense/*.kt stub/com/ryanheise/audioservice/*.kt stub/androidx/lifecycle/*.kt
echo "Kotlin OK"
