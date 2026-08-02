package com.innobizglobal.cartsense_lite

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.graphics.Rect
import android.media.ExifInterface
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val OCR_CHANNEL = "cartsense/receipt_ocr"
        private const val MAX_RECEIPT_PIXELS = 12_500_000L
    }

    private data class OcrSegment(val text: String, val bounds: Rect)

    private class OcrRow(first: OcrSegment) {
        val segments = mutableListOf(first)
        var top = first.bounds.top
        var bottom = first.bounds.bottom

        val centerY: Float
            get() = (top + bottom) / 2f

        val height: Int
            get() = (bottom - top).coerceAtLeast(1)

        fun add(segment: OcrSegment) {
            segments.add(segment)
            top = minOf(top, segment.bounds.top)
            bottom = maxOf(bottom, segment.bounds.bottom)
        }
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

                val bitmap = try {
                    decodeReceiptBitmap(imageFile)
                } catch (error: Exception) {
                    result.error(
                        "IMAGE_OPEN_FAILED",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                    return@setMethodCallHandler
                } catch (_: OutOfMemoryError) {
                    result.error(
                        "IMAGE_TOO_LARGE",
                        "This photo is too large to read safely. Please use a lower-resolution copy.",
                        null,
                    )
                    return@setMethodCallHandler
                }

                val inputImage = try {
                    InputImage.fromBitmap(bitmap, 0)
                } catch (error: Exception) {
                    bitmap.recycle()
                    result.error(
                        "OCR_IMAGE_FAILED",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                    return@setMethodCallHandler
                }

                val recognizer = try {
                    TextRecognition.getClient(TextRecognizerOptions.Builder().build())
                } catch (error: Exception) {
                    bitmap.recycle()
                    result.error(
                        "OCR_START_FAILED",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                    return@setMethodCallHandler
                }

                val recognitionTask = try {
                    recognizer.process(inputImage)
                } catch (error: Exception) {
                    recognizer.close()
                    bitmap.recycle()
                    result.error(
                        "OCR_PROCESS_FAILED",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                    return@setMethodCallHandler
                }
                recognitionTask
                    .addOnSuccessListener { recognized ->
                        result.success(buildReceiptRows(recognized))
                    }
                    .addOnFailureListener { error ->
                        result.error("OCR_FAILED", error.message ?: error.javaClass.simpleName, null)
                    }
                    .addOnCompleteListener {
                        recognizer.close()
                        bitmap.recycle()
                    }
            }
    }

    private fun buildReceiptRows(recognized: Text): String {
        val segments = recognized.textBlocks
            .flatMap { it.lines }
            .mapNotNull { line ->
                val bounds = line.boundingBox ?: return@mapNotNull null
                line.text.trim().takeIf { it.isNotEmpty() }?.let { OcrSegment(it, bounds) }
            }
            .sortedWith(compareBy<OcrSegment> { it.bounds.top }.thenBy { it.bounds.left })
        if (segments.isEmpty()) return recognized.text

        val rows = mutableListOf<OcrRow>()
        for (segment in segments) {
            val segmentHeight = segment.bounds.height().coerceAtLeast(1)
            val segmentCenter = segment.bounds.exactCenterY()
            val row = rows
                .filter { candidate ->
                    val overlap = minOf(candidate.bottom, segment.bounds.bottom) -
                        maxOf(candidate.top, segment.bounds.top)
                    val enoughOverlap = overlap >= minOf(candidate.height, segmentHeight) * 0.35f
                    val closeCenters = kotlin.math.abs(candidate.centerY - segmentCenter) <=
                        maxOf(candidate.height, segmentHeight) * 0.45f
                    enoughOverlap || closeCenters
                }
                .minByOrNull { kotlin.math.abs(it.centerY - segmentCenter) }
            if (row == null) {
                rows.add(OcrRow(segment))
            } else {
                row.add(segment)
            }
        }

        return rows
            .sortedBy { it.top }
            .joinToString("\n") { row ->
                row.segments
                    .sortedBy { it.bounds.left }
                    .joinToString("  ") { it.text }
            }
    }

    private fun decodeReceiptBitmap(imageFile: File): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(imageFile.absolutePath, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw IllegalArgumentException("Android could not decode this image format.")
        }

        var sampleSize = 1
        while (
            (bounds.outWidth.toLong() / sampleSize) *
                (bounds.outHeight.toLong() / sampleSize) > MAX_RECEIPT_PIXELS
        ) {
            sampleSize *= 2
        }

        val decoded = BitmapFactory.decodeFile(
            imageFile.absolutePath,
            BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            },
        ) ?: throw IllegalArgumentException("Android could not decode this image format.")

        val orientation = try {
            ExifInterface(imageFile.absolutePath).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        } catch (_: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }
        return applyExifOrientation(decoded, orientation)
    }

    private fun applyExifOrientation(bitmap: Bitmap, orientation: Int): Bitmap {
        if (orientation == ExifInterface.ORIENTATION_NORMAL ||
            orientation == ExifInterface.ORIENTATION_UNDEFINED
        ) {
            return bitmap
        }

        val matrix = Matrix().apply {
            when (orientation) {
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> setScale(-1f, 1f)
                ExifInterface.ORIENTATION_ROTATE_180 -> setRotate(180f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> setScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> {
                    setRotate(90f)
                    postScale(-1f, 1f)
                }
                ExifInterface.ORIENTATION_ROTATE_90 -> setRotate(90f)
                ExifInterface.ORIENTATION_TRANSVERSE -> {
                    setRotate(-90f)
                    postScale(-1f, 1f)
                }
                ExifInterface.ORIENTATION_ROTATE_270 -> setRotate(-90f)
                else -> return bitmap
            }
        }
        val oriented = Bitmap.createBitmap(
            bitmap,
            0,
            0,
            bitmap.width,
            bitmap.height,
            matrix,
            true,
        )
        if (oriented !== bitmap) {
            bitmap.recycle()
        }
        return oriented
    }
}
