package com.example.arxiv

import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.UUID

class MainActivity : FlutterActivity() {
    companion object {
        private const val TTS_CHANNEL = "com.example.arxiv/aosp_tts"
        private const val APP_LINKS_CHANNEL = "com.example.arxiv/app_links"
    }

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var ttsFailed = false
    private var pendingInitCallbacks = mutableListOf<(Boolean) -> Unit>()
    private var pendingLanguage: String = "en-US"
    private var pendingSpeechRate: Float = 1.0f
    private var lastUtteranceId: String? = null
    private var ttsChannel: MethodChannel? = null
    private var appLinksChannel: MethodChannel? = null
    private var pendingInitialLink: String? = null
    private var isAppLinksReady: Boolean = false
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val link = extractArxivLink(intent)
        if (link != null) {
            pendingInitialLink = link
        }
        appLinksChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_LINKS_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "getInitialLink") {
                    isAppLinksReady = true
                    val initial = pendingInitialLink
                    pendingInitialLink = null
                    result.success(initial)
                } else {
                    result.notImplemented()
                }
            }
        }
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TTS_CHANNEL)
        ttsChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setLanguage" -> {
                    val lang = call.argument<String>("language") ?: "en-US"
                    pendingLanguage = lang
                    ensureTts { ready ->
                        if (ready) {
                            applyLanguage(lang)
                        }
                        result.success(ready)
                    }
                }
                "setSpeechRate" -> {
                    val rate = (call.argument<Double>("rate") ?: 0.5).toFloat()
                    // Match flutter_tts scale: 0.5 -> 1.0x native AOSP speed
                    pendingSpeechRate = (rate * 2.0f).coerceIn(0.25f, 3.0f)
                    if (ttsReady) {
                        tts?.setSpeechRate(pendingSpeechRate)
                    }
                    result.success(true)
                }
                "speak" -> {
                    val text = call.argument<String>("text") ?: ""
                    if (text.isBlank()) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    ensureTts { ready ->
                        if (!ready) {
                            result.error(
                                "TTS_UNAVAILABLE",
                                "No AOSP text-to-speech engine is available on this device.",
                                null
                            )
                            return@ensureTts
                        }
                        val engine = tts
                        if (engine == null) {
                            result.error("TTS_UNAVAILABLE", "TTS engine not initialized.", null)
                            return@ensureTts
                        }
                        applyLanguage(pendingLanguage)
                        engine.setSpeechRate(pendingSpeechRate)

                        val maxLen = TextToSpeech.getMaxSpeechInputLength().coerceAtLeast(1000)
                        val chunks = splitIntoChunks(text, maxLen - 50)
                        var allQueued = true
                        chunks.forEachIndexed { index, chunk ->
                            val utteranceId = UUID.randomUUID().toString()
                            if (index == chunks.lastIndex) {
                                lastUtteranceId = utteranceId
                            }
                            val queueMode =
                                if (index == 0) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD
                            val status = engine.speak(chunk, queueMode, null, utteranceId)
                            if (status != TextToSpeech.SUCCESS) {
                                allQueued = false
                            }
                        }
                        if (allQueued) {
                            result.success(true)
                        } else {
                            result.error("TTS_SPEAK_ERROR", "Failed to speak text.", null)
                        }
                    }
                }
                "stop" -> {
                    lastUtteranceId = null
                    tts?.stop()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun ensureTts(callback: (Boolean) -> Unit) {
        if (ttsReady) {
            callback(true)
            return
        }
        if (ttsFailed) {
            callback(false)
            return
        }
        pendingInitCallbacks.add(callback)
        if (tts != null) return

        tts = TextToSpeech(applicationContext) { status ->
            mainHandler.post {
                val success = status == TextToSpeech.SUCCESS
                ttsReady = success
                ttsFailed = !success
                if (success) {
                    tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {}

                        override fun onDone(utteranceId: String?) {
                            if (utteranceId != null && utteranceId == lastUtteranceId) {
                                mainHandler.post {
                                    ttsChannel?.invokeMethod("onComplete", null)
                                }
                            }
                        }

                        @Deprecated("Deprecated in Java")
                        override fun onError(utteranceId: String?) {
                            mainHandler.post {
                                ttsChannel?.invokeMethod("onError", "Speech playback failed.")
                            }
                        }

                        override fun onError(utteranceId: String?, errorCode: Int) {
                            mainHandler.post {
                                ttsChannel?.invokeMethod(
                                    "onError",
                                    "Speech playback failed (code $errorCode)."
                                )
                            }
                        }
                    })
                    applyLanguage(pendingLanguage)
                    tts?.setSpeechRate(pendingSpeechRate)
                }
                val callbacks = pendingInitCallbacks.toList()
                pendingInitCallbacks.clear()
                callbacks.forEach { it(success) }
            }
        }
    }

    private fun applyLanguage(languageTag: String) {
        val locale = Locale.forLanguageTag(languageTag)
        val res = tts?.setLanguage(locale)
        if (res == TextToSpeech.LANG_MISSING_DATA || res == TextToSpeech.LANG_NOT_SUPPORTED) {
            tts?.setLanguage(Locale.US)
        }
    }

    private fun splitIntoChunks(text: String, maxLength: Int): List<String> {
        if (text.length <= maxLength) return listOf(text)
        val chunks = mutableListOf<String>()
        var remaining = text.trim()
        while (remaining.length > maxLength) {
            val window = remaining.substring(0, maxLength)
            val splitAt = listOf(
                window.lastIndexOf(". "),
                window.lastIndexOf("! "),
                window.lastIndexOf("? "),
                window.lastIndexOf('\n'),
                window.lastIndexOf(' ')
            ).maxOrNull()?.takeIf { it > maxLength / 3 } ?: maxLength
            chunks.add(remaining.substring(0, splitAt).trim())
            remaining = remaining.substring(splitAt).trim()
        }
        if (remaining.isNotEmpty()) {
            chunks.add(remaining)
        }
        return chunks
    }

    private fun extractArxivLink(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val data = intent.dataString ?: return null
        return if (data.contains("arxiv.org", ignoreCase = true)) data else null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = extractArxivLink(intent) ?: return
        val channel = appLinksChannel
        if (isAppLinksReady && channel != null) {
            mainHandler.post {
                channel.invokeMethod("onLink", link)
            }
        } else {
            pendingInitialLink = link
        }
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
}
