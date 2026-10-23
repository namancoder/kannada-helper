package dev.ng.kannada_helper

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.FloatBuffer
import java.util.concurrent.Executors
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min

/**
 * Kannada Helper: native OCR bridge for Scan mode.
 *
 * Dart (lib/engines/hybrid_ocr.dart) calls channel "kannada_helper/ocr":
 *  - dataDir -> folder that holds tessdata/kan.traineddata
 *  - read {path, lang, psm} -> Tesseract only: {text, confidence}
 *  - readWords {path, psm} -> hybrid: Tesseract finds the words; both Tesseract
 *    and the PARSeq model (IndicPhotoOCR, bundled as a Flutter asset) read each
 *    one, and the more confident reading wins per word. Returns {text,
 *    confidence, engine, words, parseqText, tessText, tessConfidence, ms}.
 *    Falls back to Tesseract alone if the model can't be loaded.
 *
 * Tesseract: Tesseract4Android. PARSeq: ONNX Runtime for Android.
 * Everything runs on one background thread; engines are created once.
 * Source of truth: tool/android/MainActivity.kt (copied by patch_android.dart).
 */
class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private val mainThread = Handler(Looper.getMainLooper())
    private var tess: TessBaseAPI? = null
    private var tessLang: String? = null
    private var parseq: ParseqReader? = null
    private var parseqError: String? = null

    private fun dataDir(): File = File(filesDir, "tesseract")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kannada_helper/ocr")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "dataDir" -> result.success(dataDir().absolutePath)
                    "read", "readWords" -> {
                        val path = call.argument<String>("path")
                        val lang = call.argument<String>("lang") ?: "kan"
                        val psm = call.argument<Int>("psm") ?: TessBaseAPI.PageSegMode.PSM_SINGLE_BLOCK
                        val hybrid = call.method == "readWords"
                        if (path == null) {
                            result.error("BAD_ARGS", "path is required", null)
                        } else {
                            worker.execute {
                                try {
                                    val out = if (hybrid) readWords(path, lang, psm) else readTesseract(path, lang, psm)
                                    mainThread.post { result.success(out) }
                                } catch (e: Throwable) {
                                    mainThread.post { result.error("OCR_FAILED", e.message, null) }
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Tesseract alone (the original engine). */
    private fun readTesseract(path: String, lang: String, psm: Int): Map<String, Any> {
        val api = engine(lang)
        api.setPageSegMode(psm)
        api.setImage(File(path))
        val text = api.getUTF8Text() ?: ""
        val confidence = api.meanConfidence()
        api.clear()
        return mapOf("text" to text, "confidence" to confidence, "engine" to "tesseract")
    }

    /** Tesseract finds word boxes; PARSeq reads each word. */
    private fun readWords(path: String, lang: String, psm: Int): Map<String, Any> {
        val start = SystemClock.elapsedRealtime()
        // ARGB_8888: what both Tesseract4Android and getPixels() expect.
        val opts = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
        val bitmap = BitmapFactory.decodeFile(path, opts)
            ?: throw IllegalArgumentException("Could not decode $path")
        try {
            // 1. Tesseract: word positions (and its own reading, kept as a fallback).
            val api = engine(lang)
            api.setPageSegMode(psm)
            api.setImage(bitmap)
            val tessText = api.getUTF8Text() ?: ""
            val tessConfidence = api.meanConfidence()
            val boxes = mutableListOf<TessWord>()
            if (tessText.isNotBlank()) {
                val iter = api.resultIterator
                if (iter != null) {
                    val level = TessBaseAPI.PageIteratorLevel.RIL_WORD
                    iter.begin()
                    do {
                        val r = iter.getBoundingRect(level)
                        if (r.width() >= 4 && r.height() >= 6) {
                            boxes.add(TessWord(Rect(r), iter.getUTF8Text(level) ?: "", iter.confidence(level)))
                        }
                    } while (iter.next(level))
                    iter.delete()
                }
            }
            api.clear()

            val reader = parseqReader()
            if (reader == null) {
                return mapOf(
                    "text" to tessText, "confidence" to tessConfidence, "engine" to "tesseract",
                    "words" to boxes.size, "tessText" to tessText, "tessConfidence" to tessConfidence,
                    "ms" to (SystemClock.elapsedRealtime() - start), "note" to (parseqError ?: ""),
                )
            }

            // 2. PARSeq reads each word too; per word, the more confident engine
            //    wins. (Tesseract does well on clean printed fonts, PARSeq on real
            //    photos and signboards.) No boxes, e.g. one big word on a sign:
            //    read the whole image as a single word with PARSeq.
            if (boxes.isEmpty()) boxes.add(TessWord(Rect(0, 0, bitmap.width, bitmap.height), "", -1f))
            val lines = groupIntoLines(boxes)
            val sb = StringBuilder()
            val parseqOnly = StringBuilder()
            var confSum = 0f
            var count = 0
            var fromParseq = 0
            for ((li, line) in lines.withIndex()) {
                if (li > 0) {
                    sb.append('\n')
                    parseqOnly.append('\n')
                }
                for (w in line) {
                    val crop = cropWithMargin(bitmap, w.box) ?: continue
                    val (pWord, pConf) = try {
                        reader.read(crop)
                    } finally {
                        // createBitmap can hand back the source itself for a full-size crop.
                        if (crop !== bitmap) crop.recycle()
                    }
                    val pScore = pConf * 100f
                    val tWord = ParseqReader.fixAnusvara(w.text.trim())
                    val useParseq = tWord.isEmpty() || (pWord.isNotEmpty() && pScore >= w.confidence)
                    val word = if (useParseq) pWord else tWord
                    if (pWord.isNotEmpty()) {
                        if (parseqOnly.isNotEmpty() && parseqOnly.last() != '\n') parseqOnly.append(' ')
                        parseqOnly.append(pWord)
                    }
                    if (word.isEmpty()) continue
                    if (sb.isNotEmpty() && sb.last() != '\n') sb.append(' ')
                    sb.append(word)
                    confSum += if (useParseq) pScore else w.confidence
                    count++
                    if (useParseq) fromParseq++
                }
            }
            val confidence = if (count == 0) 0 else (confSum / count).toInt()
            return mapOf(
                "text" to sb.toString(), "confidence" to confidence,
                "engine" to "best-of-both ($fromParseq/$count words from PARSeq)",
                "words" to count, "parseqText" to parseqOnly.toString(),
                "tessText" to tessText, "tessConfidence" to tessConfidence,
                "ms" to (SystemClock.elapsedRealtime() - start),
            )
        } finally {
            bitmap.recycle()
        }
    }

    /** One word as Tesseract saw it: where it is, what it read, how sure (0-100). */
    private data class TessWord(val box: Rect, val text: String, val confidence: Float)

    /** Sorts words into reading order: top-to-bottom lines, left-to-right words. */
    private fun groupIntoLines(words: List<TessWord>): List<List<TessWord>> {
        val lines = mutableListOf<MutableList<TessWord>>()
        for (w in words.sortedBy { it.box.centerY() }) {
            val line = lines.lastOrNull()
            val sameLine = line != null && run {
                val top = line.minOf { it.box.top }
                val bottom = line.maxOf { it.box.bottom }
                w.box.centerY() in top..bottom
            }
            if (sameLine) line!!.add(w) else lines.add(mutableListOf(w))
        }
        return lines.map { l -> l.sortedBy { it.box.left } }
    }

    /** Tesseract's boxes can clip Kannada vowel signs above/below; add a margin. */
    private fun cropWithMargin(src: Bitmap, box: Rect): Bitmap? {
        val padY = (box.height() * 0.25f).toInt()
        val padX = (box.height() * 0.15f).toInt()
        val l = max(0, box.left - padX)
        val t = max(0, box.top - padY)
        val r = min(src.width, box.right + padX)
        val b = min(src.height, box.bottom + padY)
        if (r - l < 4 || b - t < 6) return null
        return Bitmap.createBitmap(src, l, t, r - l, b - t)
    }

    /** Runs on the worker thread only. Null if the model couldn't be loaded. */
    private fun parseqReader(): ParseqReader? {
        parseq?.let { return it }
        if (parseqError != null) return null
        return try {
            val loader = FlutterInjector.instance().flutterLoader()
            val model = assets.open(loader.getLookupKeyForAsset(MODEL_ASSET)).use { it.readBytes() }
            val charset = assets.open(loader.getLookupKeyForAsset(CHARSET_ASSET))
                .use { it.readBytes().toString(Charsets.UTF_8) }.split('\n')
            ParseqReader(model, charset).also { parseq = it }
        } catch (e: Throwable) {
            parseqError = "PARSeq unavailable: ${e.message}"
            null
        }
    }

    /** Runs on the worker thread only. */
    private fun engine(lang: String): TessBaseAPI {
        val current = tess
        if (current != null && tessLang == lang) return current
        current?.recycle()
        tess = null
        val api = TessBaseAPI()
        if (!api.init(dataDir().absolutePath, lang)) {
            api.recycle()
            throw IllegalStateException("Tesseract could not load '$lang'. Is the model downloaded?")
        }
        api.setVariable("preserve_interword_spaces", "1")
        tess = api
        tessLang = lang
        return api
    }

    override fun onDestroy() {
        worker.execute {
            tess?.recycle()
            tess = null
            parseq?.close()
            parseq = null
        }
        worker.shutdown()
        super.onDestroy()
    }

    companion object {
        const val MODEL_ASSET = "models/kannada_parseq_int8.onnx"
        const val CHARSET_ASSET = "models/kannada_parseq_charset.txt"
    }
}

/**
 * IndicPhotoOCR's Kannada PARSeq word reader (ONNX, int8).
 * Input: one word image -> RGB 32x128, scaled to [-1, 1].
 * Output logits [1, 26, 100]: per position, the most likely class;
 * class 0 means "end of word"; class i maps to line i of the charset file.
 */
class ParseqReader(model: ByteArray, private val charset: List<String>) : AutoCloseable {
    private val env = OrtEnvironment.getEnvironment()
    private val session: OrtSession = env.createSession(
        model,
        OrtSession.SessionOptions().apply {
            setIntraOpNumThreads(2)
            setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
        },
    )
    private val inputName = session.inputNames.first()

    /** Returns the word and a confidence in 0..1 (geometric mean of letter probabilities). */
    fun read(word: Bitmap): Pair<String, Float> {
        val scaled = Bitmap.createScaledBitmap(word, W, H, true)
        val px = IntArray(W * H)
        scaled.getPixels(px, 0, W, 0, 0, W, H)
        if (scaled !== word) scaled.recycle()

        val buf = FloatBuffer.allocate(3 * H * W)
        for (shift in intArrayOf(16, 8, 0)) { // R, G, B planes
            for (p in px) buf.put((((p shr shift) and 0xFF) / 255f - 0.5f) / 0.5f)
        }
        buf.rewind()

        OnnxTensor.createTensor(env, buf, longArrayOf(1, 3, H.toLong(), W.toLong())).use { input ->
            session.run(mapOf(inputName to input)).use { out ->
                @Suppress("UNCHECKED_CAST")
                val logits = (out[0].value as Array<Array<FloatArray>>)[0]
                val sb = StringBuilder()
                var logProb = 0.0
                var n = 0
                for (row in logits) {
                    var best = 0
                    for (i in row.indices) if (row[i] > row[best]) best = i
                    var sum = 0.0
                    for (v in row) sum += exp((v - row[best]).toDouble())
                    logProb += ln(1.0 / sum) // softmax probability of the winner
                    n++
                    if (best == 0) break // end of word
                    if (best < charset.size) sb.append(charset[best])
                }
                val text = fixAnusvara(sb.toString().trim())
                val confidence = if (n == 0) 0f else exp(logProb / n).toFloat()
                return text to confidence
            }
        }
    }

    override fun close() = session.close()

    companion object {
        const val H = 32
        const val W = 128

        /** The model often reads the anusvara dot (ಂ) as Kannada digit zero (೦).
         *  A zero right after a letter or vowel sign is really the anusvara. */
        private val ZERO_AFTER_LETTER = Regex("(?<=[\\u0C85-\\u0CB9\\u0CBE-\\u0CCC])\\u0CE6")
        fun fixAnusvara(s: String) = ZERO_AFTER_LETTER.replace(s, "ಂ")
    }
}
