#!/usr/bin/env bash
# Compiles the Beat Sense audio engine core (plain Kotlin, no Android) with
# tool/engine_check/EngineTest.kt and runs it on the JVM.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
work="${TMPDIR:-/tmp}/ms-engine-check"
mkdir -p "$work"
cd "$work"
M=https://repo1.maven.org/maven2
K=2.4.20
get() { [ -f "$1" ] || curl -sSfL --retry 5 --retry-delay 3 -o "$1" "$2"; }
for a in kotlin-compiler-embeddable kotlin-stdlib kotlin-script-runtime kotlin-reflect kotlin-daemon-embeddable; do
  get $a.jar $M/org/jetbrains/kotlin/$a/$K/$a-$K.jar
done
get trove4j.jar $M/org/jetbrains/intellij/deps/trove4j/1.0.20200330/trove4j-1.0.20200330.jar
get annotations.jar $M/org/jetbrains/annotations/13.0/annotations-13.0.jar
get coroutines.jar $M/org/jetbrains/kotlinx/kotlinx-coroutines-core-jvm/1.8.0/kotlinx-coroutines-core-jvm-1.8.0.jar
core="$here/android/app/src/main/kotlin/com/musicsense/music_sense/engine"
rm -rf out
java -cp kotlin-compiler-embeddable.jar:kotlin-stdlib.jar:kotlin-script-runtime.jar:kotlin-reflect.jar:kotlin-daemon-embeddable.jar:trove4j.jar:annotations.jar:coroutines.jar \
  org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -jvm-target 17 -nowarn \
  -classpath kotlin-stdlib.jar -d out \
  "$core/PcmBuffer.kt" "$core/Dsp.kt" "$core/Stretcher.kt" "$core/Mixer.kt" \
  "$here/tool/engine_check/EngineTest.kt"
java -cp out:kotlin-stdlib.jar com.musicsense.music_sense.engine.EngineTestKt
