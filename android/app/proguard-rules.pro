# Keep device_info plugin classes
-keep class io.flutter.plugins.deviceinfo.** { *; }

# Keep plugin classes in general
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.**  { *; }

# Additional common rules for Flutter apps
-keep class androidx.lifecycle.** { *; }
-keep class androidx.core.** { *; }
-keep class androidx.fragment.** { *; }

# Optional HMS/EMUI and BouncyCastle paths referenced by Huawei SDKs but not
# bundled; guarded at runtime, so suppress R8's missing-class errors.
-dontwarn com.huawei.android.os.**
-dontwarn com.huawei.hianalytics.**
-dontwarn com.huawei.libcore.io.**
-dontwarn org.bouncycastle.**

# Flutter embedding entry points. The embedding is reached reflectively (the
# Activity/Application classes named in AndroidManifest.xml, the generated
# plugin registrant, and the JNI bridge), so R8 cannot see the references and
# strips or renames them in release builds.
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.embedding.engine.** { *; }
-keep class io.flutter.embedding.android.** { *; }

# HMS keep rules (hms_sdk is enabled for this app). The Huawei SDKs resolve
# their own classes by name and serialise/deserialise model types via
# reflection, so -dontwarn alone is not enough: the classes must survive R8 or
# the availability check and the push registration fail at runtime in release.
-keep class com.huawei.** { *; }
-keep class com.huawei.hms.** { *; }
-keep class com.huawei.agconnect.** { *; }
-dontwarn com.huawei.**

# Reflective lookups above need their metadata intact.
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
