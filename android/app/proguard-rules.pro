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
