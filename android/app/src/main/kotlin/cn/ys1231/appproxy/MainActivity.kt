package cn.ys1231.appproxy

import android.Manifest.permission.POST_NOTIFICATIONS
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.util.Log
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import cn.ys1231.appproxy.EbpfService.EbpfChannelHandler
import cn.ys1231.appproxy.IyueService.IyueVPNService
import cn.ys1231.appproxy.IyueService.VpnServiceController
import cn.ys1231.appproxy.data.AppChangeReceiver
import cn.ys1231.appproxy.data.Utils
import cn.ys1231.appproxy.mcpserver.MCPForegroundService
import cn.ys1231.appproxy.mcpserver.MCPServer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel


class MainActivity : FlutterActivity() {
    private val TAG = "iyue->${this.javaClass.simpleName}"
    private val CHANNEL = "cn.ys1231/appproxy"
    private val CHANNEL_VPN = "cn.ys1231/appproxy/vpn"
    private val CHANNEL_APP_UPDATE = "cn.ys1231/appproxy/appupdate"
    private val CHANNEL_MCP_SERVER = "cn.ys1231/appproxy/mcpserver"
    private var FLUTTER_VPN_CHANNEL: MethodChannel? = null
    private var FLUTTER_CHANNEL: MethodChannel? = null
    private var utils: Utils? = null
    private var intentVpnService: Intent? = null
    private var iyueVpnService: IyueVPNService? = null
    private var isBind: Boolean = false
    var currentProxy: Map<String, Any>? = null
    private var conn: ServiceConnection? = null
    private var vpnController: VpnServiceController? = null
    private var mcpServiceBinder: MCPForegroundService.MCPServiceBinder? = null
    private var mcpConn: ServiceConnection? = null
    private var isMcpBind: Boolean = false
    // eBPF(sing-box) 引擎：与原 VPN 通道完全独立
    private var ebpfChannelHandler: EbpfChannelHandler? = null
    /**
     * VPN 授权弹窗期间挂起的 startVpn 结果：
     * 未授权时不能立即回写 Result，否则 Flutter 侧会误以为 VPN 已启动；等 onActivityResult
     * 拿到用户选择后再启动并回写。同一时刻只允许一个挂起请求。
     */
    private var pendingVpnStartResult: MethodChannel.Result? = null
    // 使用 lateinit 延迟初始化
    private lateinit var receiver: AppChangeReceiver

    /** 入口：绑定 VPN 服务与 MCP 前台服务、注册应用安装/卸载广播、检查通知权限 */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intentVpnService = Intent(this, IyueVPNService::class.java)
        vpnController = VpnServiceController(this, iyueVpnService, utils!!)
        conn = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
                Log.d(TAG, "onServiceConnected: $name")

                if (service is IyueVPNService.VPNServiceBinder) {
                    iyueVpnService = service.getService()
                    vpnController?.updateVpnService(iyueVpnService)
                    MCPServer.getInstance(context).setVpnController(vpnController)
                    Log.d(TAG, "onServiceConnected: ${iyueVpnService.toString()}")
                } else {
                    Log.d(TAG, "onServiceConnected: ClassCastException")
                }
            }

            override fun onServiceDisconnected(name: ComponentName?) {
                Log.d(TAG, "onServiceDisconnected: $name")
            }
        }
        if (bindService(intentVpnService!!, conn!!, Context.BIND_AUTO_CREATE)) {
            isBind = true
        }

        // 启动并绑定 MCPForegroundService，确保 App 进入后台后 MCP Server 持续运行
        val mcpServiceIntent = Intent(this, MCPForegroundService::class.java)
        startForegroundService(mcpServiceIntent)
        mcpConn = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
                Log.d(TAG, "MCPForegroundService onServiceConnected")
                mcpServiceBinder = service as? MCPForegroundService.MCPServiceBinder
            }

            override fun onServiceDisconnected(name: ComponentName?) {
                Log.d(TAG, "MCPForegroundService onServiceDisconnected")
                mcpServiceBinder = null
            }
        }
        if (bindService(mcpServiceIntent, mcpConn!!, Context.BIND_AUTO_CREATE)) {
            isMcpBind = true
        }
        // 只检查通知权限；VPN 授权延后到用户真正启动 tun2socks 引擎时再请求
        //（启动即 prepare 会拉起系统 VPN 授权弹窗，打断/抢占设备上其它 VPN）
        checkNotificationPermission()

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REMOVED)
            addAction(Intent.ACTION_PACKAGE_REPLACED)
            addDataScheme("package")
        }
        receiver = AppChangeReceiver{
            Log.d(TAG, "onAppChanged: $packageName, notify Flutter to refresh app list")
            FLUTTER_CHANNEL?.invokeMethod("onRefresh", null)
        }
        registerReceiver(receiver, filter)
    }

    /**
     * 启动 tun2socks(VPN) 引擎：把配置交给绑定的 IyueVPNService（它负责建 TUN + 拉引擎）。
     *
     * 顺带起一个"看门"线程：每秒问一次 VPN 是否还在跑，一旦发现停了就通知 Flutter 把开关复位
     *（用户可能是在系统的 VPN 设置里关掉、或系统回收了服务，UI 需要同步）。
     * 这是**原 VPN 链路**的行为，eBPF 引擎走的是另一条通道（见 EbpfChannelHandler）。
     */
    private fun startVpnService() {
        Log.d(TAG, "startVpnService: ${currentProxy.toString()}")
        iyueVpnService?.startVpnService(currentProxy!!)
        vpnController?.setVpnConfig(currentProxy!!)

        // 检测VPN服务是否停止 通知 Flutter 更新 ui
        Thread {
            Log.d(TAG, "check iyueVpnService isRunning: " + iyueVpnService?.isRunning())
            while (true) {

                if (iyueVpnService?.isRunning() == true) {
                    Thread.sleep(1000)
                } else {
                    runOnUiThread {
                        FLUTTER_VPN_CHANNEL!!.invokeMethod("stopVpn", null)
                    }
                    break
                }
            }
        }.start()
    }

    /** 停止 tun2socks(VPN) 引擎（关闭 TUN、停引擎，见 IyueVPNService.stopVpnService） */
    private fun stopVpnService() {
        Log.d(TAG, "stopVpnService: ...... ")
        iyueVpnService?.stopVpnService()
    }

    /**
     * 交给系统去下载 APK（不自己下载）：构造 ACTION_VIEW 让浏览器/下载器接管。
     * Flutter 侧「发现新版本 → 下载」走的就是这里。
     */
    private fun startDownload(url: String?) {
        val downloadIntent = Intent(Intent.ACTION_VIEW)
        downloadIntent.data = Uri.parse(url)
        downloadIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        startActivity(downloadIntent)
    }

    /** 注册全部 MethodChannel：应用列表、原 VPN 通道、更新下载、MCP、以及新的 eBPF 通道 */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        utils = Utils(this)

        // eBPF(sing-box) 引擎通道：新通道，原 vpn 通道逻辑不动
        ebpfChannelHandler = EbpfChannelHandler(this, this).also {
            it.register(flutterEngine)
            // 冷启动清孤儿（仅当上次会话标记为运行中时才真正执行 root 检查）
            it.cleanupOrphanIfNeeded()
        }

        FLUTTER_CHANNEL = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )
        FLUTTER_CHANNEL!!.setMethodCallHandler { call, result ->
            if (call.method == "getAppList") {
                try {
                    Log.d(TAG, "configureFlutterEngine ${call.method} ")
                    val appList = utils!!.getAppList()
                    result.success(appList)
                } catch (e: Exception) {
                    result.error("-1", e.message, null)
                }

            }
        }

        FLUTTER_VPN_CHANNEL = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_VPN
        )
        FLUTTER_VPN_CHANNEL!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "startVpn" -> {
                    try {
                        if (pendingVpnStartResult != null) {
                            // 已有授权请求在途：直接失败，避免同一个 Result 被多次回写
                            result.error("-1", "VPN 授权请求正在进行中，请稍候", null)
                        } else {
                            currentProxy = call.arguments<Map<String, Any>>()
                            requestVpnPermission(result)
                        }
                    } catch (e: Exception) {
                        // 异常时清理挂起状态，否则后续 startVpn 会一直被拒
                        pendingVpnStartResult = null
                        result.error("-1", e.message, null)
                    }
                }
                "stopVpn" -> {
                    try {
                        stopVpnService()
                        result.success(!iyueVpnService?.isRunning()!!)
                    } catch (e: Exception) {
                        result.error("-1", e.message, null)
                    }
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_APP_UPDATE
        ).setMethodCallHandler { call, result ->
            if (call.method == "startDownload") {
                try {
                    Log.d(TAG, "configureFlutterEngine ${call.method} ")
                    val url: String? = call.arguments<String>()
                    startDownload(url)
                } catch (e: Exception) {
                    result.error("-1", e.message, null)
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_MCP_SERVER
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startMcpServer" -> {
                    try {
                        mcpServiceBinder?.startMcpServer()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("-1", e.message, null)
                    }
                }
                "stopMcpServer" -> {
                    try {
                        mcpServiceBinder?.stopMcpServer()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("-1", e.message, null)
                    }
                }
                "updateMcpServerConfig" -> {
                    try {
                        val arguments = call.arguments as List<*>
                        val port: Int = arguments[0] as Int
                        val auth: String = arguments[1] as String
                        // 用局部变量捕获 binder，避免两次访问间 binder 状态变化引发不一致
                        val binder = mcpServiceBinder
                        if (binder != null) {
                            binder.updateMcpPort(port)
                            binder.updateMcpAuth(auth)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("-1", e.message, null)
                    }
                }
            }
        }


        // 遍历所有 app 通知刷新
        Thread {
            Log.d(TAG, "configureFlutterEngine: start get app list info")
            utils!!.initAppList()
            runOnUiThread {
                Log.d(TAG, "configureFlutterEngine: call onRefresh")
                FLUTTER_CHANNEL!!.invokeMethod("onRefresh", null)
                Log.d(TAG, "configureFlutterEngine: end get app list info")
            }
        }.start()
    }

    private val VPN_REQUEST_CODE = 100
    private val REQUEST_NOTIFICATION_PERMISSION = 1231
    /**
     * 通知权限（Android 13+）：前台服务要挂通知，没有通知权限通知会显示不出来。
     *
     * 只在 App 启动时检查；**不涉及 VPN 授权**（见 [requestVpnPermission]）。
     */
    private fun checkNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(
                    this,
                    POST_NOTIFICATIONS
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(POST_NOTIFICATIONS),
                    REQUEST_NOTIFICATION_PERMISSION
                )
            } else {
                // 权限已被授予
                Log.d(TAG, "checkNotificationPermission: 通知权限已授予!")
            }
        }
    }

    /**
     * VPN 授权 + 启动 tun2socks（授权结果需要异步续接）：
     *   - 已授权（prepare 返回 null）：立即 [startVpnService] 并回写结果；
     *   - 未授权：把 MethodChannel.Result 挂起（[pendingVpnStartResult]），拉起系统授权弹窗，
     *     等 onActivityResult(VPN_REQUEST_CODE) 里再启动并回写结果。
     *
     * 注意：调用方（startVpn 通道分支）已先设置 currentProxy，并保证没有在途的挂起请求。
     */
    private fun requestVpnPermission(result: MethodChannel.Result) {
        val intent = VpnService.prepare(context)
        if (intent == null) {
            // 已授权：直接启动并返回运行状态
            startVpnService()
            result.success(iyueVpnService?.isRunning())
            return
        }
        // 未授权：挂起结果，等用户操作后由 onActivityResult 续接（不能在这里先返回）
        pendingVpnStartResult = result
        this.startActivityForResult(intent, VPN_REQUEST_CODE)
    }

    /** VPN 授权弹窗的回调：续接被挂起的 startVpn 请求（同意 → 启动；拒绝 → 返回 false） */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            val pending = pendingVpnStartResult
            pendingVpnStartResult = null
            if (pending == null) {
                // 进程重建等异常情况下没有挂起请求：不启动 VPN，避免用空 currentProxy 启动
                Log.w(TAG, "onActivityResult: 没有挂起的 startVpn 请求，忽略")
                return
            }
            if (resultCode == Activity.RESULT_OK) {
                // 用户授权成功：启动并回写挂起的结果。
                // 启动异常也必须回写（且只回写一次），否则挂起的 MethodChannel 结果永远
                // 得不到回复，Flutter 侧会一直等待。
                Log.d(TAG, "onActivityResult: 用户授权成功")
                try {
                    startVpnService()
                    pending.success(iyueVpnService?.isRunning())
                } catch (e: Exception) {
                    Log.e(TAG, "onActivityResult: startVpnService failed: ${e.message}", e)
                    pending.success(false)
                }
            } else {
                // 用户拒绝授权：明确回失败，避免 Flutter 侧一直等待
                Log.d(TAG, "onActivityResult: 用户拒绝授权")
                pending.success(false)
            }
        }
    }

    /** 通知权限回调：被拒时提示并引导到系统设置 */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATION_PERMISSION) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                // 权限被授予
                Toast.makeText(this, "通知权限被授予", Toast.LENGTH_SHORT).show()
            } else {
                // 权限被拒绝
                Toast.makeText(this, "此应用程序需要通知权限", Toast.LENGTH_SHORT).show()
                startNotificationSetting()
            }
        }
    }

    /**
     * 跳到本应用的系统设置页，让用户手动打开通知（通知权限被拒时的引导）。
     * 先试"应用通知设置"，失败再退到"应用详情页" —— 不同 ROM 支持的 action 不一样。
     */
    private fun startNotificationSetting() {
        val applicationInfo = applicationInfo
        try {
            val intent = Intent()
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            intent.action = "android.settings.APP_NOTIFICATION_SETTINGS"
            intent.putExtra("app_package", applicationInfo.packageName)
            intent.putExtra("android.provider.extra.APP_PACKAGE", applicationInfo.packageName)
            intent.putExtra("app_uid", applicationInfo.uid)
            startActivity(intent)
        } catch (e: Exception) {
            val intent = Intent()
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            intent.action = "android.settings.APPLICATION_DETAILS_SETTINGS"
            intent.data = Uri.fromParts("package", applicationInfo.packageName, null)
            startActivity(intent)
        }
    }

    /** Activity 销毁：解绑两个服务、注销广播接收器（避免泄漏） */
    override fun onDestroy() {
        super.onDestroy()
        if (isBind) {
            unbindService(conn!!)
            isBind = false
        }
        if (isMcpBind) {
            unbindService(mcpConn!!)
            isMcpBind = false
        }
        // 4. 在 Activity 销毁时取消注册，避免内存泄漏
        if (::receiver.isInitialized) {
            unregisterReceiver(receiver)
        }
    }
}
