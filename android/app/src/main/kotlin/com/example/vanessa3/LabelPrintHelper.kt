package com.example.vanessa3

import android.content.Context
import android.print.PrintAttributes
import android.print.PrintManager
import kotlin.math.roundToInt

object LabelPrintHelper {
    private const val LABEL_ID = "vanessa_label_80x12"
    private const val LABEL_NAME = "80 × 12 mm"

    fun mmToPoints(mm: Double): Int = (mm * 72.0 / 25.4).roundToInt()

    fun mmToMils(mm: Double): Int = (mm / 25.4 * 1000.0).roundToInt()

    /**
     * Ukuran kertas custom 80 mm (lebar) × 12 mm (tinggi).
     * Di Android, lebar > tinggi = orientasi landscape pada level sistem;
     * isi PDF tetap 80×12 mm sesuai layout label.
     */
    fun mediaSizeForLabel(widthMm: Double, heightMm: Double): PrintAttributes.MediaSize {
        val widthMils = mmToMils(widthMm)
        val heightMils = mmToMils(heightMm)
        return PrintAttributes.MediaSize(LABEL_ID, LABEL_NAME, widthMils, heightMils)
    }

    fun printLabelPdf(
        context: Context,
        jobName: String,
        widthMm: Double,
        heightMm: Double,
        pdfBytes: ByteArray,
    ) {
        val printManager = context.getSystemService(Context.PRINT_SERVICE) as PrintManager
        val mediaSize = mediaSizeForLabel(widthMm, heightMm)
        val attributes = PrintAttributes.Builder()
            .setMediaSize(mediaSize)
            .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
            .setColorMode(PrintAttributes.COLOR_MODE_MONOCHROME)
            .setResolution(
                PrintAttributes.Resolution("label_dpi", "Label", 203, 203),
            )
            .build()

        val pageWidthPt = mmToPoints(widthMm)
        val pageHeightPt = mmToPoints(heightMm)

        printManager.print(
            jobName,
            LabelPrintAdapter(
                context.applicationContext,
                jobName,
                pdfBytes,
                pageWidthPt,
                pageHeightPt,
                attributes,
            ),
            attributes,
        )
    }
}
