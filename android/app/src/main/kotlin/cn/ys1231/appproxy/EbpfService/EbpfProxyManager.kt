package cn.ys1231.appproxy.EbpfService

import android.content.Context
import android.os.Build
import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonParser
import com.topjohnwu.superuser.Shell
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * eBPF(sing-box) 引擎管理器。
 *
 * 与 VpnService/tun2socks 路径完全独立：这里负责
 *  1) 二进制下载（按 ABI，仅下载，不做本地导入）
 *  2) 支持检测（`sing-box tools ebpf status --json`）+ 结果持久化（support.json）
 *  3) 运行目录部署（优先 app 私有目录，实测不可 exec 时回退 /data/local/tmp/appproxy）
 *  4) 以 root 启动/停止 sing-box（生命周期绑定 app：同进程组 + 看门狗兜底）
 *
 * 所有方法都会执行 root 命令，**必须在后台线程调用**。
 *
 * ─────────────────────────────────────────────────────────────────────────
 * 谁调用这里（三条入口，互不感知）
 *   Flutter 设置页/代理列表  → EbpfChannelHandler（MethodChannel）→ 本类
 *   MCP 工具（start_proxy 等）→ EbpfProxyController              → 本类
 *   App 冷启动              → EbpfChannelHandler.cleanupOrphanIfNeeded() → 只清孤儿，不恢复运行
 *
 * 状态放在哪（都在「设置侧」，**不参与备份/恢复**）
 *   filesDir/ebpf/support.json  检测结论 + 二进制版本 + 运行目录 + wasRunning（冷启动判断用）
 *   filesDir/ebpf/              下载未完成的分片以 .tmp 结尾（用于断点续传），与二进制同目录
 *
 * 维护速查（想微调时按这里找位置）
 *
 * 【目录】
 *   filesDir/ebpf/                      app 私有：下载的二进制(sing-box-<abi>) + support.json
 *   filesDir/ebpf/run/                  首选运行目录（root 创建，700）：
 *                                       sing-box / config.json(600) / sing-box.log / box.log / sing-box.pid
 *   /data/local/tmp/appproxy            app 私有目录无法 exec 时的回退运行目录
 *
 * 【root 命令流程】
 *   检测：  <run>/sing-box tools ebpf status --mode local --local-data-plane {cgroup|tc} --json
 *   启动：  cd <run>; ./sing-box run -c config.json > sing-box.log 2>&1 & echo $! > sing-box.pid
 *   停止：  kill -TERM $(cat sing-box.pid) → 等 5s → kill -KILL
 *   看门狗：setsid sh -c 'while kill -0 <appPid>; do sleep 2; done; kill -TERM $(cat pid)'
 *
 */
class EbpfProxyManager private constructor(private val context: Context) {

    companion object {
        private const val TAG = "iyue->EbpfProxyManager"

        /** 二进制下载源（自定义下载源留空时用它） */
        const val DEFAULT_DOWNLOAD_BASE = "https://pfile.ys1231.cn/modules/appproxy/sing-box/"

        private const val MIN_BINARY_SIZE = 5L * 1024 * 1024
        private const val ELF_MAGIC_0 = 0x7F
        private const val ELF_MAGIC_1 = 'E'.code

        /** 运行目录首选：app 私有目录（随卸载清理）；回退：/data/local/tmp/appproxy */
        private const val FALLBACK_RUN_DIR = "/data/local/tmp/appproxy"

        private const val BIN_NAME = "sing-box"
        private const val CONFIG_NAME = "config.json"
        private const val LOG_NAME = "sing-box.log"
        private const val BOX_LOG_NAME = "box.log"
        private const val PID_NAME = "sing-box.pid"
        /** 版本清单：{base}/update.json → {version, versionCode, baseUrl, changelog} */
        private const val UPDATE_JSON = "update.json"

        /** Flutter 侧 SharedPreferences（设置页写的「自定义下载源」在这里） */
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val KEY_DOWNLOAD_BASE = "flutter.ebpfDownloadBase"

        private const val START_TIMEOUT_MS = 8_000L
        private const val STOP_TIMEOUT_MS = 5_000L

        @Volatile
        private var instance: EbpfProxyManager? = null

        /** 取单例（双检锁）；持有的是 applicationContext，避免泄漏 Activity */
        fun get(context: Context): EbpfProxyManager =
            instance ?: synchronized(this) {
                instance ?: EbpfProxyManager(context.applicationContext).also { instance = it }
            }
    }

    private val gson = Gson()
    private val binDir = File(context.filesDir, "ebpf")
    private val supportFile = File(binDir, "support.json")

    // ---------------------------------------------------------------- 数据结构

    data class BinaryStatus(
        val abi: String = "",           // 本项目 ABI 名：arm64 / arm / amd64 / 386
        val fileName: String = "",      // filesDir/ebpf 下的文件名，如 sing-box-arm64
        val exists: Boolean = false,    // 是否已下载
        val size: Long = 0,             // 字节数（设置页展示）
        val version: String = "",       // 来自上次检测时执行的 `<bin> version`
        val packageVersion: String = "",// 下载来源的版本目录，如 v0.0.1（用于和 update.json 比对）
        val updatedAt: Long = 0,        // 文件 mtime
        val pendingBytes: Long = 0,     // 未下完的 .tmp 大小（>0 表示可续传）
    )

    /** 版本清单（update.json）解析结果 */
    data class BinaryUpdateInfo(
        val latestVersion: String = "",   // 最新版本号，如 v0.0.1
        val versionCode: Int = 0,
        val downloadUrl: String = "",     // 已按当前 ABI 拼好：{baseUrl}/{version}/sing-box-android-{abi}-with-ebpf
        val changelogUrl: String = "",
        val error: String = "",           // 非空表示检查失败（网络/格式）
    )

    /**
     * 检测结果（持久化在 filesDir/ebpf/support.json）。
     *
     * 「设置侧」数据：**不参与备份/恢复**（备份只含 proxyConfig.json），
     * 所以换机/恢复后一定重新检测，不会把别的设备的结论带过来。
     */
    data class SupportStatus(
        val root: Boolean = false,
        val binaryReady: Boolean = false,
        val supported: Boolean = false,
        val cgroup: Boolean = false,           // cgroup 数据面是否可用（默认用它）
        val tc: Boolean = false,               // tc 数据面是否可用（cgroup 挂不上时的退路）
        val runtimeDir: String = "",           // 实测出来的运行目录
        val kernelRelease: String = "",        // 便于排查；变化时视为缓存失效
        val binaryVersion: String = "",        // `<bin> version` 输出（sing-box 自身版本）
        val binaryPackageVersion: String = "", // 下载来源的版本目录，如 v0.0.1（与 update.json 比对）
        val binaryVersionCode: Int = 0,        // update.json 的 versionCode
        val binaryChangelogUrl: String = "",   // 更新说明地址
        val checkedAt: Long = 0,
        /** not_ready | no_root | preflight_passed | unsupported | inconclusive */
        val result: String = "not_ready",
        val cgroupReasons: List<String> = emptyList(),  // 失败原因（取 required 且非 PASS 的 feature/detail）
        val tcReasons: List<String> = emptyList(),
        /** 上次会话是否处于「运行中」：用于 app 冷启动时判断要不要清孤儿（避免每次都调 su） */
        val wasRunning: Boolean = false,
    )

    data class RunStatus(
        val running: Boolean = false,
        val pid: Long = -1,
        val runDir: String = "",       // 当前运行目录（设置页展示/排查用）
    )

    class EbpfException(message: String) : Exception(message)

    // ---------------------------------------------------------------- 基本查询

    fun binaryFile(): File = File(binDir, "$BIN_NAME-${abiName()}")

    /** Flutter/arm 通行的 ABI 名：arm64-v8a→arm64、armeabi-v7a→arm、x86_64→amd64、x86→386 */
    fun abiName(): String {
        val abis = Build.SUPPORTED_ABIS
        for (abi in abis) {
            when (abi) {
                "arm64-v8a" -> return "arm64"
                "armeabi-v7a", "armeabi" -> return "arm"
                "x86_64" -> return "amd64"
                "x86" -> return "386"
            }
        }
        return "arm64"
    }

    /**
     * 确保 filesDir/ebpf 可写。
     *
     * 兜底场景：该目录有时会被 **root** 创建（例如用 adb/su 手工预置过二进制），
     * 此时属主是 root、app 写不了 support.json / 下载文件（实测报 EACCES）。
     * 目录在 app 私有空间内，交还属主是安全的。
     */
    private fun ensureBinDir() {
        binDir.mkdirs()
        if (!binDir.canWrite()) {
            Log.w(TAG, "ensureBinDir: ${binDir.absolutePath} 不可写（很可能是 root 创建的），交还属主")
            val uid = android.os.Process.myUid()
            Shell.cmd(
                "chown $uid:$uid ${shq(binDir.absolutePath)}; " +
                    "chmod 700 ${shq(binDir.absolutePath)}"
            ).exec()
        }
    }

    /**
     * 是否已获得 root。
     *
     * 坑（真机实测踩到）：libsu 会**缓存 shell 及其 root 状态**。如果 App 第一次请求 root 时
     * 用户还没在 KernelSU/Magisk 里点允许，缓存的 shell 就是「非 root」，之后 `isAppGrantedRoot()`
     * 会一直返回 false，即使已经授权。处理办法：发现非 root 时丢弃缓存的 shell 再问一次，
     * 让它重新创建 shell（必要时会再次唤起授权流程）。
     */
    fun isRootAvailable(): Boolean = try {
        if (Shell.isAppGrantedRoot() == true) {
            true
        } else {
            val cached = Shell.getCachedShell()
            if (cached == null) {
                false
            } else {
                Log.d(TAG, "isRootAvailable: 丢弃缓存的非 root shell 重试")
                cached.waitAndClose()
                Shell.isAppGrantedRoot() == true
            }
        }
    } catch (e: Exception) {
        Log.w(TAG, "isRootAvailable: ${e.message}")
        false
    }

    /** 二进制现状：文件信息 + 上次检测得到的版本 + 未下完的分片大小（设置页用） */
    fun getBinaryStatus(): BinaryStatus {
        val f = binaryFile()
        val cached = readSupport()
        return BinaryStatus(
            abi = abiName(),
            fileName = f.name,
            exists = f.exists() && f.length() > 0,
            size = if (f.exists()) f.length() else 0,
            version = cached.binaryVersion,
            packageVersion = cached.binaryPackageVersion,
            updatedAt = if (f.exists()) f.lastModified() else 0,
            pendingBytes = pendingDownloadBytes(),
        )
    }

    /** 部分下载中的临时文件大小（>0 表示上次没下完，可续传） */
    fun pendingDownloadBytes(): Long {
        val tmp = File(binDir, binaryFile().name + ".tmp")
        return if (tmp.exists()) tmp.length() else 0
    }

    /** 读检测结论缓存（不执行任何命令，毫秒级，可用于页面 initState） */
    fun getSupportStatus(): SupportStatus = readSupport()

    // ---------------------------------------------------------------- 版本检查

    /**
     * 读取版本清单：`{base}/update.json` → `{version, versionCode, baseUrl, changelog}`
     * 并按当前 ABI 拼出下载地址：`{baseUrl}/{version}/sing-box-android-{abi}-with-ebpf`
     *
     * 失败（网络/格式/自定义源没有 update.json）时返回带 error 的结果，
     * 由调用方决定是回退到「平铺地址」下载还是提示用户。
     */
    fun checkBinaryUpdate(baseUrl: String? = null): BinaryUpdateInfo {
        val base = resolveBase(baseUrl)
        cleartextError(base)?.let { return BinaryUpdateInfo(error = it) }
        return try {
            val text = httpGetText("$base/$UPDATE_JSON", timeoutMs = 15_000)
            val json = gson.fromJson(text, UpdateJson::class.java)
            if (json?.version.isNullOrBlank() || json?.baseUrl.isNullOrBlank()) {
                return BinaryUpdateInfo(error = "update.json 缺少 version/baseUrl")
            }
            val downloadBase = normalizeBase(json.baseUrl)
            BinaryUpdateInfo(
                latestVersion = json.version,
                versionCode = json.versionCode,
                downloadUrl = "$downloadBase/${json.version}/$BIN_NAME-android-${abiName()}-with-ebpf",
                changelogUrl = json.changelog ?: "",
            )
        } catch (e: Exception) {
            Log.w(TAG, "checkBinaryUpdate: ${e.message}")
            BinaryUpdateInfo(error = e.message ?: "检查更新失败")
        }
    }

    private data class UpdateJson(
        val version: String = "",
        val versionCode: Int = 0,
        val baseUrl: String = "",
        val changelog: String = "",
    )

    /** 下载源规范化：空 → 官方地址；去掉末尾斜杠 */
    private fun normalizeBase(url: String?): String =
        (if (url.isNullOrBlank()) DEFAULT_DOWNLOAD_BASE else url).trimEnd('/')

    /**
     * Android 9(API 28) 起默认禁止明文 HTTP（真机实测：http 源会报
     * "Cleartext HTTP traffic to x.x.x.x not permitted"）。
     * 这里提前给出可读提示，避免把平台错误直接甩给用户。
     * 需要在局域网内用 http 源时，得在 Manifest 打开 usesCleartextTraffic（安全性取舍，默认不开）。
     */
    private fun cleartextError(base: String): String? =
        if (base.startsWith("http://")) "下载源必须是 https（Android 禁止明文 HTTP）" else null

    /**
     * 解析下载源，优先级：通道参数 > 设置页写的偏好 > 官方地址。
     *
     * 为什么在这里统一解析：设置页把「自定义下载源」存在 Flutter 的 SharedPreferences 里
     * （flutter.ebpfDownloadBase），如果让 Dart 每个调用点自己传，很容易漏传（实测踩到过：
     * 设置里改了源、下载却仍走官方地址）。放在原生统一读取后，通道参数只作为覆盖/测试用。
     */
    private fun resolveBase(override: String?): String {
        if (!override.isNullOrBlank()) return normalizeBase(override)
        val fromPrefs = try {
            context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
                .getString(KEY_DOWNLOAD_BASE, "")
        } catch (e: Exception) {
            null
        }
        return normalizeBase(fromPrefs)
    }

    /** 发一个 GET 并把响应体按 UTF-8 读成字符串（用于 update.json） */
    private fun httpGetText(url: String, timeoutMs: Int): String {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = timeoutMs
            readTimeout = timeoutMs
            instanceFollowRedirects = true
            requestMethod = "GET"
        }
        try {
            val code = conn.responseCode
            if (code != HttpURLConnection.HTTP_OK) throw EbpfException("HTTP $code")
            return conn.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
        } finally {
            conn.disconnect()
        }
    }

    // ---------------------------------------------------------------- 下载
    //
    // 【概念：为什么这里会有"下载一个可执行文件"这种事】
    // eBPF 的拦截逻辑必须跑在内核里，而"怎么拦、拦哪些 app、转发到哪个代理"这套策略，
    // 是 sing-box 用 Go 实现并以可执行文件形式提供的（编译标签 with_ebpf）。
    // 所以 app 的角色是：把对应 CPU 架构的二进制拉下来 → 用 root 起进程 → 剩下的交给它。
    // APK 里不放这个文件（4 个 ABI 加起来 ~43MB），改为按当前设备的 ABI 下载并缓存在
    // app 私有目录（filesDir/ebpf/sing-box-<abi>）。
    //
    // 【概念：断点续传（HTTP Range）】
    // 下载 9.5MB 在移动网络下可能中断。HTTP 允许"只取文件的某一段"：
    //   请求头 Range: bytes=<已下载字节>-  → 服务端返回 206 Partial Content（只回剩下的部分）
    // 于是我们保留上次没下完的 .tmp，下次从断点继续写；若服务端不支持（返回 200 而不是 206），
    // 就丢掉 .tmp 的重下。是否支持是服务端行为，本实现只在实测确认后依赖它（本项目的源支持）。
    //
    // 【概念：为什么校验 ELF 魔数】
    // 下载源返回的内容可能是错误页/被劫持的 HTML（HTTP 也可能返回 200）。ELF 是 Linux
    // 可执行文件格式，开头固定两字节 0x7F 'E'；用它挡住"看起来下载成功、其实是网页"的情况。
    // 大小阈值（>5MB）是第二道保险（正常二进制 9.5MB 左右）。

    /**
     * 下载 / 续传 sing-box 二进制到 app 私有目录。失败抛 [EbpfException]。
     *
     * 地址解析顺序（兼容两种下载源布局）：
     *   1) `{base}/update.json` → `{baseUrl}/{version}/sing-box-android-{abi}-with-ebpf`（版本化目录，推荐）
     *   2) update.json 不可用时回退「平铺地址」`{base}/sing-box-android-{abi}-with-ebpf`（旧布局）
     *
     * 三个阶段的失败语义（很重要，UI 文案是按这个写的）：
     *   - 下载中断：**保留** `.tmp` → 用户再点一次就是"继续下载"
     *   - 下载完整但不是 ELF：丢弃 `.tmp`（内容本身是错的，续传没意义）
     *   - 保存失败：抛错（磁盘等环境问题）
     *
     * @param baseUrl 自定义下载源，留空则用设置页里存的（再退到官方地址），见 [resolveBase]
     * @param onProgress 0..100（长度未知时 -1）
     */
    fun downloadBinary(baseUrl: String? = null, onProgress: ((Int) -> Unit)? = null): BinaryStatus {
        val base = resolveBase(baseUrl)
        cleartextError(base)?.let { throw EbpfException(it) }
        ensureBinDir()
        val target = binaryFile()
        val tmp = File(binDir, target.name + ".tmp")

        // 1) 解析版本与地址
        val update = checkBinaryUpdate(base)
        val url = if (update.error.isEmpty() && update.downloadUrl.isNotEmpty()) {
            update.downloadUrl
        } else {
            Log.w(TAG, "downloadBinary: update.json 不可用（${update.error}），回退平铺地址")
            "$base/$BIN_NAME-android-${abiName()}-with-ebpf"
        }
        Log.d(TAG, "downloadBinary: url=$url")

        // 2) 下载（有 .tmp 就尝试续传）
        val existing = if (tmp.exists()) tmp.length() else 0L
        var conn: HttpURLConnection? = null
        try {
            conn = openForDownload(url, existing)
            var code = conn.responseCode
            var appending = existing > 0 && code == HttpURLConnection.HTTP_PARTIAL
            if (existing > 0 && !appending) {
                // 服务端不支持 Range（或 .tmp 与远端不一致）→ 丢弃重下
                Log.w(TAG, "downloadBinary: 服务端返回 $code，放弃续传")
                tmp.delete()
                conn.disconnect()
                conn = openForDownload(url, 0)
                code = conn.responseCode
            }
            if (code != HttpURLConnection.HTTP_OK && code != HttpURLConnection.HTTP_PARTIAL) {
                throw EbpfException("下载失败: HTTP $code")
            }
            val contentLength = conn.contentLengthLong
            val total = if (appending && contentLength > 0) existing + contentLength else contentLength
            var downloaded = if (appending) existing else 0L
            var lastPercent = if (total > 0) ((downloaded * 100) / total).toInt() else -1
            onProgress?.invoke(lastPercent)
            conn.inputStream.use { input ->
                FileOutputStream(tmp, appending).use { output ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n <= 0) break
                        output.write(buf, 0, n)
                        downloaded += n
                        val percent = if (total > 0) ((downloaded * 100) / total).toInt() else -1
                        if (percent != lastPercent) {
                            lastPercent = percent
                            onProgress?.invoke(percent)
                        }
                    }
                }
            }
        } catch (e: EbpfException) {
            throw e // 保留 .tmp 供续传
        } catch (e: Exception) {
            throw EbpfException("下载中断: ${e.message}（已保留进度，可再点一次续传）")
        } finally {
            conn?.disconnect()
        }

        // 3) 校验：不完整 → 保留 .tmp 续传；不是 ELF → 丢弃
        if (tmp.length() < MIN_BINARY_SIZE) {
            throw EbpfException("下载不完整（${tmp.length()} 字节），可再点一次续传")
        }
        val head = ByteArray(2)
        tmp.inputStream().use { it.read(head) }
        if (head[0].toInt() and 0xFF != ELF_MAGIC_0 || head[1].toInt() and 0xFF != ELF_MAGIC_1) {
            tmp.delete()
            throw EbpfException("下载文件不是 ELF 可执行文件（已丢弃）")
        }
        if (target.exists()) target.delete()
        if (!tmp.renameTo(target)) {
            throw EbpfException("保存二进制失败")
        }

        // 4) 记录来源版本（用于「有新版本」判断）
        if (update.error.isEmpty()) {
            val support = readSupport()
            writeSupport(support.copy(
                binaryPackageVersion = update.latestVersion,
                binaryVersionCode = update.versionCode,
                binaryChangelogUrl = update.changelogUrl,
            ))
        }
        Log.d(TAG, "downloadBinary: ok ${target.absolutePath} (${target.length()} bytes)")
        return getBinaryStatus()
    }

    /** 打开下载连接；[existing] > 0 时带 Range 头请求续传 */
    private fun openForDownload(url: String, existing: Long): HttpURLConnection {
        return (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 60_000
            instanceFollowRedirects = true
            requestMethod = "GET"
            if (existing > 0) setRequestProperty("Range", "bytes=$existing-")
        }
    }

    // ---------------------------------------------------------------- 支持检测

    /**
     * 支持检测 —— 回答「这台设备能不能跑 eBPF 透明代理」，并把结论存下来。
     *
     * ── 为什么需要"检测"这一步 ────────────────────────────────────────────────
     * eBPF 不是所有 Android 设备都支持：它依赖内核编译时打开的若干能力（BPF 子系统、
     * cgroup v2 的 socket-address 钩子或 TC 分类器、以及一批 map 类型/helper 函数）。
     * 厂商内核可能裁掉其中一部分 —— 表现就是"启动看着起来了，但流量一点没被接管"。
     * sing-box 提供了 `tools ebpf status` 子命令做**无副作用预检**（只加载/校验，不挂钩子、
     * 不改路由/队列），我们据此在启动前就把结论和原因算出来给用户看。
     *
     * 为什么分两次探测：local 接管有两种数据面（cgroup / tc），它们依赖的内核能力不同 ——
     * 有的设备 cgroup 挂不上但 tc 可以。分别记录后，设置页就能按实际情况引导用户切换。
     *
     * ── 流程 ─────────────────────────────────────────────────────────────────
     *   1. 没有 root → 直接判 no_root（eBPF 必须 root 才能挂钩子/读包名表）
     *   2. 二进制不存在 → autoDownload=false 时记 not_ready；=true 时先下载再继续
     *   3. 实测运行目录（见 resolveRunDir：能不能 exec 是设备相关的）
     *   4. 跑两次 `tools ebpf status`（cgroup / tc），解析出「是否支持 + 失败原因」
     *   5. 结论写入 support.json
     *
     * 注意：本方法只更新「检测得出的字段」，一律用 `readSupport().copy(...)` 增量写回 ——
     * 直接用新对象会清掉别的字段（下载来源版本 binaryPackageVersion、wasRunning 等），
     * 表现就是「点一次检测，当前版本就变成 ?」。
     *
     * @param autoDownload 二进制缺失时是否自动下载（设置页「检测」= true；App 启动时的静默重测 = false）
     */
    fun checkSupport(autoDownload: Boolean = true, downloadBase: String? = null, onProgress: ((Int) -> Unit)? = null): SupportStatus {
        if (!isRootAvailable()) {
            val status = readSupport().copy(root = false, result = "no_root", checkedAt = System.currentTimeMillis())
            writeSupport(status)
            return status
        }

        if (!binaryFile().exists()) {
            if (!autoDownload) {
                val status = readSupport().copy(root = true, binaryReady = false, result = "not_ready", checkedAt = System.currentTimeMillis())
                writeSupport(status)
                return status
            }
            downloadBinary(downloadBase, onProgress)
        }

        val runDir = resolveRunDir()
        val version = runRoot("$runDir/$BIN_NAME version").lineSequence().firstOrNull { it.contains("sing-box version") }
            ?.removePrefix("sing-box version")?.trim() ?: ""

        val cgroup = probePlane(runDir, "cgroup")
        val tc = probePlane(runDir, "tc")

        val supported = cgroup.passed || tc.passed
        val status = readSupport().copy(
            root = true,
            binaryReady = true,
            supported = supported,
            cgroup = cgroup.passed,
            tc = tc.passed,
            runtimeDir = runDir,
            kernelRelease = cgroup.kernelRelease.ifEmpty { tc.kernelRelease },
            binaryVersion = version,
            checkedAt = System.currentTimeMillis(),
            result = when {
                supported -> "preflight_passed"
                cgroup.result == "inconclusive" || tc.result == "inconclusive" -> "inconclusive"
                else -> "unsupported"
            },
            cgroupReasons = cgroup.reasons,
            tcReasons = tc.reasons,
        )
        Log.d(TAG, "checkSupport: $status")
        writeSupport(status)
        return status
    }

    private data class PlaneProbe(val passed: Boolean, val result: String, val kernelRelease: String, val reasons: List<String>)

    /** 探测单个数据面：`tools ebpf status --mode local --local-data-plane <plane> --json` */
    private fun probePlane(runDir: String, plane: String): PlaneProbe {
        val cmd = "$runDir/$BIN_NAME tools ebpf status --mode local --local-data-plane $plane --network tcp,udp --json"
        val result = Shell.cmd(cmd).exec()
        val probe = try {
            parseProbe(result.out.joinToString("\n"))
        } catch (e: Exception) {
            Log.w(TAG, "probePlane($plane) parse failed: ${e.message}")
            PlaneProbe(false, "unsupported", "", listOf("检测输出无法解析: ${e.message}"))
        }
        // 命令本身失败（没有 JSON 输出）时，把 stderr 首行当作原因
        if (!probe.passed && probe.reasons.isEmpty()) {
            return probe.copy(reasons = listOf(result.err.firstOrNull() ?: "未通过（退出码非 0）"))
        }
        return probe
    }

    /**
     * 解析 `tools ebpf status --json` 的输出（字段来自 sing-ebpf 的 kernelProbeJSONReport）。
     *
     * 判定规则（重要，别改成「看有没有 FAIL」）：
     *   result == "preflight_passed" → 支持
     *   result == "unsupported"      → required 项有失败
     *   result == "inconclusive"     → required 项无法判定（UNKNOWN）
     * 失败原因取 findings[] 里 importance == "required" 且 status != "PASS" 的 feature/detail。
     */
    private fun parseProbe(json: String): PlaneProbe {
        val obj = JsonParser.parseString(json.trim()).asJsonObject
        val result = obj.get("result")?.asString ?: "unsupported"
        val kernel = obj.get("kernel_release")?.asString ?: ""
        val passed = result == "preflight_passed"
        val reasons = ArrayList<String>()
        if (!passed) {
            val findings = obj.getAsJsonArray("findings")
            findings?.forEach { element ->
                val f = element.asJsonObject
                val importance = f.get("importance")?.asString ?: ""
                val status = f.get("status")?.asString ?: ""
                if (importance == "required" && status != "PASS") {
                    val feature = f.get("feature")?.asString ?: ""
                    val detail = f.get("detail")?.asString ?: ""
                    reasons.add(if (detail.isEmpty()) feature else "$feature — $detail")
                }
            }
        }
        return PlaneProbe(passed, result, kernel, reasons.take(5))
    }

    /**
     * 运行目录探测：优先 app 私有目录（POC 实测 KernelSU 下可直接 exec），
     * 不可执行时回退 /data/local/tmp/appproxy。结果缓存到 support.json。
     */
    /**
     * 解析运行目录（**实测决定**，并把结果缓存到 support.json）。
     *
     * 为什么需要"实测"：Android 上能不能 exec 取决于 SELinux/noexec，
     * app 私有目录在多数设备可用（真机验证：KernelSU 下可以），个别机型只能用 /data/local/tmp。
     * 判据不是"文件存在"，而是**真的跑一次 `<bin> version` 有输出**。
     *
     * 顺序：缓存命中 → filesDir/ebpf/run → /data/local/tmp/appproxy → 都失败就抛错（不静默降级）
     */
    private fun resolveRunDir(): String {
        val cached = readSupport().runtimeDir
        if (cached.isNotEmpty()) {
            val dir = File(cached)
            if (dir.exists() && File(dir, BIN_NAME).exists()) return cached
        }
        val candidates = listOf(File(binDir, "run"), File(FALLBACK_RUN_DIR))
        for (dir in candidates) {
            try {
                if (deployBinary(dir) && runRoot("${dir.absolutePath}/$BIN_NAME version").contains("sing-box version")) {
                    Log.d(TAG, "resolveRunDir: use ${dir.absolutePath}")
                    return dir.absolutePath
                }
            } catch (e: Exception) {
                Log.w(TAG, "resolveRunDir: ${dir.absolutePath} failed: ${e.message}")
            }
        }
        throw EbpfException("运行目录不可用（app 私有目录与 $FALLBACK_RUN_DIR 均无法执行）")
    }

    /**
     * 把二进制部署到运行目录（root 执行）。
     *
     * 用 `cp` 而不是软链：sing-box 需要在**可执行目录**里跑（同目录还会放 config/日志/pid），
     * 而且 700 只给 root，避免其它应用读到带凭据的 config.json 所在目录。
     */
    private fun deployBinary(runDir: File): Boolean {
        val src = binaryFile()
        if (!src.exists()) throw EbpfException("二进制不存在，请先下载")
        val cmd = buildString {
            append("mkdir -p ").append(shq(runDir.absolutePath)).append("; ")
            append("cp -f ").append(shq(src.absolutePath)).append(" ").append(shq("${runDir.absolutePath}/$BIN_NAME")).append("; ")
            append("chmod 700 ").append(shq("${runDir.absolutePath}/$BIN_NAME"))
        }
        return Shell.cmd(cmd).exec().isSuccess
    }

    // ---------------------------------------------------------------- 启动 / 停止
    //
    // 【概念：什么叫"接管"】
    // sing-box 起来以后做的事，用内核的话说是"挂钩子（attach）"：
    //   - 往 cgroup v2 层级上挂 connect/UDP 程序（cgroup 数据面），或
    //   - 往默认网卡上挂 TC 分类器（tc 数据面）
    // 被挂上钩子的进程发起连接时，内核会把连接"改写"成指向 sing-box 自己监听的地址，
    // 于是流量就进了 sing-box 的路由流程，最终从我们配置的 outbounds（那个 http/socks 代理）出去。
    //
    // 反过来，**停止时必须让 sing-box 优雅退出**（SIGTERM），它才会把这些钩子摘掉；
    // 直接 SIGKILL 可能在内核里留下残留状态（下次启动时 sing-box 会有"恢复"逻辑兜底，
    // 但干净退出才是正途）。所以 stopInternal 的策略是：先 TERM → 等 5s → 实在不走才 KILL。
    //
    // 【概念：为什么进程要"绑在 app 身上"】
    // 需求是"app 被划掉/强杀，代理就停"。若用 setsid 把 sing-box 变成独立会话，它会活过 app，
    // 就违背这个语义。所以：sing-box 留在 app 的进程组里（app 进程组被杀时它一起死），
    // 只在"app 被单进程 SIGKILL、来不及连带子进程"这种极端情况下，由看门狗补一刀。

    /**
     * 启动 sing-box。
     *
     * 前置条件：本机检测通过（support.supported == true，否则直接抛错，不静默降级到 VPN）。
     * 成功判据：日志出现 `eBPF inbound started`（见步骤 5），返回时的进程已真正在接管流量。
     *
     * 步骤（每一步都写清"为什么"）：
     *   1. 停旧实例 — 避免与上一次的附着/进程冲突
     *   2. 落盘 config.json — root 复制到运行目录并 600（含代理凭据）
     *   3. 日志轮转 + 清 pid — 保证本次的启动判据只看本次日志
     *   4. root 起进程 — 不 setsid（要留在 app 进程组，app 死了它也要死）
     *   5. 等启动成功 — 看日志标记，而不是"进程活着"
     *   6. 起看门狗 — 兜底 app 被单进程 SIGKILL（LMK）后留下的孤儿
     *
     * @param configJson 已生成好的 config.json 内容（UI 路径由 Dart 生成，MCP 路径由 EbpfConfigBuilder 生成）
     * @param onProgress 阶段回调：starting / started（供 UI 显示进度）
     */
    fun start(configJson: String, onProgress: ((String) -> Unit)? = null): RunStatus {
        val support = readSupport()
        if (!support.supported) throw EbpfException("当前设备未通过 eBPF 检测（${support.result}）")
        val runDirPath = support.runtimeDir.ifEmpty { resolveRunDir() }
        val runDir = File(runDirPath)
        if (!runDir.exists()) deployBinary(runDir)

        // 1) 先停掉可能存在的旧进程，避免端口/附着冲突
        stopInternal(runDir)

        // 2) 落盘 config.json：app 私有临时文件 → root 复制到运行目录（600，含代理凭据）
        ensureBinDir()
        val tmpConfig = File(binDir, "$CONFIG_NAME.new")
        tmpConfig.writeText(configJson)
        val deployConfig = Shell.cmd(
            "cp -f ${shq(tmpConfig.absolutePath)} ${shq("$runDirPath/$CONFIG_NAME")}; " +
                "chmod 600 ${shq("$runDirPath/$CONFIG_NAME")}"
        ).exec()
        if (!deployConfig.isSuccess) throw EbpfException("写入 config.json 失败: ${deployConfig.err.firstOrNull() ?: ""}")

        // 3) 日志轮转 + 清理 pid
        Shell.cmd(
            "cd ${shq(runDirPath)}; " +
                "[ -f $LOG_NAME ] && mv -f $LOG_NAME $LOG_NAME.1; " +
                "[ -f $BOX_LOG_NAME ] && mv -f $BOX_LOG_NAME $BOX_LOG_NAME.1; " +
                "rm -f $PID_NAME"
        ).exec()

        // 4) 启动（不 setsid：留在 app 进程组内，app 被强杀时一起死）
        onProgress?.invoke("starting")
        val launch = Shell.cmd(
            "cd ${shq(runDirPath)}; " +
                "./$BIN_NAME run -c $CONFIG_NAME > $LOG_NAME 2>&1 & " +
                "echo \$! > $PID_NAME"
        ).exec()
        if (!launch.isSuccess) throw EbpfException("启动命令失败: ${launch.err.firstOrNull() ?: ""}")

        // 5) 等待启动成功：判据是日志出现 "eBPF inbound started"（POC 实测 0.1~0.3s），
        //    不看进程是否存在 —— 内核能力不足时进程可能活着但没接管成功
        val deadline = System.currentTimeMillis() + START_TIMEOUT_MS
        var started = false
        while (System.currentTimeMillis() < deadline) {
            Thread.sleep(300)
            val pid = readPid(runDir)
            if (pid <= 0 || !isPidAlive(pid)) break
            if (logContains(runDir, "eBPF inbound started")) {
                started = true
                break
            }
        }
        if (!started) {
            val tail = readLog(runDir, 4_000)
            stopInternal(runDir)
            throw EbpfException("sing-box 启动失败:\n${tail.takeLast(1200)}")
        }

        // 6) 看门狗兜底（只在 app 被「单进程」杀掉时起作用）：
        //    - 正常路径：app 被划掉/强停 → killProcessGroup 连 sing-box 一起杀，看门狗也会随即消失；
        //    - 兜底路径：app 被 LMK 单进程 SIGKILL → sing-box 成孤儿，看门狗 2s 内发现 app pid 不存在并 TERM 掉它。
        //    看门狗自己用 setsid 脱离进程组，否则它会和 app 一起被杀、失去兜底意义。
        val appPid = android.os.Process.myPid()
        val watchdog = "while kill -0 $appPid 2>/dev/null; do sleep 2; done; kill -TERM \$(cat $runDirPath/$PID_NAME) 2>/dev/null"
        Shell.cmd(
            "if command -v setsid >/dev/null 2>&1; then " +
                "setsid sh -c ${shq(watchdog)} >/dev/null 2>&1 </dev/null & " +
                "else sh -c ${shq(watchdog)} >/dev/null 2>&1 </dev/null & fi"
        ).exec()

        onProgress?.invoke("started")
        setRunningFlag(true)
        return status()
    }

    /** 停止 eBPF 引擎；成功则清掉 wasRunning 标记（返回是否已停） */
    fun stop(): Boolean {
        val runDir = File(readSupport().runtimeDir.ifEmpty { FALLBACK_RUN_DIR })
        val stopped = stopInternal(runDir)
        if (stopped) setRunningFlag(false)
        return stopped
    }

    /**
     * 幂等停止：SIGTERM → 最多等 5s → SIGKILL；随后清理 pid 文件。
     *
     * 先 TERM 是因为 sing-box 要优雅退出才会归还内核状态（cgroup 程序随进程退出由内核回收，
     * TC filter 则由 sing-box 自己清理）；只有超时才用 -KILL。
     */
    private fun stopInternal(runDir: File): Boolean {
        val pid = readPid(runDir)
        if (pid <= 0) {
            File(runDir, PID_NAME).delete()
            return true
        }
        Shell.cmd("kill -TERM $pid 2>/dev/null").exec()
        val deadline = System.currentTimeMillis() + STOP_TIMEOUT_MS
        while (System.currentTimeMillis() < deadline) {
            if (!isPidAlive(pid)) break
            Thread.sleep(200)
        }
        if (isPidAlive(pid)) {
            Log.w(TAG, "stopInternal: SIGTERM 超时，改用 SIGKILL (pid=$pid)")
            Shell.cmd("kill -KILL $pid 2>/dev/null").exec()
            Thread.sleep(300)
        }
        Shell.cmd("rm -f ${shq("${runDir.absolutePath}/$PID_NAME")}").exec()
        return !isPidAlive(pid)
    }

    /** App 启动时清理孤儿进程：生命周期绑定 app，不做「恢复运行态」 */
    fun cleanupOrphan(): Boolean {
        val runDir = File(readSupport().runtimeDir.ifEmpty { FALLBACK_RUN_DIR })
        val pid = readPid(runDir)
        if (pid > 0 && isPidAlive(pid)) {
            Log.w(TAG, "cleanupOrphan: 发现残留 sing-box (pid=$pid)，停止它")
            val stopped = stopInternal(runDir)
            if (stopped) setRunningFlag(false)
            return stopped
        }
        File(runDir, PID_NAME).delete()
        setRunningFlag(false)
        return true
    }

    /** 只有上次会话标记为运行中时才需要在冷启动做孤儿检查（避免每次启动都调 su） */
    fun needsOrphanCheck(): Boolean {
        val support = readSupport()
        return support.wasRunning && support.runtimeDir.isNotEmpty()
    }

    /** 更新 support.json 里的 wasRunning（冷启动孤儿检查靠它，避免每次都调 su） */
    private fun setRunningFlag(running: Boolean) {
        val support = readSupport()
        if (support.wasRunning == running) return
        writeSupport(support.copy(wasRunning = running))
    }

    /** 当前运行状态：读 pid 文件 + kill -0 验证进程是否还活着 */
    fun status(): RunStatus {
        val runDirPath = readSupport().runtimeDir.ifEmpty { FALLBACK_RUN_DIR }
        val runDir = File(runDirPath)
        val pid = readPid(runDir)
        val running = pid > 0 && isPidAlive(pid)
        return RunStatus(running, if (running) pid else -1, runDirPath)
    }

    // ---------------------------------------------------------------- 日志 / 清理

    /**
     * 读日志尾部（经 root 读取：运行目录是 root 700，app 自己进不去）。
     *
     * 两个文件分工不同（POC 实测：sing-box.log 通常为 0 字节，内容在 box.log）：
     *   box.log      —— config.json 里 log.output 指定的结构化日志（eBPF 启动摘要在这里）
     *   sing-box.log —— 启动命令的 stdout/stderr 重定向（崩溃/报错多半在这里）
     * 两个都读并拼接，谁有内容就看得到谁。
     */
    fun readLog(runDir: File, maxBytes: Int = 32 * 1024): String {
        val boxLog = runRootTail(File(runDir, BOX_LOG_NAME).absolutePath, maxBytes / 2)
        val stdLog = runRootTail(File(runDir, LOG_NAME).absolutePath, maxBytes / 2)
        return when {
            stdLog.isBlank() -> boxLog
            boxLog.isBlank() -> stdLog
            else -> "$boxLog\n--- stdout/stderr ---\n$stdLog"
        }
    }

    /** 启动成功判据：任一日志文件里出现标记字符串 */
    private fun logContains(runDir: File, marker: String): Boolean {
        val a = File(runDir, BOX_LOG_NAME).absolutePath
        val b = File(runDir, LOG_NAME).absolutePath
        val cmd = "grep -qF ${shq(marker)} ${shq(a)} 2>/dev/null || grep -qF ${shq(marker)} ${shq(b)} 2>/dev/null"
        return Shell.cmd(cmd).exec().isSuccess
    }

    /** 读日志尾部（两个日志文件拼接，经 root 读取，见方法内注释） */
    fun readLog(maxBytes: Int = 32 * 1024): String =
        readLog(File(readSupport().runtimeDir.ifEmpty { FALLBACK_RUN_DIR }), maxBytes)

    /** 清理运行目录（日志/pid/config/二进制副本），保留已下载的二进制 */
    fun cleanupRuntimeDir(): Boolean {
        val runDir = readSupport().runtimeDir.ifEmpty { FALLBACK_RUN_DIR }
        stopInternal(File(runDir))
        setRunningFlag(false)
        return Shell.cmd("rm -rf ${shq(runDir)}").exec().isSuccess
    }

    // ---------------------------------------------------------------- 内部工具

    private fun readPid(runDir: File): Long {
        val out = runRoot("cat ${shq("${runDir.absolutePath}/$PID_NAME")} 2>/dev/null").trim()
        return out.toLongOrNull() ?: -1
    }

    private fun isPidAlive(pid: Long): Boolean {
        if (pid <= 0) return false
        return Shell.cmd("kill -0 $pid 2>/dev/null").exec().isSuccess
    }

    /** 以 root 执行并返回 stdout（失败返回空串） */
    private fun runRoot(command: String): String = try {
        val result = Shell.cmd(command).exec()
        result.out.joinToString("\n")
    } catch (e: Exception) {
        Log.w(TAG, "runRoot failed: ${e.message}")
        ""
    }

    /** 以 root 读取文件尾部 N 字节（日志查看用；运行目录是 root 700，app 自己读不了） */
    private fun runRootTail(path: String, maxBytes: Int): String = try {
        val result = Shell.cmd("tail -c $maxBytes ${shq(path)} 2>/dev/null").exec()
        result.out.joinToString("\n")
    } catch (e: Exception) {
        Log.w(TAG, "runRootTail failed: ${e.message}")
        ""
    }

    /** 单引号转义，避免路径/参数注入 */
    private fun shq(s: String): String = "'" + s.replace("'", "'\\''") + "'"

    private fun readSupport(): SupportStatus = try {
        if (!supportFile.exists()) SupportStatus() else gson.fromJson(supportFile.readText(), SupportStatus::class.java) ?: SupportStatus()
    } catch (e: Exception) {
        Log.w(TAG, "readSupport: ${e.message}")
        SupportStatus()
    }

    private fun writeSupport(status: SupportStatus) {
        try {
            ensureBinDir()
            supportFile.writeText(gson.toJson(status))
        } catch (e: Exception) {
            Log.w(TAG, "writeSupport: ${e.message}")
        }
    }
}
