package com.lxmoon.image_ocr

import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.FlutterInjector
import java.io.File

class MainApplication : Application() {
    // Make flutterEngine nullable and private
    private var flutterEngine: FlutterEngine? = null
    private val METHOD_CHANNEL = "com.lxmoon.image_ocr/screenshot"
    private val EVENT_CHANNEL = "com.lxmoon.image_ocr/screenshot_events"

    companion object {
        const val FLUTTER_ENGINE_ID = "main_engine"
        
        @Volatile
        private var eventSink: EventChannel.EventSink? = null

        fun getEventSink(): EventChannel.EventSink? {
            return eventSink
        }
    }

    override fun onCreate() {
        super.onCreate()
        // Do not initialize the engine here to avoid startup crashes.
        // It will be initialized lazily when needed.
    }

    /**
     * Creates and configures a new FlutterEngine instance if it doesn't exist.
     * This method is synchronized to be thread-safe.
     */
    @Synchronized
    fun getFlutterEngine(context: Context, isMainActivity: Boolean): FlutterEngine {
        if (flutterEngine == null) {
            // Create a new FlutterEngine.
            flutterEngine = FlutterEngine(context.applicationContext)

            // Determine which Dart entrypoint to use
            val entrypoint = if (isMainActivity) {
                DartExecutor.DartEntrypoint.createDefault()
            } else {
                DartExecutor.DartEntrypoint(
                    FlutterInjector.instance().flutterLoader().findAppBundlePath(), "backgroundMain"
                )
            }

            // Start executing the chosen Dart code.
            flutterEngine!!.dartExecutor.executeDartEntrypoint(entrypoint)

            // Cache the FlutterEngine to be used by other components.
            FlutterEngineCache
                .getInstance()
                .put(FLUTTER_ENGINE_ID, flutterEngine)
                
            // Register all channels.
            registerChannels(flutterEngine!!)
        }
        return flutterEngine!!
    }


    private fun registerChannels(engine: FlutterEngine) {
        EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )

        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
             val mainActivity = MainActivity.getInstance()

            when (call.method) {
                "checkAccessibilityPermission", 
                "requestAccessibilityPermission", 
                "takeScreenshot", 
                "checkRootPermission", 
                "requestRootPermission" -> {
                    if (mainActivity == null) {
                        // If activity is not available, try to launch it for critical actions
                        val intent = Intent(this, MainActivity::class.java).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                        }
                        startActivity(intent)
                        result.error("ACTIVITY_UNAVAILABLE", "MainActivity was not available, attempting to launch it. Please try again.", null)
                        return@setMethodCallHandler
                    }
                    when(call.method) {
                        "checkAccessibilityPermission" -> result.success(mainActivity.isAccessibilityServiceEnabled())
                        "requestAccessibilityPermission" -> {
                             val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                             intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                             mainActivity.startActivity(intent)
                             result.success(null)
                        }
                        "takeScreenshot" -> result.success(mainActivity.triggerScreenshotMultipleWays())
                        "checkRootPermission" -> result.success(mainActivity.isRootAvailable())
                        "requestRootPermission" -> mainActivity.requestRootPermission(result)
                    }
                }
                "getPicturesDirectory" -> {
                    try {
                        val picturesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
                        val appDir = File(picturesDir, MainActivity.PICTURES_SUB_DIR)
                        result.success(appDir.absolutePath)
                    } catch (e: Exception) {
                        result.error("UNAVAILABLE", "Could not get public pictures directory.", e.toString())
                    }
                }
                "wakeUp" -> {
                    val intent = Intent(this, MainActivity::class.java).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                    }
                    startActivity(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}