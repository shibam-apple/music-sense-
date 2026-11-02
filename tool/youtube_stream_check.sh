#!/usr/bin/env bash
# Compiles the app's YouTubeStreams.kt with tool/youtube_check/Main.kt and
# runs it: finds and downloads a YouTube song exactly as the phone does.
# Needs Java 17+ and network access to Maven Central, JitPack and YouTube.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
work="${TMPDIR:-/tmp}/ms-youtube-check-build"
mkdir -p "$work"
cd "$work"
M=https://repo1.maven.org/maven2
J=https://jitpack.io/com/github/TeamNewPipe
K=2.4.20
get() { [ -f "$1" ] || curl -sSfL -o "$1" "$2"; }
for a in kotlin-compiler-embeddable kotlin-stdlib kotlin-script-runtime kotlin-reflect kotlin-daemon-embeddable; do
  get $a.jar $M/org/jetbrains/kotlin/$a/$K/$a-$K.jar
done
get trove4j.jar $M/org/jetbrains/intellij/deps/trove4j/1.0.20200330/trove4j-1.0.20200330.jar
get annotations.jar $M/org/jetbrains/annotations/13.0/annotations-13.0.jar
get coroutines.jar $M/org/jetbrains/kotlinx/kotlinx-coroutines-core-jvm/1.8.0/kotlinx-coroutines-core-jvm-1.8.0.jar
get newpipe.jar $J/NewPipeExtractor/v0.26.5/NewPipeExtractor-v0.26.5.jar
get nanojson.jar $J/nanojson/e9d656ddb49a412a5a0a5d5ef20ca7ef09549996/nanojson-e9d656ddb49a412a5a0a5d5ef20ca7ef09549996.jar
get jsoup.jar $M/org/jsoup/jsoup/1.22.2/jsoup-1.22.2.jar
get jsr305.jar $M/com/google/code/findbugs/jsr305/3.0.2/jsr305-3.0.2.jar
get protobuf.jar $M/com/google/protobuf/protobuf-javalite/4.35.1/protobuf-javalite-4.35.1.jar
get rhino.jar $M/org/mozilla/rhino/1.8.1/rhino-1.8.1.jar
get rhino-engine.jar $M/org/mozilla/rhino-engine/1.8.1/rhino-engine-1.8.1.jar
libs=newpipe.jar:nanojson.jar:jsoup.jar:jsr305.jar:protobuf.jar:rhino.jar:rhino-engine.jar
rm -rf out
java -cp kotlin-compiler-embeddable.jar:kotlin-stdlib.jar:kotlin-script-runtime.jar:kotlin-reflect.jar:kotlin-daemon-embeddable.jar:trove4j.jar:annotations.jar:coroutines.jar \
  org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -jvm-target 17 -nowarn \
  -classpath kotlin-stdlib.jar:$libs -d out \
  "$here"/android/app/src/main/kotlin/com/musicsense/music_sense/YouTubeStreams.kt "$here"/tool/youtube_check/Main.kt
java -cp out:kotlin-stdlib.jar:$libs com.musicsense.music_sense.MainKt "$@"
