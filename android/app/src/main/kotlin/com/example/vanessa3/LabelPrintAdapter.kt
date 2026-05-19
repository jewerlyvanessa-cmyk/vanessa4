package com.example.vanessa3

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.pdf.PdfDocument
import android.graphics.pdf.PdfRenderer
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import androidx.annotation.RequiresApi
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Setiap halaman PDF keluaran = tepat 80×12 mm (bukan Letter/A4).
 */
@RequiresApi(Build.VERSION_CODES.LOLLIPOP)
class LabelPrintAdapter(
    private val context: Context,
    private val jobName: String,
    private val documentData: ByteArray,
    private val pageWidthPt: Int,
    private val pageHeightPt: Int,
    private val fixedAttributes: PrintAttributes,
) : PrintDocumentAdapter() {

    private var pdfPageCount: Int = -1

    private fun openRenderer(): Pair<PdfRenderer, File> {
        val tempFile = File.createTempFile("vanessa_label_", ".pdf", context.cacheDir)
        FileOutputStream(tempFile).use { it.write(documentData) }
        val pfd = ParcelFileDescriptor.open(tempFile, ParcelFileDescriptor.MODE_READ_ONLY)
        return PdfRenderer(pfd) to tempFile
    }

    private fun ensurePageCount(renderer: PdfRenderer) {
        if (pdfPageCount < 0) {
            pdfPageCount = renderer.pageCount
        }
    }

    private fun pageIndices(pages: Array<PageRange>, total: Int): List<Int> {
        if (total <= 0) return emptyList()
        if (pages.isEmpty()) return (0 until total).toList()

        val indices = linkedSetOf<Int>()
        for (range in pages) {
            if (range.start == 0 && range.end < 0) {
                return (0 until total).toList()
            }
            val end = if (range.end < 0) total - 1 else minOf(range.end, total - 1)
            for (i in range.start..end) {
                if (i in 0 until total) indices.add(i)
            }
        }
        return if (indices.isEmpty()) (0 until total).toList() else indices.sorted()
    }

    override fun onLayout(
        oldAttributes: PrintAttributes?,
        newAttributes: PrintAttributes,
        cancellationSignal: CancellationSignal,
        callback: LayoutResultCallback,
        extras: Bundle?,
    ) {
        if (cancellationSignal.isCanceled) {
            callback.onLayoutCancelled()
            return
        }

        val attrs = fixedAttributes

        try {
            val (renderer, tempFile) = openRenderer()
            try {
                ensurePageCount(renderer)
            } finally {
                renderer.close()
                tempFile.delete()
            }
        } catch (e: IOException) {
            callback.onLayoutFailed(e.message)
            return
        }

        val count = pdfPageCount.coerceAtLeast(1)
        val info = PrintDocumentInfo.Builder(jobName)
            .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
            .setPageCount(count)
            .build()

        val changed = oldAttributes == null ||
            oldAttributes.mediaSize != attrs.mediaSize ||
            oldAttributes.minMargins != attrs.minMargins

        callback.onLayoutFinished(info, changed)
    }

    override fun onWrite(
        pages: Array<PageRange>,
        destination: ParcelFileDescriptor,
        cancellationSignal: CancellationSignal,
        callback: WriteResultCallback,
    ) {
        if (cancellationSignal.isCanceled) {
            callback.onWriteCancelled()
            return
        }

        var tempFile: File? = null
        var renderer: PdfRenderer? = null

        try {
            val opened = openRenderer()
            renderer = opened.first
            tempFile = opened.second
            ensurePageCount(renderer)

            val total = pdfPageCount
            if (total < 1) {
                callback.onWriteFailed("PDF kosong")
                return
            }

            val indices = pageIndices(pages, total)
            if (indices.isEmpty()) {
                callback.onWriteFailed("Tidak ada halaman untuk dicetak")
                return
            }

            // Selalu tulis ulang PDF dengan MediaBox tepat 80×12 mm per halaman
            // (hindari Save as PDF / printer yang membungkus ke Letter).
            val outputDoc = PdfDocument()
            try {
                for (pageIndex in indices) {
                    if (cancellationSignal.isCanceled) {
                        callback.onWriteCancelled()
                        return
                    }

                    val srcPage = renderer.openPage(pageIndex)
                    try {
                        val pageInfo = PdfDocument.PageInfo.Builder(
                            pageWidthPt,
                            pageHeightPt,
                            pageIndex,
                        )
                            .setContentRect(Rect(0, 0, pageWidthPt, pageHeightPt))
                            .create()

                        val outPage = outputDoc.startPage(pageInfo)
                        val canvas = outPage.canvas
                        canvas.drawColor(Color.WHITE)

                        val bitmap = Bitmap.createBitmap(
                            pageWidthPt,
                            pageHeightPt,
                            Bitmap.Config.ARGB_8888,
                        )
                        bitmap.eraseColor(Color.WHITE)

                        val scaleX = pageWidthPt.toFloat() / srcPage.width.toFloat()
                        val scaleY = pageHeightPt.toFloat() / srcPage.height.toFloat()
                        val matrix = Matrix()
                        matrix.setScale(scaleX, scaleY)

                        srcPage.render(
                            bitmap,
                            null,
                            matrix,
                            PdfRenderer.Page.RENDER_MODE_FOR_PRINT,
                        )
                        canvas.drawBitmap(bitmap, 0f, 0f, null)
                        bitmap.recycle()

                        outputDoc.finishPage(outPage)
                    } finally {
                        srcPage.close()
                    }
                }

                FileOutputStream(destination.fileDescriptor).use { out ->
                    outputDoc.writeTo(out)
                }

                callback.onWriteFinished(
                    arrayOf(PageRange(indices.first(), indices.last())),
                )
            } finally {
                outputDoc.close()
            }
        } catch (e: IOException) {
            callback.onWriteFailed(e.message)
        } finally {
            renderer?.close()
            tempFile?.delete()
        }
    }
}
