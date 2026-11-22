package com.smiunotes.smiunotes_contributers_app

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.pdf.PdfRenderer
import android.os.Build
import android.os.ParcelFileDescriptor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * Uses Android's platform PDF renderer. No PDF bytes, original paths, or
 * watermarked preview content are sent to third-party services here.
 * Every output page is generated in application cache as a private file.
 */
class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private val channelName = "com.smiunotes.contributors/pdf_renderer"
    private val cachePrefix = "smiunotes-page-"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "inspect" -> {
                        val path = call.argument<String>("path")
                        executor.execute {
                            try {
                                val file = checkedPdf(path)
                                val details = openPdf(file) { renderer ->
                                    if (renderer.pageCount !in 1..60) {
                                        throw IllegalArgumentException("PDF needs 1 to 60 pages")
                                    }
                                    mapOf(
                                        "pageCount" to renderer.pageCount,
                                        "sha256" to sha256(file),
                                        "bytes" to file.length()
                                    )
                                }
                                runOnUiThread { result.success(details) }
                            } catch (_: Exception) {
                                runOnUiThread {
                                    result.error("INVALID_PDF", "PDF cannot be opened or exceeds limits.", null)
                                }
                            }
                        }
                    }
                    "renderPage" -> {
                        val path = call.argument<String>("path")
                        val index = call.argument<Int>("index")
                        executor.execute {
                            try {
                                val file = checkedPdf(path)
                                if (index == null) throw IllegalArgumentException("Page required")
                                val output = renderPage(file, index)
                                runOnUiThread { result.success(output.absolutePath) }
                            } catch (_: Exception) {
                                runOnUiThread {
                                    result.error("RENDER_FAILED", "Unable to prepare watermarked page.", null)
                                }
                            }
                        }
                    }
                    "deleteTemporary" -> {
                        val path = call.argument<String>("path")
                        executor.execute {
                            val target = path?.let(::File)
                            val safe = target != null && target.parentFile?.canonicalPath ==
                                cacheDir.canonicalPath && target.name.startsWith(cachePrefix) &&
                                target.name.endsWith(".webp")
                            if (safe) target?.delete()
                            runOnUiThread { result.success(null) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun checkedPdf(path: String?): File {
        if (path.isNullOrBlank()) throw IllegalArgumentException("Missing PDF")
        val file = File(path).canonicalFile
        if (!file.isFile || !file.canRead() ||
            file.length() < 20 || file.length() > 20L * 1024L * 1024L) {
            throw IllegalArgumentException("Invalid PDF size")
        }
        FileInputStream(file).use { input ->
            val magic = ByteArray(5)
            if (input.read(magic) != 5 || String(magic, Charsets.US_ASCII) != "%PDF-") {
                throw IllegalArgumentException("Invalid PDF header")
            }
        }
        return file
    }

    private fun <T> openPdf(file: File, action: (PdfRenderer) -> T): T {
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
            PdfRenderer(descriptor).use { renderer ->
                return action(renderer)
            }
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(8192)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                if (read > 0) digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun renderPage(file: File, zeroBased: Int): File = openPdf(file) { renderer ->
        if (zeroBased < 0 || zeroBased >= renderer.pageCount || renderer.pageCount > 60) {
            throw IllegalArgumentException("Invalid page")
        }
        renderer.openPage(zeroBased).use { page ->
            // Match the existing website's maximum edge and 2x scale policy.
            val factor = minOf(2f, 1600f / maxOf(page.width, page.height).toFloat())
            val width = maxOf(1, (page.width * factor).toInt())
            val height = maxOf(1, (page.height * factor).toInt())
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            try {
                val canvas = Canvas(bitmap)
                canvas.drawColor(Color.WHITE)
                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                val water = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.argb(41, 38, 77, 102)
                    textAlign = Paint.Align.CENTER
                    typeface = android.graphics.Typeface.create(
                        android.graphics.Typeface.SANS_SERIF,
                        android.graphics.Typeface.BOLD
                    )
                    textSize = maxOf(22f, width / 15f)
                }
                canvas.save()
                canvas.translate(width / 2f, height / 2f)
                canvas.rotate(-30f)
                var y = -height.toFloat()
                while (y <= height.toFloat()) {
                    canvas.drawText("SMIUNotes.com", 0f, y, water)
                    y += maxOf(150f, width / 3f)
                }
                canvas.restore()

                val output = File.createTempFile(cachePrefix, ".webp", cacheDir)
                var encoded = false
                for (quality in listOf(78, 60, 45)) {
                    FileOutputStream(output, false).use { stream ->
                        val format = if (Build.VERSION.SDK_INT >= 30)
                            Bitmap.CompressFormat.WEBP_LOSSY else
                            @Suppress("DEPRECATION") Bitmap.CompressFormat.WEBP
                        if (!bitmap.compress(format, quality, stream)) {
                            throw IllegalStateException("WebP encoding failed")
                        }
                    }
                    if (output.length() in 1..1048576) {
                        encoded = true
                        break
                    }
                }
                if (!encoded) {
                    output.delete()
                    throw IllegalArgumentException("Page exceeds 1 MiB.")
                }
                output
            } finally {
                bitmap.recycle()
            }
        }
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }
}
