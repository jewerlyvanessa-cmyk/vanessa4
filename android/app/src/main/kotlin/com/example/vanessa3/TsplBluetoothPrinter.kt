package com.example.vanessa3

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
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
        val adapter = BluetoothAdapter.getDefaultAdapter()
            ?: throw IOException("Bluetooth tidak tersedia")
        if (!adapter.isEnabled) throw IOException("Bluetooth mati — nyalakan dulu")

        val device: BluetoothDevice = adapter.getRemoteDevice(address)
        val socket = device.createRfcommSocketToServiceRecord(sppUuid)
        try {
            adapter.cancelDiscovery()
            socket.connect()
            socket.outputStream.use { out ->
                out.write(data)
                out.flush()
            }
        } finally {
            try {
                socket.close()
            } catch (_: IOException) {
            }
        }
    }

    private fun BluetoothDevice.toMap(): Map<String, String> = mapOf(
        "name" to (name?.trim().takeUnless { it.isNullOrEmpty() } ?: "Printer"),
        "address" to address,
    )
}
