# CartSense uses only TextRecognitionScript.latin. The Flutter ML Kit bridge
# references the optional recognizers, but their large language models are
# intentionally not packaged in this private on-device build.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
