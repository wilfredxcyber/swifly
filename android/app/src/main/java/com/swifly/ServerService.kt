package com.swifly

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Binder
import android.os.IBinder
import android.util.Log

class ServerService : Service() {

    private val TAG = "ServerService"
    private var server: SwiflyServer? = null
    
    private val binder = LocalBinder()

    inner class LocalBinder : Binder() {
        fun getService(): ServerService = this@ServerService
    }

    override fun onBind(intent: Intent?): IBinder {
        return binder
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_START) {
            val fileUriStr = intent.getStringExtra(EXTRA_FILE_URI)
            val token = intent.getStringExtra(EXTRA_TOKEN)
            val pairingCode = intent.getStringExtra(EXTRA_PAIRING_CODE) ?: ""
            val port = intent.getIntExtra(EXTRA_PORT, 7845)
            
            if (fileUriStr != null && token != null) {
                startServer(Uri.parse(fileUriStr), pairingCode, token, port)
                startForeground(NOTIFICATION_ID, createNotification())
            } else {
                stopSelf()
            }
        } else if (action == ACTION_STOP) {
            stopServer()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
        
        return START_NOT_STICKY
    }

    private fun startServer(fileUri: Uri, pairingCode: String, token: String, port: Int) {
        if (server?.isAlive == true) {
            server?.stop()
        }
        
        server = SwiflyServer(this, port, pairingCode, token, fileUri)
        try {
            server?.start()
            Log.i(TAG, "Server started on port $port with token $token")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start server", e)
            stopSelf()
        }
    }

    private fun stopServer() {
        server?.stop()
        server = null
        Log.i(TAG, "Server stopped")
    }

    override fun onDestroy() {
        stopServer()
        super.onDestroy()
    }

    private fun createNotification(): Notification {
        val channelId = "swifly_server_channel"
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Swifly File Server",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }

        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("Swifly is serving")
            .setContentText("A file is available for transfer")
            .setSmallIcon(android.R.drawable.stat_sys_upload) // Fallback icon
            .setContentIntent(pendingIntent)
            .build()
    }

    companion object {
        const val ACTION_START = "com.swifly.action.START"
        const val ACTION_STOP = "com.swifly.action.STOP"
        const val EXTRA_FILE_URI = "extra_file_uri"
        const val EXTRA_TOKEN = "extra_token"
        const val EXTRA_PAIRING_CODE = "extra_pairing_code"
        const val EXTRA_PORT = "extra_port"
        const val NOTIFICATION_ID = 1001
    }
}
