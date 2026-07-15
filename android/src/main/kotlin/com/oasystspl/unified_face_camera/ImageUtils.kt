package com.oasystspl.unified_face_camera

import android.graphics.*
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.*

/**
 * Utility object for post-processing captured face images.
 *
 * The timestamp format is: `DD-MM-YYYY hh:mm AM/PM`
 * Example: `09-07-2026 11:45 AM`
 */
object ImageUtils {

    /**
     * Returns the rotation degrees encoded in the EXIF orientation tag of [filePath].
     */
    private fun getExifRotationDegrees(filePath: String): Int {
        return try {
            val exif = ExifInterface(filePath)
            when (exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90  -> 90
                ExifInterface.ORIENTATION_ROTATE_180 -> 180
                ExifInterface.ORIENTATION_ROTATE_270 -> 270
                else -> 0
            }
        } catch (e: Exception) {
            android.util.Log.w("UnifiedFaceCamera", "Could not read EXIF orientation: $e")
            0
        }
    }

    /**
     * Rotates [bitmap] by [degrees] and returns the new bitmap (recycles the old one).
     */
    private fun rotateBitmap(bitmap: Bitmap, degrees: Int): Bitmap {
        if (degrees == 0) return bitmap
        val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (rotated !== bitmap) bitmap.recycle()
        return rotated
    }

    /**
     * Embeds a date/time timestamp onto the image located at [imagePath] and
     * overwrites it with a JPEG-compressed version.
     *
     * Reads the EXIF orientation tag and rotates the bitmap so the final
     * saved image is always in the correct (portrait) orientation.
     *
     * @return The absolute path of the updated image, or `null` on failure.
     */
    fun addTimestamp(imagePath: String, latitude: Double?, longitude: Double?): String? {
        val file = File(imagePath)
        if (!file.exists()) {
            android.util.Log.e("UnifiedFaceCamera", "File does not exist: $imagePath")
            return null
        }
        if (file.length() == 0L) {
            android.util.Log.e("UnifiedFaceCamera", "File is empty: $imagePath")
            return null
        }

        return try {
            // Read EXIF rotation BEFORE decoding (ExifInterface needs the file path)
            val rotationDegrees = getExifRotationDegrees(file.absolutePath)

            val rawBitmap = BitmapFactory.decodeFile(file.absolutePath) ?: return null

            // Rotate to portrait if the sensor wrote it sideways
            val bitmap = rotateBitmap(rawBitmap, rotationDegrees)

            val mutableBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, true)
            if (mutableBitmap !== bitmap) bitmap.recycle()

            val canvas = Canvas(mutableBitmap)

            // ── Timestamp text paint ────────────────────────────────────────
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                textSize = mutableBitmap.width / 22f
                typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
                setShadowLayer(4f, 2f, 2f, Color.BLACK)
            }

            // ── Format: DD-MM-YYYY hh:mm AM/PM ─────────────────────────────
            // Using "hh" (12-hour) and "a" (AM/PM marker).
            val sdf = SimpleDateFormat("dd-MM-yyyy hh:mm a", Locale.US)
            val timestamp = sdf.format(Date())

            val locationText = if (latitude != null && longitude != null) {
                String.format(Locale.US, "Lat: %.4f, Long: %.4f", latitude, longitude)
            } else {
                "Location: Not Available"
            }

            val boundsTimestamp = Rect()
            paint.getTextBounds(timestamp, 0, timestamp.length, boundsTimestamp)

            val boundsLocation = Rect()
            paint.getTextBounds(locationText, 0, locationText.length, boundsLocation)

            val maxTextWidth = Math.max(boundsTimestamp.width(), boundsLocation.width())
            val lineHeight = boundsTimestamp.height()
            val spacing = lineHeight * 0.4f
            val totalTextHeight = (lineHeight * 2 + spacing).toInt()

            // ── Semi-transparent background behind text ──────────────────────
            val padding = mutableBitmap.width * 0.02f
            val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.argb(160, 0, 0, 0)
                style = Paint.Style.FILL
            }
            val textX = mutableBitmap.width - maxTextWidth - padding * 2
            val textY = mutableBitmap.height - padding * 2 - lineHeight - spacing
            canvas.drawRect(
                textX - padding,
                textY - boundsTimestamp.height() - padding,
                mutableBitmap.width.toFloat(),
                mutableBitmap.height.toFloat(),
                bgPaint
            )

            // Draw timestamp line
            canvas.drawText(timestamp, textX, textY, paint)
            // Draw location line
            canvas.drawText(locationText, textX, textY + lineHeight + spacing, paint)

            // ── Save overwriting the original file ──────────────────────────
            FileOutputStream(file).use { out ->
                mutableBitmap.compress(Bitmap.CompressFormat.JPEG, 97, out)
                out.flush()
            }

            mutableBitmap.recycle()
            file.absolutePath
        } catch (e: Exception) {
            android.util.Log.e("UnifiedFaceCamera", "ImageUtils Error", e)
            null
        }
    }
}
