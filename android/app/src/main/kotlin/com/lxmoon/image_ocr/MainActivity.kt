package com.lxmoon.image_ocr

import android.content.*
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import android.Manifest
import android.content.pm.PackageManager
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import java.io.BufferedReader
import java.io.DataOutputStream
import java.io.InputStreamReader

class MainActivity: FlutterFragmentActivity() {
    private val NOTIFICATION_PERMISSION_REQUEST_CODE = 101

    companion object {
        const val PICTURES_SUB_DIR = "ImageOCR"
        private var instance: MainActivity? = null
        
        fun getInstance(): MainActivity? {
            return instance
        }
    }
    
    // Do not override provideFlutterEngine. We will get it from the Application class.

    override fun onCreate(savedInstanceState: Bundle?) {
        // Ensure the engine is initialized before the activity is created.
        (application as MainApplication).getFlutterEngine(this)
        super.onCreate(savedInstanceState)
        instance = this
        checkAndRequestNotificationPermission()
    }

    // This is required to hook into the cached engine.
    override fun getCachedEngineId(): String? {
        return MainApplication.FLUTTER_ENGINE_ID
    }
    
    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }

    override fun onResume() {
        super.onResume()
        // The broadcast receiver is a fallback and can remain, but primary communication is the EventChannel.
        val filter = IntentFilter(ScreenshotService.ACTION_SCREENSHOT_RESULT)
        LocalBroadcastManager.getInstance(this).registerReceiver(screenshotReceiver, filter)

        val reconnectIntent = Intent(this, ScreenshotService::class.java).apply {
            action = ScreenshotService.ACTION_RECONNECT
        }
        try {
            startService(reconnectIntent)
        } catch (e: Exception) {
            // Log error
        }
    }

    override fun onPause() {
        super.onPause()
        try {
            LocalBroadcastManager.getInstance(this).unregisterReceiver(screenshotReceiver)
        } catch (e: Exception) {
            // Log error
        }
    }

    private val screenshotReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            // This is now a fallback. The main logic is handled by the persistent EventChannel.
        }
    }
    
    fun triggerScreenshotMultipleWays(): Boolean {
        var success = false
        try {
            ScreenshotService.eventHandler?.invoke("takeScreenshot")
            success = true
        } catch (e: Exception) {
            // Log error
        }
        if (!success) {
            try {
                ScreenshotService.serviceInstance?.triggerScreenshot()
                success = true
            } catch (e: Exception) {
                // Log error
            }
        }
        return success
    }

    fun isAccessibilityServiceEnabled(): Boolean {
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

    fun isRootAvailable(): Boolean {
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

    fun requestRootPermission(result: io.flutter.plugin.common.MethodChannel.Result) {
        Thread {
            var process: Process? = null
            try {
                process = Runtime.getRuntime().exec("su")
                val os = DataOutputStream(process.outputStream)
                os.writeBytes("exit\n")
                os.flush()
                val exitCode = process.waitFor()
                runOnUiThread {
                    result.success(exitCode == 0)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.success(false)
                }
            } finally {
                process?.destroy()
            }
        }.start()
    }
}
