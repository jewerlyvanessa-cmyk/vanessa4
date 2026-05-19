package com.example.vanessa3

import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        WindowCompat.setDecorFitsSystemWindows(window, true)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.vanessa3/label_print",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "printLabelPdf" -> handlePrintLabelPdf(call, result)
                "saveLabelPdf" -> handleSaveLabelPdf(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handlePrintLabelPdf(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            result.error("unsupported", "Android 5.0+ required for label print", null)
            return
        }

        val name = call.argument<String>("name") ?: "label_stok"
        val widthMm = call.argument<Number>("widthMm")?.toDouble()
        val heightMm = call.argument<Number>("heightMm")?.toDouble()
        val data = readPdfBytes(call)

        if (widthMm == null || heightMm == null || data == null) {
            result.error("invalid_args", "widthMm/heightMm/data required", null)
            return
        }

        try {
            LabelPrintHelper.printLabelPdf(this, name, widthMm, heightMm, data)
            result.success(true)
        } catch (e: Exception) {
            result.error("print_failed", e.message, null)
        }
    }

    private fun handleSaveLabelPdf(call: MethodCall, result: MethodChannel.Result) {
        val fileName = call.argument<String>("fileName") ?: "label_stok.pdf"
        val data = readPdfBytes(call)
        if (data == null) {
            result.error("invalid_args", "data required", null)
            return
        }

        try {
            val path = LabelPdfSaver.saveToDownloads(this, fileName, data)
            result.success(path)
        } catch (e: Exception) {
            result.error("save_failed", e.message, null)
        }
    }

    private fun readPdfBytes(call: MethodCall): ByteArray? {
        call.argument<ByteArray>("data")?.let { return it }

        val args = call.arguments as? Map<*, *> ?: return null
        return when (val raw = args["data"]) {
            is ByteArray -> raw
            is ByteBuffer -> {
                val bytes = ByteArray(raw.remaining())
                raw.get(bytes)
                bytes
            }
            else -> null
        }
    }
}
