package com.example.vanessa3

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer

// FlutterFragmentActivity diperlukan agar registerForActivityResult (izin Bluetooth) berfungsi.
class MainActivity : FlutterFragmentActivity() {
    private var pendingBluetoothPermissionResult: MethodChannel.Result? = null

    private val bluetoothPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { grants: Map<String, Boolean> ->
        val granted = grants.values.all { it }
        pendingBluetoothPermissionResult?.success(granted)
        pendingBluetoothPermissionResult = null
    }

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
                "hasBluetoothPermission" -> {
                    result.success(TsplBluetoothPrinter.hasNearbyPermissions(this))
                }
                "requestBluetoothPermission" -> handleRequestBluetoothPermission(result)
                "openAppSettings" -> {
                    startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", packageName, null),
                        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(true)
                }
                "listBondedBluetoothPrinters" -> handleListBondedBluetooth(result)
                "printTsplBluetooth" -> handlePrintTsplBluetooth(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleRequestBluetoothPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.success(true)
            return
        }
        if (TsplBluetoothPrinter.hasNearbyPermissions(this)) {
            result.success(true)
            return
        }
        if (pendingBluetoothPermissionResult != null) {
            result.error("busy", "Permintaan izin Bluetooth sedang berjalan", null)
            return
        }
        pendingBluetoothPermissionResult = result
        bluetoothPermissionLauncher.launch(
            arrayOf(
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_SCAN,
            ),
        )
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

    private fun handleListBondedBluetooth(result: MethodChannel.Result) {
        // Tidak ada pre-check checkSelfPermission — bisa tidak akurat di Xiaomi/MIUI.
        // SecurityException dari operasi Bluetooth yang mengonfirmasi izin sesungguhnya.
        try {
            result.success(TsplBluetoothPrinter.listBondedDevices(this))
        } catch (e: SecurityException) {
            result.error("permission_denied", "Izin perangkat terdekat (Bluetooth) belum diberikan", null)
        } catch (e: Exception) {
            result.error("bt_error", e.message, null)
        }
    }

    private fun handlePrintTsplBluetooth(call: MethodCall, result: MethodChannel.Result) {
        val address = call.argument<String>("address")?.trim().orEmpty()
        val data = readPdfBytes(call)
        if (address.isEmpty() || data == null) {
            result.error("invalid_args", "address and data required", null)
            return
        }
        // Kirim di thread terpisah — write + settle delay bisa >1 detik.
        Thread {
            try {
                TsplBluetoothPrinter.print(address, data)
                runOnUiThread { result.success(true) }
            } catch (e: SecurityException) {
                runOnUiThread {
                    result.error(
                        "permission_denied",
                        "Izin perangkat terdekat (Bluetooth) belum diberikan",
                        null,
                    )
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("print_failed", e.message, null)
                }
            }
        }.start()
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
