package com.sora214.plana.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import kotlin.math.ceil

/**
 * 预览图底部、名字胶囊所在那块的平均亮度 0..1。
 *
 * 系统解码器按 2 的幂抽样,解到几十像素宽,直接在 CPU 上数像素。
 * 取样区底部 22% 高,横向范围由 Dart 侧 PreviewTone 按胶囊位置给。
 */
object PreviewTone {
    /** 抽样后宽度不低于这个数。 */
    private const val MIN_WIDTH = 32

    private val pool = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())

    /** [bytes] 和 [path] 二选一;[x0]~[x1] 是取样区占宽度的比例。解不出来回 null。 */
    fun measure(
        path: String?,
        bytes: ByteArray?,
        x0: Double,
        x1: Double,
        result: MethodChannel.Result,
    ) {
        pool.execute {
            val tone = runCatching {
                decode(path, bytes)?.let { luminance(it, x0, x1) }
            }.getOrNull()
            main.post { result.success(tone) }
        }
    }

    private fun decode(path: String?, bytes: ByteArray?): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        read(path, bytes, bounds)
        if (bounds.outWidth <= 0) return null
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= MIN_WIDTH) sample *= 2
        val opts = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        return read(path, bytes, opts)
    }

    private fun read(path: String?, bytes: ByteArray?, opts: BitmapFactory.Options): Bitmap? =
        when {
            bytes != null -> BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
            path != null -> BitmapFactory.decodeFile(path, opts)
            else -> null
        }

    private fun luminance(bmp: Bitmap, fx0: Double, fx1: Double): Double? {
        try {
            val w = bmp.width
            val h = bmp.height
            val x0 = (w * fx0).toInt().coerceIn(0, w)
            val x1 = ceil(w * fx1).toInt().coerceIn(0, w)
            val y0 = (h * 0.78).toInt()
            val rw = x1 - x0
            val rh = h - y0
            if (rw <= 0 || rh <= 0) return null
            val px = IntArray(rw * rh)
            bmp.getPixels(px, 0, rw, x0, y0, rw, rh)
            var sum = 0.0
            for (c in px) {
                sum += 0.2126 * ((c shr 16) and 0xff) +
                    0.7152 * ((c shr 8) and 0xff) +
                    0.0722 * (c and 0xff)
            }
            return sum / px.size / 255
        } finally {
            bmp.recycle()
        }
    }
}
