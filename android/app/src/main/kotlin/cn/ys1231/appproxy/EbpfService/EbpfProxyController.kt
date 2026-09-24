package cn.ys1231.appproxy.EbpfService

import android.content.Context
import android.util.Log

/**
 * eBPF 引擎的 MCP 入口，与 [cn.ys1231.appproxy.IyueService.VpnServiceController] 同层级。
 *
 * MCP 的 `start_proxy` 在 `proxyEngine=ebpf` 时走这里；`stop_proxy` / `get_proxy_status`
 * 由 MCP 按「实际运行的引擎」选择调用哪个 Controller。
 *
 * 与 Flutter 路径的关系：Flutter 的 config.json 由 Dart 生成后经通道传入；
 * MCP 不经过 Dart，所以这里用 [EbpfConfigBuilder] 生成（规则两边保持一致）。
 */
class EbpfProxyController(private val context: Context) {

    private val TAG = "iyue->EbpfProxyController"
    private val manager = EbpfProxyManager.get(context)

    /**
     * 启动。返回可读结果字符串（MCP 直接回显），失败时以 "Error to start eBPF proxy: ..." 开头。
     */
    fun start(config: Map<String, Any?>): String {
        // 前置校验：root + 检测缓存（MCP 调用前应先让用户在设置页做过检测）
        if (!manager.isRootAvailable()) {
            return "Error to start eBPF proxy: root 不可用"
        }
        val support = manager.getSupportStatus()
        if (!support.supported) {
            return "Error to start eBPF proxy: 本机未通过 eBPF 检测（${support.result}），请先在设置页点「检测」"
        }
        if (!manager.getBinaryStatus().exists) {
            return "Error to start eBPF proxy: sing-box 二进制未下载，请先在设置页下载"
        }
        return try {
            val configJson = EbpfConfigBuilder.build(context, config)
            val status = manager.start(configJson)
            EbpfProxyService.start(context, EbpfConfigBuilder.summaryOf(config))
            "eBPF proxy started (pid=${status.pid}, runDir=${status.runDir})"
        } catch (e: Exception) {
            Log.w(TAG, "start failed: ${e.message}")
            "Error to start eBPF proxy: ${e.message}"
        }
    }

    /** 停止 eBPF 引擎并撤下通知；返回可读结果（MCP 直接回显） */
    fun stop(): String = try {
        val stopped = manager.stop()
        EbpfProxyService.stop(context)
        "eBPF proxy stopped: $stopped"
    } catch (e: Exception) {
        "Error to stop eBPF proxy: ${e.message}"
    }

    /** 引擎是否在跑（读 pid 文件 + kill -0，会执行 root 命令） */
    fun getStatus(): Boolean = try {
        manager.status().running
    } catch (e: Exception) {
        Log.w(TAG, "getStatus: ${e.message}")
        false
    }

    /** 当前生效的 config（用于 MCP 查询/排查，不执行命令） */
    fun getConfig(): Map<String, Any?> = mapOf(
        "proxyEngine" to "ebpf",
        "supported" to manager.getSupportStatus().supported,
        "runDir" to manager.getSupportStatus().runtimeDir,
        "binaryVersion" to manager.getSupportStatus().binaryVersion,
    )
}
