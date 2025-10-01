
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
    
    // [最终修复] 移除所有缓存逻辑，Activity 只负责监听和转发，不持有状态。
    private val screenshotReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ScreenshotService.ACTION_SCREENSHOT_RESULT) {
                val filePath = intent.getStringExtra(ScreenshotService.EXTRA_FILE_PATH)
                val errorMessage = intent.getStringExtra(ScreenshotService.EXTRA_ERROR_MESSAGE)

                // [最终修复] 收到广播后，直接通过当前有效的 EventSink 发送给 Flutter。
                // 如果 eventSink 为 null (Flutter UI 不可见)，则消息被安全地忽略。
                // 这种方式保证了不会��一个无效的 Sink 发送数据，从而避免闪退。
                eventSink?.let { sink ->
                    if (filePath != null) {
                        val result = mapOf("type" to "success", "path" to filePath)
                        sink.success(result)
                        //Log.d("MainActivity", "Broadcast received and forwarded to Flutter: SUCCESS")
                    } else {
                        sink.error("CAPTURE_FAILED", errorMessage ?: "未知错误", null)
                        //Log.d("MainActivity", "Broadcast received and forwarded to Flutter: ERROR")
                    }
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
                    // [最终修复] onListen 只负责设置 sink，移除所有待处理结果的逻辑。
                    MainActivity.eventSink = events
                    //Log.d("MainActivity", "EventChannel listener attached.")
                }

                override fun onCancel(arguments: Any?) {
                    MainActivity.eventSink = null
                    //Log.d("MainActivity", "EventChannel listener detached.")
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
                    // [核心加固] 改为使用最可靠的 Intent 方式
                    val success = triggerScreenshotViaIntent()
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
                // [NEW] Add Root permission check
                "checkRootPermission" -> {
                    result.success(isRootAvailable())
                }
                // [NEW] Add Root permission request
                "requestRootPermission" -> {
                    requestRootPermission(result)
                }
                else -> result.notImplemented()
            }
        }
        
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        checkAndRequestNotificationPermission()
        // [核心加固] 在 Activity 创建时就确保服务正在运行
        startScreenshotService()
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
     * [核心加固] 使用 Intent Action 触发截屏，这是最可靠的方式
     */
    private fun triggerScreenshotViaIntent(): Boolean {
        return try {
            val intent = Intent(this, ScreenshotService::class.java).apply {
                action = ScreenshotService.ACTION_TRIGGER_SCREENSHOT
            }
            // 始终使用 startService 来发送命令，系统会处理服务是否已在运行
            startService(intent)
            //Log.d("MainActivity", "Screenshot command sent via Intent")
            true
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to send screenshot command via Intent", e)
            false
        }
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

    /**
     * [NEW] Checks if root access is available.
     */
    private fun isRootAvailable(): Boolean {
        var process: Process? = null
        return try {
            process = Runtime.getRuntime().exec(arrayOf("su", "-c", "id"))
            process.waitFor() == 0
        } catch (e: Exception) {
            false
        } finally {
            process?.destroy()
        }
    }

    /**
     * [NEW] Tries to execute a simple command with su to trigger the root permission prompt.
     */
    private fun requestRootPermission(result: MethodChannel.Result) {
        Thread {
            var process: Process? = null
            try {
                process = Runtime.getRuntime().exec(arrayOf("su", "-c", "echo 'root permission requested'"))
                val exitCode = process.waitFor()
                // Post the result back to the main thread
                handler.post {
                    result.success(exitCode == 0)
                }
            } catch (e: Exception) {
                handler.post {
                    result.success(false)
                }
            } finally {
                process?.destroy()
            }
        }.start()
    }

    /**
     * [核心加固] 启动无障碍服务的统一方法
     */
    private fun startScreenshotService() {
        try {
            val serviceIntent = Intent(this, ScreenshotService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            //Log.d("MainActivity", "Ensured ScreenshotService is started.")
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to start ScreenshotService.", e)
        }
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

