package cn.ys1231.appproxy.EbpfService

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import cn.ys1231.appproxy.MainActivity
import cn.ys1231.appproxy.R

/**
 * eBPF(sing-box) 代理前台服务。
 *
 * ─────────────────────────────────────────────────────────────────────────
 * 【概念：为什么需要一个"前台服务"】
 * Android 从 8.0 起严格限制后台进程：app 退到后台后，随时可能被系统回收。
 * 想"长期做一件事"（这里是：让代理继续活着 + 让用户随时能看到/停掉它），
 * 标准做法是起一个 **前台服务** —— 它必须挂一条常驻通知（用户可见 = 系统允许你活着）。
 *
 * 三个 Android 细节（缺一不可，都在代码里体现）：
 *   1. 通知渠道（NotificationChannel）：8.0 起通知必须属于某个渠道，见 createNotificationChannel()
 *   2. foregroundServiceType：14 起启动前台服务必须声明类型；本项目在 Manifest 里用 specialUse
 *      （通用型），并配了 PROPERTY_SPECIAL_USE_FGS_SUBTYPE 说明用途，否则直接抛异常
 *   3. 通知 ID 不能撞：VPN(tun2socks) 用 1、MCP 用 2，这里用 3（撞了会互相覆盖）
 *
 * 【它管什么 / 不管什么】
 *   管：保活 + 通知栏展示 + 通知里的「停止」按钮
 *   不管：**不持有任何状态**。代理在不在跑，唯一事实来源是 EbpfProxyManager
 *        （通过 pid 文件 + kill -0 判断），避免"通知说在跑、其实早死了"这种假状态
 *
 * 【生命周期：与 app 绑定】
 *   划掉最近任务卡片 → 系统回调 onTaskRemoved() → 这里主动停代理 + 自己停掉。
 *   （本项目的语义就是"app 退了代理就停"，见 EbpfProxyManager 里关于 setsid 的说明）
 * ─────────────────────────────────────────────────────────────────────────
 */
class EbpfProxyService : Service() {

    private val TAG = "iyue->${this.javaClass.simpleName}"
    // 1 = VPN(tun2socks)、2 = MCP，这里用 3 避免互相覆盖
    private val NOTIFICATION_ID = 3
    private val CHANNEL_ID = "ebpf_proxy_channel"

    companion object {
        const val ACTION_START = "cn.ys1231.appproxy.ebpf.START"
        const val ACTION_STOP = "cn.ys1231.appproxy.ebpf.STOP"
        const val EXTRA_SUMMARY = "summary"

        /** 静态入口：启动前台服务并携带通知文案（由 EbpfProxyManager 启动成功后调用） */
        fun start(context: Context, summary: String) {
            val intent = Intent(context, EbpfProxyService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_SUMMARY, summary)
            }
            context.startForegroundService(intent)
        }

        /** 静态入口：请求停止代理（走 ACTION_STOP，见 onStartCommand） */
        fun stop(context: Context) {
            val intent = Intent(context, EbpfProxyService::class.java).apply { action = ACTION_STOP }
            try {
                context.startService(intent)
            } catch (e: Exception) {
                Log.w("iyue->EbpfProxyService", "stop: ${e.message}")
            }
        }
    }

    /** 不支持绑定：本服务不对外提供 Binder，状态一律从 EbpfProxyManager 读 */
    override fun onBind(intent: Intent?): IBinder? {
        // 不需要绑定：状态由 EbpfProxyManager 提供
        return null
    }

    /** 创建通知渠道（8.0+ 必须） */
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        Log.d(TAG, "onCreate")
    }

    /** 按 action 分流：停止 → 停代理并撤通知；默认 → 拉起前台通知 */
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                Log.d(TAG, "onStartCommand: ACTION_STOP")
                stopProxy()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            else -> {
                Log.d(TAG, "onStartCommand: ACTION_START")
                val summary = intent?.getStringExtra(EXTRA_SUMMARY) ?: ""
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    startForeground(
                        NOTIFICATION_ID,
                        buildNotification(summary),
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                    )
                } else {
                    startForeground(NOTIFICATION_ID, buildNotification(summary))
                }
            }
        }
        return START_NOT_STICKY
    }

    /** 用户划掉最近任务卡片 = 停止代理（本项目"生命周期绑定 app"的语义） */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // 划掉最近任务 = 停止代理（生命周期与 app 绑定）
        Log.d(TAG, "onTaskRemoved: stop ebpf proxy")
        stopProxy()
        stopSelf()
    }

    /** 服务被销毁时兜底停一次代理（stop 是幂等的，重复调用安全） */
    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "onDestroy")
        // 服务被销毁（含系统回收）时确保 root 进程也被清理，stop 是幂等的
        stopProxy()
    }

    /** 在后台线程停代理：停进程可能耗时，不能在主线程做 */
    private fun stopProxy() {
        Thread {
            try {
                EbpfProxyManager.get(applicationContext).stop()
            } catch (e: Exception) {
                Log.w(TAG, "stopProxy: ${e.message}")
            }
        }.start()
    }

    /** 建通知渠道；低优先级，避免每次启停都弹提示 */
    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "eBPF Proxy",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "AppProxy eBPF (sing-box) transparent proxy"
            lightColor = Color.BLUE
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }

    /** 构造常驻通知：标题带应用名，正文是代理摘要，附带「停止」按钮 */
    private fun buildNotification(summary: String): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, EbpfProxyService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("${applicationInfo.loadLabel(packageManager)}: eBPF")
            .setContentText(summary)
            .setSmallIcon(R.mipmap.vpn_round)
            .setContentIntent(contentIntent)
            .addAction(0, "停止", stopIntent)
            .setOngoing(true)
            .build()
    }
}
