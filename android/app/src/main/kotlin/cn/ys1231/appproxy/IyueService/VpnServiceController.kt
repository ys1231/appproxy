package cn.ys1231.appproxy.IyueService

import android.content.Context
import android.util.Log
import cn.ys1231.appproxy.data.Utils

/**
 * tun2socks(VPN) 引擎的控制器：给 MCP 工具（以及任何非 UI 调用方）用的薄封装。
 *
 * 它与 Flutter 的 `cn.ys1231/appproxy/vpn` 通道**不共享状态**：
 *  - Flutter 直接调 MainActivity → IyueVPNService；
 *  - MCP 走这里，内部维护一份"当前配置"（currentProxy），用于「改了配置要重启」的判断。
 * 两边最终都落到同一个 IyueVPNService 上，所以引擎本身仍然是单实例。
 */
class VpnServiceController(
    private val context: Context,
    private var vpnService: IyueVPNService?,
    private val utils: Utils
) {
    private val TAG = "iyue->${this.javaClass.simpleName}"
    private var currentProxy: MutableMap<String, Any>? = HashMap()
    private var fields = listOf("proxyPort","proxyPass","proxyName","proxyType","proxyUser","appProxyPackageList","proxyHost")

    /** 注入/更新底层 VPN 服务引用（MainActivity 在服务连接成功后调用） */
    fun updateVpnService(newVpnService: IyueVPNService?) {
        vpnService = newVpnService
        Log.d(TAG, "VPN service updated: $newVpnService")
    }

    /**
     * 就地更新当前配置（只认 fields 里列出的键）。
     * @return true = 至少有一个字段真的变了（调用方据此决定要不要重启 VPN 才能生效）
     */
    fun setVpnConfig(config: Map<String, Any>): Boolean {
        var isChange = false
        for (key in config.keys) {
            if (fields.contains(key)) {
                currentProxy!![key] = config[key]!!
                isChange = true
            }
        }
        return isChange
    }

    /** 当前配置（含未生效的最新值）；MCP 的 get_proxy_config 用它回显 */
    fun getVpvConfig(): Map<String, Any>? {
        return currentProxy
    }
    /** 设备上装了哪些"请求过 INTERNET 权限"的应用包名（MCP 用它校验参数里的包名是否合法） */
    fun getPackageList(): List<String> {
        return utils.getPackageList()
    }

    /** 启动 VPN 引擎，返回可读结果字符串（MCP 直接回显；失败以 "Error to start VPN: " 开头） */
    fun startVpn(config: Map<String, Any>): String {
        return try {
            // {proxyPort=8080, proxyPass=, proxyName=vpn, proxyType=http, proxyUser=, appProxyPackageList=["com.bssss"], proxyHost=192.168.0.11}
            vpnService?.startVpnService(config)
            "VPN started successfully"
        } catch (e: Exception) {
            "Error to start VPN: ${e.message}"
        }
    }

    /** 停止 VPN 引擎，返回可读结果字符串（MCP 直接回显） */
    fun stopVpn(): String {
        return try {
            run {
                vpnService?.stopVpnService()
                "VPN stopped state:${vpnService?.isRunning()}"
            }
        } catch (e: Exception) {
            "Error to stop VPN: ${e.message}"
        }
    }

    /** 引擎是否在跑（null = 服务还没绑定上，调用方按"没在跑"处理即可） */
    fun getVpnStatus(): Boolean? {
        return vpnService?.isRunning()
    }

}