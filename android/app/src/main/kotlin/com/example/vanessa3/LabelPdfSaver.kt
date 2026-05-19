package com.example.vanessa3

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.IOException

object LabelPdfSaver {
    @Throws(IOException::class)
    fun saveToDownloads(context: Context, fileName: String, pdfBytes: ByteArray): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf")
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("Gagal membuat file di Downloads")
            resolver.openOutputStream(uri)?.use { it.write(pdfBytes) }
                ?: throw IOException("Gagal menulis PDF")
            return uri.toString()
        }

        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!dir.exists() && !dir.mkdirs()) {
            throw IOException("Folder Downloads tidak tersedia")
        }
        val file = File(dir, fileName)
        file.writeBytes(pdfBytes)
        return file.absolutePath
    }
}
