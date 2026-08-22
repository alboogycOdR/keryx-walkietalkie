# Keryx release R8 keep rules (TASK-039).
#
# Each rule names the plugin that needs it and why. Plugin consumer-rules
# (when a library ships them) are still applied automatically; these app
# rules are the explicit, reviewable floor so a missing consumer file
# cannot silently strip JNI / ML Kit / method-channel classes.

# --- flutter_webrtc ----------------------------------------------------------
# JNI + WebRTC Java API looked up by name from libjingle / FlutterWebRTCPlugin.
# Source: flutter_webrtc-1.6.0/android/proguard-rules.pro (consumerProguardFiles).
-keep class com.cloudwebrtc.webrtc.** { *; }
-keep class org.webrtc.** { *; }
-keep class org.jni_zero.** { *; }
-dontwarn org.webrtc.**
-dontwarn org.jni_zero.**

# --- livekit_client ----------------------------------------------------------
# Flutter plugin package is io.livekit.plugin (LiveKitPlugin.kt) and pulls
# io.github.webrtc-sdk + io.livekit:noise + AudioSwitch. The plugin does NOT
# ship consumerProguardFiles, so these must live here. Native callbacks and
# method-channel classes are resolved by name.
-keep class io.livekit.** { *; }
-keep class livekit.org.webrtc.** { *; }
-keep class com.twilio.audioswitch.** { *; }
-dontwarn io.livekit.**
-dontwarn livekit.org.webrtc.**
-dontwarn com.twilio.audioswitch.**

# --- mobile_scanner ----------------------------------------------------------
# ML Kit barcode + Barhopper native; CameraX is kept via AndroidX defaults.
# Source: mobile_scanner-7.4.0/android/proguard-rules.pro.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.libraries.barhopper.** { *; }
-keep class com.google.photos.** { *; }
-keep class dev.steenbakker.mobile_scanner.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.libraries.barhopper.**
-dontwarn com.google.photos.**

# Enum valueOf / values used by ML Kit barcode format mapping.
-keepclassmembers class * extends java.lang.Enum {
    <fields>;
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# --- flutter_soloud ----------------------------------------------------------
# FFI/CMake plugin (namespace flutter.soloud.flutter_soloud). R8 must not
# rename the Java/Kotlin registrant the Flutter engine loads by class name;
# native .so files are unaffected by R8.
-keep class flutter.soloud.** { *; }
-dontwarn flutter.soloud.**

# --- app native plugins (TASK-019 / TASK-026) --------------------------------
# MainActivity registers NsdPlugin and RadioServicePlugin by class; the
# foreground service is started from the method channel by component name.
-keep class za.co.basileia.keryx.** { *; }

# --- Flutter embedding / plugins ---------------------------------------------
# Extra belt: method-channel plugins and GeneratedPluginRegistrant are
# loaded reflectively. Flutter's own consumer rules usually cover this.
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
