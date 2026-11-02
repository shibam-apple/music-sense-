# NewPipe Extractor (YouTube streams). Rhino runs YouTube's player
# JavaScript and loads classes by name; the time-ago parsers are loaded
# reflectively too.
-keep class org.schabi.newpipe.extractor.timeago.patterns.** { *; }
-keep class org.mozilla.javascript.** { *; }
-keep class org.mozilla.classfile.ClassFileWriter
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }
-dontwarn org.mozilla.javascript.tools.**
# Rhino's JVM optimizer (desktop Java only; Android runs it interpreted).
-dontwarn jdk.dynalink.**
-dontwarn javax.script.**
-dontwarn java.beans.**
-dontwarn javax.lang.model.**
-dontwarn java.awt.**
-dontwarn javax.annotation.**
-dontwarn com.google.re2j.**
-dontwarn org.jspecify.annotations.**
