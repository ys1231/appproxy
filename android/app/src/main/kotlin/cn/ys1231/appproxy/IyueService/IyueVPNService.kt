package cn.ys1231.appproxy.IyueService

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.VpnService
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import cn.ys1231.appproxy.MainActivity
import cn.ys1231.appproxy.R
import com.google.gson.Gson
import engine.Engine
import engine.Key

class IyueVPNService : VpnService() {

    private val TAG = "iyue->${this.javaClass.simpleName} "

    private var vpnInterface: ParcelFileDescriptor? = null
    private var isRunning = false
    private val binder = VPNServiceBinder()

    inner class VPNServiceBinder : Binder() {
        fun getService(): IyueVPNService = this@IyueVPNService
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate: VPNServiceBinder")

        // 创建通知渠道（Android Oreo 及以上版本）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "iyue_vpn_channel"
            val channelName = "Iyue VPN"
            val importance = NotificationManager.IMPORTANCE_DEFAULT
            val channel = NotificationChannel(channelId, channelName, importance).apply {
                description = "Iyue VPN Service Channel"
                lightColor = Color.BLUE
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            }
            val notificationManager: NotificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder {
        Log.d(TAG, "onBind: VPNServiceBinder")
        return binder
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: ${intent.toString()}")
        return START_NOT_STICKY
    }

    fun startVpnService(data: Map<String, Any>) {
        Log.d(TAG, "startVpnService: $data")

        // {proxyPort=8080, proxyPass=, proxyName=test, proxyType=http, proxyUser=, appProxyPackageList=[com.android.chrome], proxyHost=192.168.0.1}
        val proxyName = data["proxyName"].toString()
        val proxyHost = data["proxyHost"].toString()
        val proxyPort = (data["proxyPort"] as String).toInt()
        val proxyType = data["proxyType"].toString()
        val proxyUser = data["proxyUser"].toString()
        val proxyPass = data["proxyPass"].toString()

        // 创建并显示前台服务通知
        val notificationIntent = Intent(this, MainActivity::class.java)
            .putExtra("iyue_vpn_channel", true)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, "iyue_vpn_channel")
            .setContentTitle("${applicationInfo.loadLabel(packageManager)}: $proxyName")
            .setContentText("$proxyType: $proxyHost:$proxyPort")
            .setSmallIcon(R.mipmap.vpn, 3)
            .setContentIntent(pendingIntent)
            .build()

        startForeground(1, notification)

        val builder = Builder()
            .addAddress("10.0.0.2", 24)
            .addRoute("0.0.0.0", 0)
            .setMtu(1500)
//            .addDnsServer("192.168.10.1")
            .setSession(packageName)
        val allowedApps = jsonToList(data["appProxyPackageList"].toString())
//        builder.addDisallowedApplication(packageName)
        for (appPackageName in allowedApps) {
            try {
                Log.d(TAG, "addAllowedApplication: $appPackageName")
                builder.addAllowedApplication(appPackageName)
            } catch (e: Exception) {
                Log.e(TAG, "addAllowedApplication: ${e.message}")
            }
        }

        try {
            vpnInterface = builder.establish()
            if (vpnInterface == null) {
                Log.e(TAG, "vpnInterface: create establish error ")
                return
            }

            val key = Key()
            key.mark = 0
            key.mtu = 1500
            key.device = "fd://" + vpnInterface!!.fd // <--- here
            key.setInterface("")
            key.logLevel = "debug"
            key.proxy =
                "${proxyType}://${proxyUser}:${proxyPass}@${proxyHost}:${proxyPort}" // <--- and here
            key.restAPI = ""
            key.tcpSendBufferSize = ""
            key.tcpReceiveBufferSize = ""
            key.tcpModerateReceiveBuffer = false
            Engine.insert(key)
            Engine.start()
            Log.d(TAG, "startEngine: $key")
            isRunning = true
//            stopSignal.await()
        } catch (e: Exception) {
            Log.e(TAG, "startEngine: error ${e.message}")
        }
    }

    fun stopVpnService() {
        Log.d(TAG, "stopVpnService: vpnInterface $vpnInterface")
        try {
            if (vpnInterface != null) {
                // 不能主动停止,会触发重复关闭fd 导致app崩溃
//                 Engine.stop()
                vpnInterface?.close()
                vpnInterface = null
                isRunning = false
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                }
            }
            Log.d(TAG, "stopEngine: success!")
        } catch (e: Exception) {
            Log.e(TAG, "stopVpnService: ${e.message}")
        }
    }

    fun isRunning(): Boolean {
        return isRunning
    }

    private fun jsonToList(jsonString: String): List<String> {
        val gson = Gson()
        return gson.fromJson(jsonString, Array<String>::class.java).toList()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        Log.d(TAG, "onUnbind: IyueVPNService ")
        stopVpnService()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "onDestroy: IyueVPNService ")
    }

}