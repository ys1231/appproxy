package cn.ys1231.appproxy.EbpfService

import android.app.Activity
import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * eBPF(sing-box) 引擎的 MethodChannel：`cn.ys1231/appproxy/ebpf`
 *
 * 与原 `cn.ys1231/appproxy/vpn`（tun2socks）通道完全独立，两条链路互不感知。
 *
 * ─────────────────────────────────────────────────────────────────────────
 * 【概念：MethodChannel 是什么，这里的线程模型为什么要这样】
 * MethodChannel 是 Flutter(UI 线程, Dart) 与原生(Android 主线程, Kotlin) 之间的双向调用通道：
 *   Dart 调 Kotlin：invokeMethod(方法名, 参数)  → 本文件的 handle()
 *   Kotlin 调 Dart：channel.invokeMethod(同名回调, 参数) → Dart 侧 setMethodCallHandler
 *
 * 线程模型（两个方向都要小心）：
 *   - `handle()` 跑在 **主线程**：所以里面绝不能直接做耗时/root 操作，否则会卡 UI（甚至 ANR）。
 *     本文件的做法是 runAsync{...}：把活丢到 Thread 里，算完再 runOnUiThread 回结果。
 *   - 进度回调（下载百分比）反过来：`channel.invokeMethod` 必须在主线程调，
 *     所以 sendProgress() 里也套了一层 runOnUiThread。
 *
 * 【每个方法对应 Flutter 侧哪段 UI】（Dart 封装见 lib/data/ebpf_proxy_data.dart）
 *
 * | 方法                | 谁调 / 何时调                     | 参数                        | 返回 |
 * |---------------------|-----------------------------------|-----------------------------|------|
 * | getSupportStatus    | 打开「添加/修改代理配置」页       | —                           | SupportStatus（读缓存，秒回） |
 * | checkEbpfSupport    | 设置页「检测」按钮                | autoDownload, downloadBase  | SupportStatus（会跑 root 命令） |
 * | getBinaryStatus     | 设置页展示二进制信息              | —                           | BinaryStatus |
 * | checkBinaryUpdate   | 设置页打开时静默检查版本          | downloadBase                | BinaryUpdateInfo（含 changelog 地址） |
 * | downloadBinary      | 设置页「下载 / 继续下载 / 更新」  | downloadBase                | BinaryStatus |
 * | start               | 代理列表开关（该条标记了 ebpf）   | configJson, summary         | RunStatus |
 * | stop                | 代理列表开关关闭 / 通知栏「停止」 | —                           | Boolean |
 * | status              | 启动前/界面刷新                   | —                           | RunStatus |
 * | readLog             | 设置页日志页                      | maxBytes                    | String |
 * | cleanupRuntimeDir   | 设置页「清理运行目录」            | —                           | Boolean |
 *
 * 进度/阶段回调（原生 → Flutter）：`onEbpfProgress` {phase: download|starting|started, percent?}
 * ─────────────────────────────────────────────────────────────────────────
 */
class EbpfChannelHandler(private val activity: Activity, private val context: Context) {

    companion object {
        const val CHANNEL = "cn.ys1231/appproxy/ebpf"
        private const val TAG = "iyue->EbpfChannel"
    }

    private val manager = EbpfProxyManager.get(context)
    private var channel: MethodChannel? = null

    /** 创建并注册 eBPF 通道（在 MainActivity.configureFlutterEngine 里调用一次） */
    fun register(engine: FlutterEngine) {
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result -> handle(call, result) }
    }

    /** 通道方法分发：按方法名走不同分支，读缓存的直接回，跑命令的交给 runAsync */
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // 读缓存，不执行命令（表单打开时调用，要求秒回）
            "getSupportStatus" -> result.success(manager.getSupportStatus().toMap())

            // 完整检测（root + 二进制 + 运行目录 + 两种数据面），可选自动下载
            "checkEbpfSupport" -> {
                val autoDownload = call.argument<Boolean>("autoDownload") ?: true
                val downloadBase = call.argument<String>("downloadBase")
                runAsync(result) {
                    manager.checkSupport(autoDownload, downloadBase) { percent ->
                        sendProgress("download", percent)
                    }.toMap()
                }
            }

            "getBinaryStatus" -> result.success(manager.getBinaryStatus().toMap())

            // 检查版本清单（{base}/update.json）：拿到最新版本号与按 ABI 拼好的下载地址
            "checkBinaryUpdate" -> {
                val downloadBase = call.argument<String>("downloadBase")
                runAsync(result) { manager.checkBinaryUpdate(downloadBase).toMap() }
            }

            "downloadBinary" -> {
                val downloadBase = call.argument<String>("downloadBase")
                runAsync(result) {
                    manager.downloadBinary(downloadBase) { percent -> sendProgress("download", percent) }
                        .toMap()
                }
            }

            "start" -> {
                val configJson = call.argument<String>("configJson")
                    ?: return result.error("-1", "缺少 configJson", null)
                val summary = call.argument<String>("summary") ?: ""
                runAsync(result) {
                    val status = manager.start(configJson) { phase -> sendProgress(phase, null) }
                    EbpfProxyService.start(context, summary)
                    status.toMap()
                }
            }

            "stop" -> runAsync(result) {
                val stopped = manager.stop()
                EbpfProxyService.stop(context)
                stopped
            }

            "status" -> runAsync(result) { manager.status().toMap() }

            "readLog" -> {
                val maxBytes = call.argument<Int>("maxBytes") ?: (32 * 1024)
                runAsync(result) { manager.readLog(maxBytes) }
            }

            "cleanupRuntimeDir" -> runAsync(result) { manager.cleanupRuntimeDir() }

            else -> result.notImplemented()
        }
    }

    /** App 冷启动时调用：仅当上次会话处于运行中才做孤儿清理（避免每次都弹 su） */
    fun cleanupOrphanIfNeeded() {
        if (!manager.needsOrphanCheck()) return
        Thread {
            try {
                manager.cleanupOrphan()
            } catch (e: Exception) {
                Log.w(TAG, "cleanupOrphanIfNeeded: ${e.message}")
            }
        }.start()
    }

    /** 把耗时的原生操作放到后台线程执行，结果再回主线程（MethodChannel 要求） */
    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        Thread {
            try {
                val value = block()
                activity.runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                Log.w(TAG, "runAsync failed: ${e.message}")
                activity.runOnUiThread { result.error("-1", e.message, null) }
            }
        }.start()
    }

    /** 进度/阶段回传给 Flutter（主线程调用 invokeMethod） */
    private fun sendProgress(phase: String, percent: Int?) {
        val payload = HashMap<String, Any>()
        payload["phase"] = phase
        if (percent != null) payload["percent"] = percent
        activity.runOnUiThread {
            try {
                channel?.invokeMethod("onEbpfProgress", payload)
            } catch (e: Exception) {
                Log.w(TAG, "sendProgress: ${e.message}")
            }
        }
    }
}

private fun EbpfProxyManager.BinaryStatus.toMap(): Map<String, Any?> = mapOf(
    "abi" to abi,
    "fileName" to fileName,
    "exists" to exists,
    "size" to size,
    "version" to version,
    // 下载来源版本（update.json 的 version）+ 未下完的临时文件大小（用于「继续下载」文案）
    "packageVersion" to packageVersion,
    "pendingBytes" to pendingBytes,
    "updatedAt" to updatedAt,
)

private fun EbpfProxyManager.BinaryUpdateInfo.toMap(): Map<String, Any?> = mapOf(
    "latestVersion" to latestVersion,
    "versionCode" to versionCode,
    "downloadUrl" to downloadUrl,
    "changelogUrl" to changelogUrl,
    "error" to error,
)

private fun EbpfProxyManager.SupportStatus.toMap(): Map<String, Any?> = mapOf(
    "root" to root,
    "binaryReady" to binaryReady,
    "supported" to supported,
    "cgroup" to cgroup,
    "tc" to tc,
    "runtimeDir" to runtimeDir,
    "kernelRelease" to kernelRelease,
    "binaryVersion" to binaryVersion,
    "binaryPackageVersion" to binaryPackageVersion,
    "binaryVersionCode" to binaryVersionCode,
    "binaryChangelogUrl" to binaryChangelogUrl,
    "checkedAt" to checkedAt,
    "result" to result,
    "cgroupReasons" to cgroupReasons,
    "tcReasons" to tcReasons,
    "wasRunning" to wasRunning,
)

private fun EbpfProxyManager.RunStatus.toMap(): Map<String, Any?> = mapOf(
    "running" to running,
    "pid" to pid,
    "runDir" to runDir,
)
