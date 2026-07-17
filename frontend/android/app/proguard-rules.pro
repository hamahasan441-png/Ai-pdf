# ---------------------------------------------------------------------------
# R8 / ProGuard keep rules for the AI PDF app.
# Only rules NOT already covered by the Flutter/AGP defaults are listed here.
# These target reflection- and native-heavy plugins that R8 can otherwise
# strip or rename, which would crash the release build at runtime.
# ---------------------------------------------------------------------------

# --- Flutter engine (safety net; usually provided by the default rules) ---
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# --- Google ML Kit: text recognition (on-device OCR) ---
# ML Kit loads model/detector classes via reflection and JNI.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# ML Kit optionally references other language text recognizers via reflection.
# We only bundle the Latin model, so silence the missing-class warnings.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# --- pdfx / native PdfRenderer bindings ---
-keep class io.scer.pdfx.** { *; }
-dontwarn io.scer.pdfx.**

# --- flutter_secure_storage ---
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**

# --- file_picker ---
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-dontwarn com.mr.flutter.plugin.filepicker.**

# --- Play Billing (in_app_purchase) ---
-keep class com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**

# --- Keep annotated/native entry points and enums generally ---
-keepclasseswithmembernames class * {
    native <methods>;
}
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep Parcelable CREATOR fields (used by plugin channel arguments).
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# Kotlin metadata / coroutines used by several plugins.
-keep class kotlin.Metadata { *; }
-dontwarn kotlinx.coroutines.**
