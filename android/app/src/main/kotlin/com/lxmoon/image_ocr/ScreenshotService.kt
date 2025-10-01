
package com.lxmoon.image_ocr

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import android.os.Looper
import android.util.Log
import android.view.Display
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.os.Environment
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import android.app.NotificationManager
import android.app.NotificationChannel
import android.app.Notification
import android.content.Context
import androidx.core.app.NotificationCompat
import android.app.PendingIntent
import android.content.ComponentName
import android.content.SharedPreferences
import java.util.concurrent.atomic.AtomicBoolean
import android.media.MediaScannerConnection
import android.provider.MediaStore
import android.content.ContentValues
import android.net.Uri

class ScreenshotService : AccessibilityService() {

    companion object {
        const val ACTION_SCREENSHOT_RESULT = "com.lxmoon.image_ocr.SCREENSHOT_RESULT"
        const val ACTION_RECONNECT = "com.lxmoon.image_ocr.RECONNECT"
        const val ACTION_TRIGGER_SCREENSHOT = "com.lxmoon.image_ocr.TRIGGER_SCREENSHOT" // 新增 Action
        const val EXTRA_FILE_PATH = "extra_file_path"
        const val EXTRA_ERROR_MESSAGE = "extra_error_message"
        
        // 通知相关常量
        private const val NOTIFICATION_CHANNEL_ID = "screenshot_service_channel"
        private const val FOREGROUND_NOTIFICATION_ID = 1 // 前台服务通知ID
        private const val RESULT_NOTIFICATION_ID = 1002

        // A simple event bus to receive commands from the MainActivity/Flutter.
        var eventHandler: ((String) -> Unit)? = null
        
        // 服务实例引用，用于外部调用
        var serviceInstance: ScreenshotService? = null
    }

    private val executor: Executor = Executors.newSingleThreadExecutor()
    private val handler: android.os.Handler = android.os.Handler(Looper.getMainLooper())
    private val uiHandler: android.os.Handler = android.os.Handler(Looper.getMainLooper())
    private lateinit var notificationManager: NotificationManager
    private lateinit var sharedPreferences: SharedPreferences
    private val isProcessingScreenshot = AtomicBoolean(false)

    override fun onServiceConnected() {
        super.onServiceConnected()
        
        // 初始化通知管理器和SharedPreferences
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        sharedPreferences = getSharedPreferences("screenshot_service_prefs", Context.MODE_PRIVATE)
        createNotificationChannel()
        
        // 将服务提升到前台
        val notification = createForegroundNotification()
        startForeground(FOREGROUND_NOTIFICATION_ID, notification)
        
        // 重新建立连接的逻辑
        reconnect()
        
        //Log.d("ScreenshotService", "Service connected and running in foreground")
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            // 当 MainActivity 请求重连时
            ACTION_RECONNECT -> {
                reconnect()
                //Log.d("ScreenshotService", "Reconnected via onStartCommand")
            }
            // 当接收到截图指令时
            ACTION_TRIGGER_SCREENSHOT -> {
                handleScreenshotRequest()
                //Log.d("ScreenshotService", "Screenshot triggered via Intent Action")
            }
        }
        // 使用 START_STICKY 确保服务在被杀死后能自动重启
        return START_STICKY
    }

    /**
     * 封装的重连接逻辑，用于建立或恢复与 MainActivity 的通信
     */
    private fun reconnect() {
        serviceInstance = this
        eventHandler = { command ->
            if (command == "takeScreenshot") {
                handleScreenshotRequest()
            }
        }
    }

    /**
     * 处理截屏请求（新的统一入口）
     */
    private fun handleScreenshotRequest() {
        // 防止重复处理
        if (!isProcessingScreenshot.compareAndSet(false, true)) {
            //Log.d("ScreenshotService", "Screenshot already in progress, skipping")
            return
        }
        
        //Log.d("ScreenshotService", "Starting screenshot process after a delay")
        
        // 增加一个延迟，等待悬浮窗UI完成动画或隐藏
        handler.postDelayed({
            // [NEW] 优先使用 Root 截图
            if (isRootAvailable()) {
                captureScreenshotWithRoot()
            } else {
                captureScreenshotWithAccessibility()
            }
        }, 200) // 200毫秒延迟，优化响应速度
    }
    
    /**
     * 创建通知渠道（Android 8.0+需要）
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "截屏服务",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "处理截屏请求和结果通知"
                setShowBadge(true) // 允许显示角标
            }
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    /**
     * 显示截屏结果通知
     */
    private fun showResultNotification(title: String, message: String, isError: Boolean = false) {
        val intent = Intent().apply {
            component = ComponentName(packageName, "com.lxmoon.image_ocr.MainActivity")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentTitle(title)
            .setContentText(message)
            .setPriority(NotificationCompat.PRIORITY_HIGH) // 提升优先级以弹出通知
            .setDefaults(Notification.DEFAULT_ALL) // 使用默认声音和振动
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setColor(if (isError) 0xFFE53E3E.toInt() else 0xFF38A169.toInt())
            .build()
            
        notificationManager.notify(RESULT_NOTIFICATION_ID, notification)
    }

    private fun sendResult(filePath: String?, errorMessage: String?) {
        try {
            // [最终修复] 移除对 EventSink 的所有直接引用，只使用 LocalBroadcastManager。
            // 这是保证 Service 和 Activity 彻底解耦的关键。
            //Log.d("ScreenshotService", "Sending result via LocalBroadcast only.")
            val intent = Intent(ACTION_SCREENSHOT_RESULT).apply {
                putExtra(EXTRA_FILE_PATH, filePath)
                putExtra(EXTRA_ERROR_MESSAGE, errorMessage)
            }
            LocalBroadcastManager.getInstance(this).sendBroadcast(intent)

            // 错误通知仍然可以显示，因为它不依赖于 Activity 的状态。
            if (filePath == null) {
                showResultNotification("截屏失败", errorMessage ?: "未知错误", true)
            }
            
            //Log.d("ScreenshotService", "Screenshot result broadcasted: path=$filePath, error=$errorMessage")
        } finally {
            // 重置处理状态
            isProcessingScreenshot.set(false)
        }
    }
    

    private fun captureScreenshotWithAccessibility() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            sendResult(null, "Screenshot API is only available on Android P (API 28) and above.")
            return
        }

        val windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        val display = windowManager.defaultDisplay

        val displayId = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display.displayId
        } else {
            Display.DEFAULT_DISPLAY
        }

        takeScreenshot(
            displayId,
            executor,
            object : TakeScreenshotCallback {
                override fun onSuccess(screenshot: ScreenshotResult) {
                    handler.post {
                        try {
                            val bitmap = Bitmap.wrapHardwareBuffer(screenshot.hardwareBuffer, screenshot.colorSpace)
                            if (bitmap != null) {
                                val filePath = saveBitmapToFile(bitmap)
                                if (filePath != null) {
                                    sendResult(filePath, null)
                                } else {
                                    sendResult(null, "Failed to save screenshot.")
                                }
                            } else {
                                sendResult(null, "Failed to create bitmap from hardware buffer.")
                            }
                        } catch (e: Exception) {
                            sendResult(null, "Error processing screenshot: ${e.message}")
                        } finally {
                            screenshot.hardwareBuffer.close()
                        }
                    }
                }

                override fun onFailure(errorCode: Int) {
                    handler.post {
                        sendResult(null, "Screenshot capture failed with error code: $errorCode")
                    }
                }
            }
        )
    }

    private fun saveBitmapToFile(bitmap: Bitmap): String? {
        val tag = "ScreenshotService"
        try {
            val picturesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
            // --- FINAL FIX: Use the shared constant for the subdirectory name ---
            val appDir = File(picturesDir, MainActivity.PICTURES_SUB_DIR)

            // --- STRICT POLICY ENFORCEMENT ---
            // Attempt to create the directory if it doesn't exist.
            // If mkdirs() fails, it means we cannot save to the required location.
            // In this case, we MUST fail the entire operation as per the user's strict requirement.
            if (!appDir.exists() && !appDir.mkdirs()) {
                Log.e(tag, "FATAL: Could not create required directory ${appDir.absolutePath}. Aborting screenshot save.")
                return null // Explicitly fail the save operation.
            }

            val fileName = "screenshot_${System.currentTimeMillis()}.png"
            val file = File(appDir, fileName)

            FileOutputStream(file).use { out ->
                val softwareBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, false)
                softwareBitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            }
            
            notifyMediaScanner(file.absolutePath)
            
            //Log.d(tag, "Screenshot saved and registered: ${file.absolutePath}")
            return file.absolutePath
        } catch (e: Exception) {
            Log.e(tag, "Failed to save screenshot", e)
            return null
        }
    }
    
    /**
     * 通知系统媒体库扫描新文件
     */
    private fun notifyMediaScanner(filePath: String) {
        try {
            // 方法1: 使用MediaScannerConnection扫描文件
            MediaScannerConnection.scanFile(
                this,
                arrayOf(filePath),
                arrayOf("image/png")
            ) { path, uri ->
                //Log.d("ScreenshotService", "Media scan completed: $path -> $uri")
            }
            
            // 方法2: 发送广播通知系统扫描（兼容旧版本）
            val mediaScanIntent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
            val contentUri = Uri.fromFile(File(filePath))
            mediaScanIntent.data = contentUri
            sendBroadcast(mediaScanIntent)
            
            //Log.d("ScreenshotService", "Media scanner notified for: $filePath")
        } catch (e: Exception) {
            Log.e("ScreenshotService", "Failed to notify media scanner", e)
        }
    }


    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // We don't need to react to events for this use case.
    }

    override fun onInterrupt() {
        // Service interrupted.
    }

    override fun onUnbind(intent: Intent?): Boolean {
        eventHandler = null
        serviceInstance = null
        stopForeground(true) // 服务解绑时停止前台状态
        //Log.d("ScreenshotService", "Service unbound and foreground state stopped")
        return super.onUnbind(intent)
    }
    
    /**
     * 公共方法：触发截屏（供外部调用）
     */
    fun triggerScreenshot() {
        //Log.d("ScreenshotService", "Triggering screenshot from external call")
        handleScreenshotRequest()
    }

    /**
     * 创建前台服务所需的通知
     */
    private fun createForegroundNotification(): Notification {
        val channelId = NOTIFICATION_CHANNEL_ID
        val channelName = "无障碍服务"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                channelName,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "确保无障碍服务持续运行"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("服务运行中")
            .setContentText("无障碍截图服务正在运行，以提供实时处理功能。")
            .setSmallIcon(android.R.drawable.ic_dialog_info) // 使用一个系统图标
            .setContentIntent(pendingIntent)
            .setOngoing(true) // 使通知不可清除
            .build()
    }

    /**
     * [NEW] Checks if root access is available.
     */
    private fun isRootAvailable(): Boolean {
        var process: Process? = null
        return try {
            // "-c" and "id" are separated intentionally.
            process = Runtime.getRuntime().exec(arrayOf("su", "-c", "id"))
            process.waitFor() == 0
        } catch (e: Exception) {
            false
        } finally {
            process?.destroy()
        }
    }

    /**
     * [NEW] Captures a screenshot using root command 'screencap'.
     */
    private fun captureScreenshotWithRoot() {
        executor.execute {
            var process: Process? = null
            val picturesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
            val appDir = File(picturesDir, MainActivity.PICTURES_SUB_DIR)
            if (!appDir.exists() && !appDir.mkdirs()) {
                sendResult(null, "Failed to create directory for screenshot.")
                return@execute
            }
            val fileName = "screenshot_${System.currentTimeMillis()}.png"
            val file = File(appDir, fileName)
            val filePath = file.absolutePath

            try {
                // Execute the screencap command
                val command = arrayOf("su", "-c", "/system/bin/screencap -p $filePath")
                process = Runtime.getRuntime().exec(command)
                
                val exitCode = process.waitFor()
                
                if (exitCode == 0) {
                    // Notify media scanner to make the image visible in the gallery
                    notifyMediaScanner(filePath)
                    sendResult(filePath, null)
                } else {
                    sendResult(null, "Root screencap command failed with exit code: $exitCode")
                }
            } catch (e: Exception) {
                sendResult(null, "Error capturing screenshot with root: ${e.message}")
            } finally {
                process?.destroy()
            }
        }
    }
}
