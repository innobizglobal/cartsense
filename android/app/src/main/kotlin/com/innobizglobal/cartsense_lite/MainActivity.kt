package com.innobizglobal.cartsense_lite

import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val OCR_CHANNEL = "cartsense/receipt_ocr"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OCR_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "recognizeReceipt") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val path = call.argument<String>("path")
                val imageFile = path?.let { File(it) }
                if (imageFile == null || !imageFile.isFile) {
                    result.error("IMAGE_NOT_FOUND", "The selected receipt image is unavailable.", null)
                    return@setMethodCallHandler
                }

                val inputImage = try {
                    InputImage.fromFilePath(this, Uri.fromFile(imageFile))
                } catch (error: Exception) {
                    result.error("IMAGE_OPEN_FAILED", error.message, null)
                    return@setMethodCallHandler
                }

                val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                recognizer.process(inputImage)
                    .addOnSuccessListener { recognized -> result.success(recognized.text) }
                    .addOnFailureListener { error ->
                        result.error("OCR_FAILED", error.message ?: error.javaClass.simpleName, null)
                    }
                    .addOnCompleteListener { recognizer.close() }
            }
    }
}
