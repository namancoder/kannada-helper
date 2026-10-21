package __PACKAGE__

import android.os.Handler
import android.os.Looper
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Kannada Helper: native OCR bridge for Scan mode.
 *
 * Dart (lib/engines/tesseract_ocr.dart) calls channel "kannada_helper/ocr":
 *  - dataDir -> folder that holds tessdata/kan.traineddata
 *  - read {path, lang, psm} -> text found in the image file
 *
 * Uses Tesseract4Android (cz.adaptech.tesseract4android). OCR runs on one
 * background thread; the engine is created once and reused.
 * Source of truth: tool/android/MainActivity.kt (copied by patch_android.dart).
 */
class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private val mainThread = Handler(Looper.getMainLooper())
    private var tess: TessBaseAPI? = null
    private var tessLang: String? = null

    private fun dataDir(): File = File(filesDir, "tesseract")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kannada_helper/ocr")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "dataDir" -> result.success(dataDir().absolutePath)
                    "read" -> {
                        val path = call.argument<String>("path")
                        val lang = call.argument<String>("lang") ?: "kan"
                        val psm = call.argument<Int>("psm") ?: TessBaseAPI.PageSegMode.PSM_SINGLE_BLOCK
                        if (path == null) {
                            result.error("BAD_ARGS", "path is required", null)
                        } else {
                            worker.execute {
                                try {
                                    val api = engine(lang)
                                    api.setPageSegMode(psm)
                                    api.setImage(File(path))
                                    val text = api.getUTF8Text() ?: ""
                                    api.clear()
                                    mainThread.post { result.success(text) }
                                } catch (e: Exception) {
                                    mainThread.post { result.error("OCR_FAILED", e.message, null) }
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
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
        }
        worker.shutdown()
        super.onDestroy()
    }
}
