package com.lxmoon.image_ocr

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // 确保接收到的是开机完成的广播
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.d("BootCompletedReceiver", "Boot completed, attempting to start ScreenshotService.")
            try {
                val serviceIntent = Intent(context, ScreenshotService::class.java)
                // 根据安卓版本的不同，使用不同的方式启动服务
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            } catch (e: Exception) {
                Log.e("BootCompletedReceiver", "Failed to start ScreenshotService on boot", e)
            }
        }
    }
}