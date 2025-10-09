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
import java.io.BufferedReader
import java.io.DataOutputStream
import java.io.InputStreamReader

class ScreenshotService : AccessibilityService() {

    companion object {
        const val ACTION_SCREENSHOT_RESULT = "com.lxmoon.image_ocr.SCREENSHOT_RESULT"
        const val ACTION_RECONNECT = "com.lxmoon.image_ocr.RECONNECT"
        const val EXTRA_FILE_PATH = "extra_file_path"
        const val EXTRA_ERROR_MESSAGE = "extra_error_message"
        
        private const val NOTIFICATION_CHANNEL_ID = "screenshot_service_channel"
        private const val NOTIFICATION_ID = 1001
        private const val RESULT_NOTIFICATION_ID = 1002

        var eventHandler: ((String) -> Unit)? = null
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

        // Ensure the Flutter engine is ready before the service starts its work.
        (application as MainApplication).getFlutterEngine(this)
        
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        sharedPreferences = getSharedPreferences("screenshot_service_prefs", Context.MODE_PRIVATE)
        createNotificationChannel()
        startAsForegroundService()
        reconnect()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_RECONNECT) {
            reconnect()
        }
        return START_STICKY
    }

    private fun reconnect() {
        serviceInstance = this
        eventHandler = { command ->
            if (command == "takeScreenshot") {
                handleScreenshotRequest()
            }
        }
    }

    private fun handleScreenshotRequest() {
        if (!isProcessingScreenshot.compareAndSet(false, true)) {
            return
        }
        
        handler.postDelayed({
            if (isRootAvailable()) {
                captureScreenshotWithRoot()
            } else {
                captureScreenshot()
            }
        }, 200)
    }
    
    private fun startAsForegroundService() {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("ImageOCR 服务正在运行")
            .setContentText("点击可返回应用")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()

        startForeground(NOTIFICATION_ID, notification)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "截屏服务",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "处理截屏请求和结果通知"
                setShowBadge(true)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }
    
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
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(Notification.DEFAULT_ALL)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setColor(if (isError) 0xFFE53E3E.toInt() else 0xFF38A169.toInt())
            .build()
            
        notificationManager.notify(RESULT_NOTIFICATION_ID, notification)
    }

    private fun sendResult(filePath: String?, errorMessage: String?) {
        try {
            val eventSink = MainApplication.getEventSink()
            if (eventSink != null) {
                uiHandler.post {
                    if (filePath != null) {
                        eventSink.success(mapOf("type" to "success", "path" to filePath))
                    } else {
                        eventSink.error("screenshot_failed", errorMessage, null)
                    }
                }
            } else {
                val intent = Intent(ACTION_SCREENSHOT_RESULT).apply {
                    putExtra(EXTRA_FILE_PATH, filePath)
                    putExtra(EXTRA_ERROR_MESSAGE, errorMessage)
                }
                LocalBroadcastManager.getInstance(this).sendBroadcast(intent)
            }

            if (errorMessage != null) {
                showResultNotification("截屏失败", errorMessage, true)
            }
            
        } finally {
            isProcessingScreenshot.set(false)
        }
    }
    

    private fun captureScreenshot() {
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
            val appDir = File(picturesDir, MainActivity.PICTURES_SUB_DIR)

            if (!appDir.exists() && !appDir.mkdirs()) {
                Log.e(tag, "FATAL: Could not create required directory ${appDir.absolutePath}. Aborting screenshot save.")
                return null
            }

            val fileName = "screenshot_${System.currentTimeMillis()}.png"
            val file = File(appDir, fileName)

            FileOutputStream(file).use { out ->
                val softwareBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, false)
                softwareBitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            }
            
            notifyMediaScanner(file.absolutePath)
            
            return file.absolutePath
        } catch (e: Exception) {
            Log.e(tag, "Failed to save screenshot", e)
            return null
        }
    }
    
    private fun notifyMediaScanner(filePath: String) {
        try {
            MediaScannerConnection.scanFile(
                this,
                arrayOf(filePath),
                arrayOf("image/png")
            ) { path, uri ->
                // Log scan completion
            }
            
            val mediaScanIntent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
            val contentUri = Uri.fromFile(File(filePath))
            mediaScanIntent.data = contentUri
            sendBroadcast(mediaScanIntent)
            
        } catch (e: Exception) {
            Log.e("ScreenshotService", "Failed to notify media scanner", e)
        }
    }


    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Not used
    }

    override fun onInterrupt() {
        // Not used
    }

    override fun onUnbind(intent: Intent?): Boolean {
        eventHandler = null
        serviceInstance = null
        stopForeground(true)
        return super.onUnbind(intent)
    }
    
    fun triggerScreenshot() {
        captureScreenshot()
    }

    override fun onDestroy() {
        super.onDestroy()
        stopForeground(true)
        eventHandler = null
        serviceInstance = null
    }

    private fun isRootAvailable(): Boolean {
        var process: Process? = null
        return try {
            process = Runtime.getRuntime().exec(arrayOf("su", "-c", "id"))
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val output = reader.readLine()
            process.waitFor()
            output != null && output.contains("uid=0")
        } catch (e: Exception) {
            false
        } finally {
            process?.destroy()
        }
    }

    private fun captureScreenshotWithRoot() {
        executor.execute {
            var process: Process? = null
            var filePath: String? = null
            var error: String? = null

            try {
                val picturesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
                val appDir = File(picturesDir, MainActivity.PICTURES_SUB_DIR)
                if (!appDir.exists() && !appDir.mkdirs()) {
                    throw Exception("Could not create directory: ${appDir.absolutePath}")
                }

                val fileName = "screenshot_${System.currentTimeMillis()}.png"
                val file = File(appDir, fileName)
                filePath = file.absolutePath
                val command = "/system/bin/screencap -p \"$filePath\"\n"

                process = Runtime.getRuntime().exec("su")
                val os = DataOutputStream(process.outputStream)
                os.writeBytes(command)
                os.writeBytes("exit\n")
                os.flush()

                val exitCode = process.waitFor()

                if (exitCode == 0) {
                    notifyMediaScanner(filePath)
                } else {
                    error = "Root screenshot command failed with exit code $exitCode"
                    filePath = null
                }
            } catch (e: Exception) {
                error = "Root screenshot failed: ${e.message}"
                filePath = null
            } finally {
                process?.destroy()
                handler.post {
                    sendResult(filePath, error)
                }
            }
        }
    }
}
