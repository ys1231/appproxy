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

/**
 * tun2socks(VPN) 引擎的 VpnService 实现。
 *
 * 【职责】用 Android 的 VpnService 建立 TUN 网卡（虚拟网卡），把应用流量送进 TUN，
 * 再由 tun2socks 引擎（JNI，见 engine.Engine）转成到目标代理的普通连接。
 * 支持的"分应用"由 VpnService.Builder 的 allow/disallow 决定（见 startVpnService）。
 *
 * 【与 eBPF 引擎的关系】两条路互斥、互不感知：这个类只服务原有的 VPN 链路，
 * eBPF(sing-box) 走 EbpfProxyManager，不经过 VpnService。
 *
 * 【状态】isRunning 只反映"这一次启动是否成功"，真正的事实来源是 vpnInterface 是否还在。
 */
class IyueVPNService : VpnService() {

    private val TAG = "iyue->${this.javaClass.simpleName} "

    private var vpnInterface: ParcelFileDescriptor? = null
    private var isRunning = false
    private val binder = VPNServiceBinder()

    /** 给 MainActivity 用的 Binder：把服务实例交出去，由它直接调下面的方法 */
    inner class VPNServiceBinder : Binder() {
        /** 把服务实例交给调用方（MainActivity 通过 Binder 拿到后直接调下面的方法） */
        fun getService(): IyueVPNService = this@IyueVPNService
    }

    /** 建通知渠道（前台服务需要），并打日志 */
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate: VPNServiceBinder")

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

    /** 返回 Binder（VpnService 必须实现；绑定方是 MainActivity） */
    override fun onBind(intent: Intent?): IBinder {
        Log.d(TAG, "onBind: VPNServiceBinder")
        return binder
    }

    /** START_NOT_STICKY：不要求系统自动重启（重启由 App 重新发起，避免状态不一致） */
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: ${intent.toString()}")
        return START_NOT_STICKY
    }

    /**
     * 启动 VPN：建 TUN（含分应用过滤）→ 把 fd 与代理地址交给 tun2socks 引擎。
     *
     * @param data 代理配置：proxyName/proxyHost/proxyPort/proxyType/proxyUser/proxyPass/
     *             appProxyPackageList（JSON 字符串数组）
     *
     * 分应用规则（与 eBPF 侧同义）：
     *   - 列表为空 → addDisallowedApplication(自己) ⇒ 代理"除自己外所有应用"
     *   - 列表非空 → 逐个 addAllowedApplication ⇒ 只代理列表内的应用（找不到的包名忽略并记日志）
     */
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
            .setSmallIcon(R.mipmap.vpn_round)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()

        startForeground(1, notification)

        val builder = Builder()
            .addAddress("10.0.0.2", 24)
            .addRoute("0.0.0.0", 0)
            .setMtu(1500)
//            .addDnsServer("192.168.10.1")
            .setSession(packageName)
        val allowedApps = jsonToList(data["appProxyPackageList"].toString())
        if(allowedApps.isEmpty()){
            builder.addDisallowedApplication(packageName)
        }else{
            for (appPackageName in allowedApps) {
                try {
                    Log.d(TAG, "addAllowedApplication: $appPackageName")
                    builder.addAllowedApplication(appPackageName)
                } catch (e: Exception) {
                    Log.e(TAG, "addAllowedApplication: ${e.message}")
                }
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
            key.logLevel = "error"
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

    /**
     * 停止 VPN：关闭 TUN。
     *
     * 注意**不主动调 Engine.stop()**：tun2socks 在 fd 关闭后会自己退出，
     * 主动 stop 会与关闭 fd 竞争、触发重复关闭 fd 导致整个 app 崩溃（历史踩坑）。
     */
    fun stopVpnService() {
        Log.d(TAG, "stopVpnService: vpnInterface $vpnInterface")
        try {
            if (vpnInterface != null) {
                // 不能主动停止,会触发重复关闭fd 导致app崩溃
//                 Engine.stop()
                vpnInterface?.close()
                vpnInterface = null
                isRunning = false
                stopForeground(STOP_FOREGROUND_REMOVE)
            }
            Log.d(TAG, "stopEngine: success!")
        } catch (e: Exception) {
            Log.e(TAG, "stopVpnService: ${e.message}")
        }
    }

    /** 本次启动是否成功（TUN 建好且引擎已拉起）；不代表系统里 VPN 一定还活着 */
    fun isRunning(): Boolean {
        return isRunning
    }

    /** 把 Flutter 传来的 JSON 字符串（如 "["com.a"]"）解析成包名列表 */
    private fun jsonToList(jsonString: String): List<String> {
        val gson = Gson()
        return gson.fromJson(jsonString, Array<String>::class.java).toList()
    }

    /** 外部解绑时停止 VPN，避免留下没人管的 TUN */
    override fun onUnbind(intent: Intent?): Boolean {
        Log.d(TAG, "onUnbind: IyueVPNService ")
        stopVpnService()
        return super.onUnbind(intent)
    }

    /** 销毁时打日志（真正的清理在 stopVpnService / fd 关闭） */
    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "onDestroy: IyueVPNService ")
    }

}