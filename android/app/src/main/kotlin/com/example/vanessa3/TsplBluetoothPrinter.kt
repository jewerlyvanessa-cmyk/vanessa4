package com.example.vanessa3

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import java.io.IOException
import java.util.UUID

/**
 * Kirim perintah TSPL mentah ke printer label Bluetooth (SPP).
 * Cocok untuk Xprinter XP-TT426B yang sudah di-pair di pengaturan Android.
 */
object TsplBluetoothPrinter {
    private val sppUuid: UUID =
        UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    private const val CHUNK_SIZE = 1024
    private const val CHUNK_DELAY_MS = 25L
    private const val BASE_SETTLE_MS = 250L
    private const val SETTLE_PER_KB_MS = 40L
    private const val SETTLE_PER_LABEL_MS = 400L
    private const val MAX_SETTLE_MS = 15000L
    private const val GAPDETECT_SETTLE_MS = 8000L
    private const val CONNECT_RETRY_DELAY_MS = 400L

    fun hasNearbyPermissions(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val connectGranted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.BLUETOOTH_CONNECT,
        ) == PackageManager.PERMISSION_GRANTED
        val scanGranted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.BLUETOOTH_SCAN,
        ) == PackageManager.PERMISSION_GRANTED
        return connectGranted && scanGranted
    }

    // Tidak ada pre-check izin sebelum operasi — checkSelfPermission tidak akurat
    // di beberapa ROM (Xiaomi/MIUI). SecurityException dari bondedDevices / name
    // dilempar jika izin benar-benar tidak ada di level OS.
    @Throws(SecurityException::class)
    fun listBondedDevices(context: Context): List<Map<String, String>> {
        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter: BluetoothAdapter? = manager?.adapter ?: BluetoothAdapter.getDefaultAdapter()
        if (adapter == null || !adapter.isEnabled) return emptyList()

        return adapter.bondedDevices
            .sortedBy { it.name?.lowercase() ?: it.address }
            .map { device -> device.toMap() }
    }

    @Throws(IOException::class, SecurityException::class)
    fun print(address: String, data: ByteArray) {
        if (data.isEmpty()) throw IOException("Data TSPL kosong")

        val adapter = BluetoothAdapter.getDefaultAdapter()
            ?: throw IOException("Bluetooth tidak tersedia")
        if (!adapter.isEnabled) throw IOException("Bluetooth mati — nyalakan dulu")

        val device: BluetoothDevice = adapter.getRemoteDevice(address)
        adapter.cancelDiscovery()

        var lastError: IOException? = null
        repeat(2) { attempt ->
            try {
                val socket = connectDevice(device)
                try {
                    Thread.sleep(80)
                    writeAll(socket, data)
                    return
                } catch (e: IOException) {
                    lastError = e
                    try {
                        socket.close()
                    } catch (_: IOException) {
                    }
                }
            } catch (e: IOException) {
                lastError = e
            }
            if (attempt == 0) Thread.sleep(CONNECT_RETRY_DELAY_MS)
        }
        throw lastError ?: IOException("Gagal mengirim ke printer")
    }

    @Throws(IOException::class)
    private fun connectDevice(device: BluetoothDevice): BluetoothSocket {
        val factories: List<() -> BluetoothSocket> = listOf(
            { device.createRfcommSocketToServiceRecord(sppUuid) },
            { createRfcommFallback(device) },
        )
        var lastError: IOException? = null
        for (factory in factories) {
            val socket = try {
                factory()
            } catch (e: IOException) {
                lastError = e
                continue
            }
            try {
                socket.connect()
                return socket
            } catch (e: IOException) {
                lastError = e
                try {
                    socket.close()
                } catch (_: IOException) {
                }
            }
        }
        throw lastError ?: IOException("Tidak bisa terhubung ke printer")
    }

    @Throws(IOException::class)
    private fun createRfcommFallback(device: BluetoothDevice): BluetoothSocket {
        return try {
            val method = device.javaClass.getMethod(
                "createRfcommSocket",
                Int::class.javaPrimitiveType,
            )
            method.invoke(device, 1) as BluetoothSocket
        } catch (e: Exception) {
            throw IOException("Tidak bisa membuka koneksi Bluetooth ke printer", e)
        }
    }

    @Throws(IOException::class)
    private fun writeAll(socket: BluetoothSocket, data: ByteArray) {
        val out = socket.outputStream
        var offset = 0
        while (offset < data.size) {
            val end = minOf(offset + CHUNK_SIZE, data.size)
            out.write(data, offset, end - offset)
            out.flush()
            offset = end
            if (offset < data.size) Thread.sleep(CHUNK_DELAY_MS)
        }

        Thread.sleep(estimateSettleMs(data))

        try {
            socket.close()
        } catch (_: IOException) {
        }
    }

    private fun estimateSettleMs(data: ByteArray): Long {
        val text = String(data, Charsets.UTF_8)
        if (text.contains("GAPDETECT", ignoreCase = true)) {
            return GAPDETECT_SETTLE_MS
        }

        val printCount = Regex("PRINT\\s+1,1", RegexOption.IGNORE_CASE)
            .findAll(text)
            .count()
        val sizeBased = BASE_SETTLE_MS + (data.size / 1024) * SETTLE_PER_KB_MS
        val labelBased = printCount * SETTLE_PER_LABEL_MS
        return (sizeBased + labelBased).coerceIn(BASE_SETTLE_MS, MAX_SETTLE_MS)
    }

    private fun BluetoothDevice.toMap(): Map<String, String> = mapOf(
        "name" to (name?.trim().takeUnless { it.isNullOrEmpty() } ?: "Printer"),
        "address" to address,
    )
}
