package cn.ys1231.appproxy.mcpserver

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import cn.ys1231.appproxy.MainActivity
import cn.ys1231.appproxy.R

/**
 * MCP Server 前台服务
 *
 * 将 Netty HTTP Server 托管在前台服务中，确保 App 进入后台后
 * Android 系统不会挂起网络线程或终止进程，客户端始终可以连接。
 *
 * 【为什么必须是"前台"服务】
 * Android 8.0 起限制后台进程：普通后台服务随时可能被回收，网络线程也会被挂起。
 * 只有前台服务（必须挂一条常驻通知）才能长期存活 —— 所以这条通知不是"装饰"，
 * 它是"系统允许你一直跑"的凭证。
 *
 * 【谁调用它】
 * MainActivity 在 onCreate 里 startForegroundService + bindService，
 * 之后所有操作（启停/改端口/改鉴权）都通过 [MCPServiceBinder] 转发到这里，
 * 由这里再委托给 [MCPServer]（真正持有 Netty 与工具实现的地方）。
 * 也就是说：**服务层只管 Android 生命周期与通知，业务状态不在这里**。
 */
class MCPForegroundService : Service() {

    private val TAG = "iyue->${this.javaClass.simpleName}"
    // 与 IyueVPNService 的通知 ID(1) 区分开，避免覆盖
    private val NOTIFICATION_ID = 2
    private val CHANNEL_ID = "mcp_server_channel"

    /**
     * 向 MainActivity 暴露的 Binder：跨进程/跨组件调用的入口。
     * 每个方法都直接委托给 Service 内部实现，Binder 本身不做事（只做转发）。
     */
    inner class MCPServiceBinder : Binder() {
        /** 启动 MCP 服务（含前台通知）；失败时静默返回 false，客户端连不上会表现为请求超时/拒绝 */
        fun startMcpServer() = this@MCPForegroundService.startMcpServer()

        /** 停止 MCP 服务并撤下前台通知 */
        fun stopMcpServer() = this@MCPForegroundService.stopMcpServer()

        /** 改监听端口（仅在服务运行中才会真正重启） */
        fun updateMcpPort(port: Int?) = this@MCPForegroundService.updateMcpPort(port)

        /** 改 Bearer 鉴权 token（仅在服务运行中才会真正重启） */
        fun updateMcpAuth(auth: String?) = this@MCPForegroundService.updateMcpAuth(auth)
    }

    private val binder = MCPServiceBinder()

    /** 创建时先建通知渠道（8.0+ 必须，否则后面 startForeground 会失败） */
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        Log.d(TAG, "onCreate: MCPForegroundService")
    }

    /** 绑定：把 Binder 交给 MainActivity（用它来启停服务） */
    override fun onBind(intent: Intent?): IBinder {
        Log.d(TAG, "onBind: MCPForegroundService")
        return binder
    }

    /** 拉起前台通知（Android 14 起必须带 foregroundServiceType），返回 START_NOT_STICKY */
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: MCPForegroundService")
        // 立即提升为前台服务，防止系统在后台将进程降级
        // Android 14（API 34）起，Manifest 声明了 foregroundServiceType 后必须传入对应类型，否则抛 MissingForegroundServiceTypeException
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }
        // 不需要系统在服务被杀后自动重启，App 重新打开时会由 Flutter 重新启动
        return START_NOT_STICKY
    }

    /** 划掉最近任务 = 停 MCP 服务，避免 Netty 在后台残留 */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // 用户从最近任务划掉 App 时，主动停止服务，避免 Netty 服务器在后台残留
        Log.d(TAG, "onTaskRemoved: app exit, Stop MCPForegroundService")
        stopMcpServer()
        stopSelf()
    }

    /** 销毁时确保 Netty 被停掉，释放端口 */
    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "onDestroy: MCPForegroundService")
        // 服务被销毁时确保 Netty 服务器资源得到释放
        stopMcpServer()
    }

    // ---------- 私有服务方法，Binder 统一委托到这里 ----------

    private fun startMcpServer() {
        // stopMcpServer 会通过 stopForeground 移除通知，所以每次启动都需要重新调用 startForeground
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, buildNotification(true), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, buildNotification(true))
        }
        Log.d(TAG, "startMcpServer: Netty server started")
        MCPServer.getInstance(applicationContext).startMcpServer()
    }

    /** 停服务：先停 Netty，再撤下前台通知（撤了通知服务就退回后台，系统可能很快回收它） */
    private fun stopMcpServer() {
        MCPServer.getInstance(applicationContext).stopMcpServer()
        // 移除前台通知，下次 startMcpServer 会重新调用 startForeground 补回来
        Log.d(TAG, "stopMcpServer: Netty server stopped")
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    /** 改端口：委托给 MCPServer（它会判断是否需要重启 Netty） */
    private fun updateMcpPort(port: Int?) {
        Log.d(TAG, "updateMcpPort: $port")
        MCPServer.getInstance(applicationContext).updateMcpPort(port)
    }

    /** 改鉴权 token：同 updateMcpPort，委托给 MCPServer */
    private fun updateMcpAuth(auth: String?) {
        Log.d(TAG, "updateMcpAuth: $auth")
        MCPServer.getInstance(applicationContext).updateMcpAuth(auth)
    }

    // ---------- 通知相关 ----------

    /** 通知渠道：8.0+ 通知必须归属某个渠道；用低优先级避免每次启停都弹提醒 */
    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "MCP Server",
            // 使用低优先级，避免在状态栏产生弹出提醒打扰用户
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "AppProxy MCP Server"
            lightColor = Color.GREEN
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        }
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.createNotificationChannel(channel)
    }

    /**
     * 构造常驻通知。
     * @param running true = 服务在跑（点开可进 App 配置）；false = 仅用于把服务提升为前台
     */
    private fun buildNotification(running: Boolean = false): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val contentText = if (running) "MCP Server is running" else "MCP Server is not running"
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("${applicationInfo.loadLabel(packageManager)}-mcp")
            .setContentText(contentText)
            .setSmallIcon(R.mipmap.vpn_round)
            .setContentIntent(pendingIntent)
            // 设置为持续通知，不允许用户手动滑掉
            .setOngoing(true)
            .build()
    }
}
