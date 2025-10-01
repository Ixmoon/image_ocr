
package com.lxmoon.image_ocr

import android.content.*
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import android.Manifest
import android.content.pm.PackageManager

class MainActivity: FlutterFragmentActivity() {
    private val METHOD_CHANNEL = "com.lxmoon.image_ocr/screenshot"
    private val NOTIFICATION_PERMISSION_REQUEST_CODE = 101
    private val EVENT_CHANNEL = "com.lxmoon.image_ocr/screenshot_events"

    companion object {
        // IMPORTANT: This value MUST match `AppConstants.imageAlbumName` in the Dart code.
        const val PICTURES_SUB_DIR = "ImageOCR"

        @Volatile
        private var eventSink: EventChannel.EventSink? = null

        fun getEventSink(): EventChannel.EventSink? {
            return eventSink
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    
    // 缓存截屏结果，防止在应用不在前台时丢失
    private var pendingScreenshotResult: Map<String, Any>? = null

    private val screenshotReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val tag = "MainActivity"
            if (intent?.action == ScreenshotService.ACTION_SCREENSHOT_RESULT) {
                val filePath = intent.getStringExtra(ScreenshotService.EXTRA_FILE_PATH)
                val errorMessage = intent.getStringExtra(ScreenshotService.EXTRA_ERROR_MESSAGE)

                val result = if (filePath != null) {
                    mapOf("type" to "success", "path" to filePath)
                } else {
                    mapOf("type" to "error", "error" to (errorMessage ?: "未知错误"))
                }
                
                // 尝试立即发送结果
                if (eventSink != null) {
                    try {
                        if (filePath != null) {
                            eventSink?.success(result)
                        } else {
                            eventSink?.error("CAPTURE_FAILED", errorMessage, null)
                        }
                        //Log.d(tag, "Screenshot result sent immediately")
                    } catch (e: Exception) {
                        //Log.w(tag, "Failed to send result immediately, caching: ${e.message}")
                        pendingScreenshotResult = result
                    }
                } else {
                    // EventSink不可用，缓存结果等待恢复
                    pendingScreenshotResult = result
                    //Log.d(tag, "EventSink not available, result cached")
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Event Channel for receiving screenshot results
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    MainActivity.eventSink = events
                    
                    // 如果有待处理的结果，立即发送
                    pendingScreenshotResult?.let { result ->
                        handler.post {
                            try {
                                if (result["type"] == "success") {
                                    eventSink?.success(result)
                                } else {
                                    eventSink?.error("CAPTURE_FAILED", result["error"] as? String, null)
                                }
                                pendingScreenshotResult = null
                                //Log.d("MainActivity", "Pending screenshot result sent")
                            } catch (e: Exception) {
                                Log.e("MainActivity", "Failed to send pending result: ${e.message}")
                            }
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    MainActivity.eventSink = null
                }
            }
        )

        // Method Channel for sending commands
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkAccessibilityPermission" -> {
                    result.success(isAccessibilityServiceEnabled())
                }
                "requestAccessibilityPermission" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    startActivity(intent)
                    result.success(null)
                }
                "takeScreenshot" -> {
                    // 尝试多种方式触发截屏
                    val success = triggerScreenshotMultipleWays()
                    result.success(success)
                }
                "getPicturesDirectory" -> {
                    try {
                        // --- ABSOLUTE FINAL FIX: Return the FULL path including the subdirectory ---
                        val picturesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
                        val appDir = java.io.File(picturesDir, PICTURES_SUB_DIR)
                        result.success(appDir.absolutePath)
                    } catch (e: Exception) {
                        result.error("UNAVAILABLE", "Could not get public pictures directory.", e.toString())
                    }
                }
                else -> result.notImplemented()
            }
        }
        
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        checkAndRequestNotificationPermission()
    }

    override fun onResume() {
        super.onResume()
        val filter = IntentFilter(ScreenshotService.ACTION_SCREENSHOT_RESULT)
        LocalBroadcastManager.getInstance(this).registerReceiver(screenshotReceiver, filter)

        // [核心修复] 每次 Activity 可见时，都尝试与服务重新建立通信链接
        // 如果服务已在运行，这只会调用 onStartCommand，不会创建新实例。
        // 这确保了即使应用进程被杀死后重启，也能恢复与服务的通信。
        val reconnectIntent = Intent(this, ScreenshotService::class.java).apply {
            action = ScreenshotService.ACTION_RECONNECT
        }
        try {
            startService(reconnectIntent)
            //Log.d("MainActivity", "Attempted to reconnect with ScreenshotService.")
        } catch (e: Exception) {
            // 在某些极端情况下（如后台限制），startService 可能会失败
            //Log.e("MainActivity", "Failed to start service for reconnection.", e)
        }
        
        //Log.d("MainActivity", "Activity resumed, screenshot receiver registered")
    }

    override fun onPause() {
        super.onPause()
        try {
            LocalBroadcastManager.getInstance(this).unregisterReceiver(screenshotReceiver)
        } catch (e: Exception) {
            //Log.w("MainActivity", "Failed to unregister receiver: ${e.message}")
        }
        //Log.d("MainActivity", "Activity paused")
    }
    
    /**
     * 使用多种方式尝试触发截屏，提高成功率
     */
    private fun triggerScreenshotMultipleWays(): Boolean {
        var success = false
        
        // 方式1: 通过事件处理器
        try {
            ScreenshotService.eventHandler?.invoke("takeScreenshot")
            success = true
            //Log.d("MainActivity", "Screenshot triggered via event handler")
        } catch (e: Exception) {
            //Log.w("MainActivity", "Event handler failed: ${e.message}")
        }
        
        // 方式2: 直接调用服务实例
        if (!success) {
            try {
                ScreenshotService.serviceInstance?.triggerScreenshot()
                success = true
                //Log.d("MainActivity", "Screenshot triggered via service instance")
            } catch (e: Exception) {
                //Log.w("MainActivity", "Service instance call failed: ${e.message}")
            }
        }
        
        return success
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        // 恢复原始的、最可靠的检查方式：只检查系统设置。
        // 通信的重新建立由 onResume 中的 startService 主动触发。
        val service = packageName + "/" + ScreenshotService::class.java.canonicalName
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        )
        return enabledServices?.contains(service) == true
    }

    private fun checkAndRequestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_REQUEST_CODE)
            }
        }
    }
    
}

