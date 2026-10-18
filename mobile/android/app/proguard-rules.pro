# ML Kit text recognition: the plugin references the optional Chinese,
# Devanagari, Japanese and Korean recognizers. We only read Latin bib
# numbers, so those artifacts aren't bundled; let R8 ignore them.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
