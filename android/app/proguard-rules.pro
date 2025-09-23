# Flutter-specific rules.
-dontwarn io.flutter.embedding.**

# Rules for google_mlkit_text_recognition

# 1. Keep the classes to prevent them from being removed by R8.
-keep class com.google.mlkit.vision.text.devanagari.** { *; }
-keep class com.google.mlkit.vision.text.japanese.** { *; }
-keep class com.google.mlkit.vision.text.korean.** { *; }

# 2. Suppress warnings about these classes, as suggested by R8.
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**