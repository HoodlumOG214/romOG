# Flutter Secure Storage - keep Tink library classes
-keep class com.google.crypto.tink.** { *; }
-keepclassmembers class * {
    @com.google.crypto.tink.annotations.** *;
}

# Keep TypeToken for Gson (used by flutter_secure_storage)
-keepattributes Signature
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Keep generic signatures
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# libtorrent4j: native interop. R8 must not strip or rename these —
# the native side calls into them by exact name via JNI.
-keep class org.libtorrent4j.** { *; }
-keep class org.libtorrent4j.swig.** { *; }
-keepclassmembers class org.libtorrent4j.** { *; }
-dontwarn org.libtorrent4j.**

# Enums are special: R8 will rewrite enum.values() / valueOf() /
# ordinal call sites into integer constants. The alert dispatch uses
# AlertType.swig() and reverse lookups that depend on enum members
# staying intact — without this, alerts silently never reach
# AlertListener on release builds.
-keepclassmembers enum org.libtorrent4j.** {
    public static **[] values();
    public static ** valueOf(java.lang.String);
    public int swig();
}
-keep enum org.libtorrent4j.alerts.AlertType { *; }

# Pigeon-generated bridge + our impl talk to native code.
-keep class com.caprado.romgi.torrent.** { *; }
