package cn.ys1231.appproxy.IyueService

import android.R.id.message
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import cn.ys1231.appproxy.MainActivity
import cn.ys1231.appproxy.R
import com.google.gson.Gson
import engine.Engine
import engine.Key
import java.util.concurrent.CountDownLatch


class IyueVPNService : VpnService() {
    private val TAG = "iyue->${this.javaClass.simpleName}"
    private var vpnInterface: ParcelFileDescriptor? = null
    private var vpnThread: Thread? = null
    private var proxyData: Map<String, Any>? = null

    // 移除死循环，并添加一个停止信号处理逻辑
    private val stopSignal = CountDownLatch(1)

    companion object {
        const val ACTION_STOP_SERVICE = "cn.ys1231.appproxy.STOP_VPN_SERVICE"
    }

    override fun onCreate() {
        super.onCreate()
        // 初始化操作
        Log.d(TAG, "onCreate: IyueVPNService ")
        // 创建通知渠道（Android Oreo 及以上版本）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "iyue_vpn_channel"
            val channelName = "Iyue VPN"
            val importance = NotificationManager.IMPORTANCE_LOW
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

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP_SERVICE) {
            stopVpn()
//            stopSelf()
            return START_NOT_STICKY
        }
        proxyData = intent?.extras?.getSerializable("data") as Map<String, Any>
        Log.d(TAG, "onStartCommand: $proxyData")
        vpnThread = object : Thread() {
            override fun run() {
                try {
                    startVpn(proxyData!!)
                } catch (e: Exception) {
                    Log.e(TAG, "vpnThread: fail", e)
                }
            }
        }
        vpnThread?.start()
        // 创建并显示前台服务通知
        val notificationIntent = Intent(this, MainActivity::class.java)
            .putExtra("iyue_vpn_channel",true)
            .putExtra("proxyData", proxyData!!["proxyName"]as String)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, "iyue_vpn_channel")
            .setContentTitle("${applicationInfo.loadLabel(packageManager)}: ${proxyData!!["proxyName"]}")
            .setContentText("${proxyData!!["proxyType"]}: ${proxyData!!["proxyHost"]}:${proxyData!!["proxyPort"]}")
            .setSmallIcon(R.drawable.vpn_foreground)
            .setContentIntent(pendingIntent)
            .build()

        startForeground(1, notification) // 使用一个唯一ID（例如1）来启动前台服务

        return START_NOT_STICKY
    }

    private fun startVpn(data: Map<String, Any>) {

        Log.d(TAG, "startVpn: IyueVPNService: $data")
        // {proxyPort=8080, proxyPass=, proxyName=test, proxyType=http, proxyUser=, appProxyPackageList=[com.android.chrome], proxyHost=192.168.0.1}
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
            val proxyHost = data["proxyHost"].toString()
            val proxyPort = (data["proxyPort"] as String).toInt()
            val proxyType = data["proxyType"].toString()
            val proxyUser = data["proxyUser"].toString()
            val proxyPass = data["proxyPass"].toString()

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
            Log.d(TAG, "startEngine: ${key.toString()}")
            stopSignal.await()
        } catch (e: Exception) {
            Log.e(TAG, "startEngine: error ${e.message}")
        } finally {
            if (vpnInterface != null) {
                // 不能主动停止,会触发重复关闭fd 导致app崩溃
//                Engine.stop()
                vpnInterface?.close()
                vpnInterface = null
            }
            Log.d(TAG, "stopEngine: success!")
        }

    }

    private fun stopVpn() {
        Log.d(TAG, "stopVpn: vpnInterface $vpnInterface")
        try {
            // 通知startVpn中的等待线程可以结束
            stopSignal.countDown();
            if (vpnThread != null && vpnThread?.isAlive == true) {
                vpnThread?.interrupt()
            } else {
                Log.w(TAG, "vpnThread is either null or not alive, interrupt is not called.")
            }
        } catch (e: Exception) {
            Log.e(TAG, "stopVpn: ${e.message}")
        }

    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "onDestroy: ")
    }

    private fun jsonToList(jsonString: String): List<String> {
        val gson = Gson()
        return gson.fromJson(jsonString, Array<String>::class.java).toList()
    }

    public fun isVpnRunning(): Boolean {
        return vpnInterface != null
    }

    public fun getProxyData() : String? {
        return proxyData!!["proxyName"]?.toString()
    }

}