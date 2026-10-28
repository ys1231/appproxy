package cn.ys1231.appproxy.EbpfService

import android.content.Context
import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.google.gson.reflect.TypeToken

/**
 * MCP 路径用的 config.json 生成器（Kotlin 侧）。
 *
 * 为什么这里又有一份生成逻辑：config.json 由 **Dart 侧生成**（见 lib/data/ebpf_config_generator.dart），
 * 那条路径走 Flutter UI；而 MCP 是原生直接被调用、不经过 Dart，所以这里需要等价实现。
 * **两边的映射规则必须保持一致**（改规则时两边一起改）：
 *
 *   outbounds[0].type        ← proxyType：http → http；socks5 → socks（并写 version=5）
 *   outbounds[0].server      ← proxyHost（trim 后必须非空）
 *   outbounds[0].server_port ← proxyPort（1-65535 的整数）
 *   username / password      ← proxyUser / proxyPass（为空则整字段省略）
 *   inbounds[0].network      ← ebpfNetwork：all/tcp/udp（缺省 all，即 tcp+udp）
 *   inbounds[0].local.data_plane ← ebpfDataPlane：cgroup / socket_assign（缺省按本机检测能力）
 *   inbounds[0].local.dns_mode   ← 固定 hijack（端口 53 的查询交给 route 的 hijack-dns）
 *   local.include_package    ← appProxyPackageList（为空则省略 ⇒ 全局接管）
 *   local.exclude_package    ← 本应用包名
 *   dns/route                ← 固定策略：DoH(经代理) + 端口53 → hijack-dns（不作为用户选项）
 *
 * 校验规则：proxyType 仅支持 http/socks5；host 不能为空；port 必须 1-65535；
 * ebpfNetwork / ebpfDataPlane 非法值直接抛异常（不做静默映射，避免"配错了却以为生效"）。
 * 仅 `tc` → `socket_assign` 是唯一的兼容映射（sing-box 1.15 起旧数据面被移除，不保留别名）。
 *
 * 注意 log.output 用相对路径 `box.log`：原生启动时会先 `cd <运行目录>`。
 */
object EbpfConfigBuilder {

    private const val TAG = "iyue->EbpfConfigBuilder"
    private val gson = Gson()
    /** 与 Dart 侧 `JsonEncoder.withIndent('  ')` 保持同样的两空格缩进，便于比对/排查 */
    private val prettyGson = Gson().newBuilder()
        .disableHtmlEscaping() // Dart 不转义 & ' < > =，这里保持一致（账号密码可能含这些字符）
        .setPrettyPrinting()
        .create()

    private val VALID_TYPES = setOf("http", "socks5")
    private val VALID_NETWORKS = setOf("all", "tcp", "udp")
    private val VALID_DATA_PLANES = setOf("cgroup", "socket_assign")

    /** 生成 config.json（MCP 路径用）：outbounds 跟随入参，inbounds 与 Dart 侧保持同一套规则 */
    fun build(context: Context, config: Map<String, Any?>): String {
        // ---- 入参校验（失败抛异常，由调用方转成可读错误，不做静默降级）----
        // proxyType 缺失/null/空串一律报错（与 Dart 侧一致）：不再默默按 socks5 处理，
        // 否则调用方少传一个字段就会得到一份"看起来正常、实际协议不对"的配置。
        val proxyType = (config["proxyType"] ?: "").toString().trim().lowercase()
        require(proxyType.isNotEmpty()) {
            "代理类型不能为空（仅支持 http / socks5）"
        }
        require(proxyType in VALID_TYPES) {
            "不支持的代理类型: $proxyType（仅支持 http / socks5）"
        }
        val isHttp = proxyType == "http"

        val host = (config["proxyHost"] ?: "").toString().trim()
        require(host.isNotEmpty()) { "代理地址不能为空" }

        val portText = (config["proxyPort"] ?: "").toString().trim()
        val port = portText.toIntOrNull()?.takeIf { it in 1..65535 }
            ?: throw IllegalArgumentException("代理端口无效: $portText（应为 1-65535）")

        // ---- 可调项（与 Dart 侧规则保持一致）----
        // network: all = TCP+UDP（默认）/ tcp = 仅 TCP / udp = 仅 UDP
        val networkMode = (config["ebpfNetwork"] ?: "").toString().trim().lowercase()
            .ifEmpty { "all" }
        require(networkMode in VALID_NETWORKS) {
            "ebpfNetwork 无效: $networkMode（仅支持 all / tcp / udp）"
        }
        val tcpEnabled = networkMode != "udp"
        val udpEnabled = networkMode != "tcp"
        if (isHttp && udpEnabled) {
            // http 出站没有原生 UDP：UDP/QUIC 会被封装成 MASQUE(CONNECT-UDP)，上游不支持即 404。
            // 保留用户显式选择的 udp 捕获，但在 route 里 reject（见下方规则），让 UDP 快速失败。
            Log.w(TAG, "build: http 代理配置了 network=$networkMode，UDP 将在路由层被 reject（上游不支持 UDP）")
        }
        Log.d(TAG, "build: network=$networkMode (tcp=$tcpEnabled udp=$udpEnabled)")

        val dataPlane = resolveDataPlane(context, (config["ebpfDataPlane"] ?: "").toString())

        val outboundTag = if (isHttp) "http-out" else "socks-out"
        val outbound = JsonObject().apply {
            addProperty("type", if (isHttp) "http" else "socks")
            addProperty("tag", outboundTag)
            addProperty("server", host)
            // server_port 必须是数字（字符串会被 sing-box 判为类型错误）
            addProperty("server_port", port)
            if (!isHttp) addProperty("version", "5")
            val user = (config["proxyUser"] ?: "").toString()
            val pass = (config["proxyPass"] ?: "").toString()
            if (user.isNotEmpty()) addProperty("username", user)
            if (pass.isNotEmpty()) addProperty("password", pass)
        }

        val local = JsonObject().apply {
            addProperty("enabled", true)
            addProperty("data_plane", dataPlane)
            // 端口 53 的查询统一进入路由，由 route.rules 的 hijack-dns 交给 DNS 模块
            addProperty("dns_mode", "hijack")
            addProperty("ipv6", true)
            addProperty("bypass_private_address", true)
            val packages = packageListOf(config["appProxyPackageList"])
                .map { it.trim() }
                .filter { it.isNotEmpty() }
            if (packages.isNotEmpty()) {
                add("include_package", JsonArray().apply { packages.forEach { add(it) } })
            }
            add("exclude_package", JsonArray().apply { add(context.packageName) })
        }

        val inbound = JsonObject().apply {
            addProperty("type", "ebpf")
            addProperty("tag", "ebpf-in")
            add("network", JsonArray().apply {
                if (tcpEnabled) add("tcp")
                if (udpEnabled) add("udp")
            })
            addProperty("udp_timeout", "5m")
            addProperty("tc_priority", 1)
            addProperty("fakeip_icmp", "off")
            add("local", local)
        }

        val log = JsonObject().apply {
            addProperty("disabled", false)
            addProperty("level", "debug")
            addProperty("output", "box.log")
            addProperty("timestamp", true)
        }

        // DNS 由 sing-box 统一处理（**不作为用户选项**），与 Dart 侧完全一致：
        //   dns-boot  —— 明文 UDP，仅用于路由解析域名（default_domain_resolver），不走代理；
        //   dns-ali / dns-dnspod —— DoH，detour 指向上游出站（经代理）；
        //   dns-group —— 把上面两个 DoH 组成并发组，作为 final 解析业务域名。
        // 若没有 hijack-dns 规则，端口 53 会被当作普通 UDP 交给 outbound，http 出站下即 404 风暴。
        val dns = JsonObject().apply {
            add("servers", JsonArray().apply {
                add(JsonObject().apply {
                    addProperty("tag", "dns-boot")
                    addProperty("type", "udp")
                    addProperty("server", "223.5.5.5")
                })
                add(dohServer("dns-ali", "dns.alidns.com", outboundTag))
                add(dohServer("dns-dnspod", "doh.pub", outboundTag))
                add(JsonObject().apply {
                    addProperty("tag", "dns-group")
                    addProperty("type", "group")
                    add("servers", JsonArray().apply {
                        add("dns-ali")
                        add("dns-dnspod")
                    })
                })
            })
            addProperty("final", "dns-group")
            // 经代理转发时 IPv6 常不可达（实测 socks5 出现 [2001::1]:443 EOF）
            addProperty("strategy", "ipv4_only")
        }
        val route = JsonObject().apply {
            // 路由阶段解析域名时用直连 DNS，避免为「解析 DoH 服务器域名」再走代理形成死循环
            addProperty("default_domain_resolver", "dns-boot")
            add("rules", JsonArray().apply {
                // 端口 53（被接管的 TCP/UDP DNS）交给 DNS 模块应答
                add(JsonObject().apply {
                    addProperty("port", 53)
                    addProperty("action", "hijack-dns")
                })
                // 不接管 IPv6 目的地（dns.strategy 已限定 ipv4_only，这里再兜底防泄漏）
                add(JsonObject().apply {
                    add("ip_cidr", JsonArray().apply { add("::/0") })
                    addProperty("action", "reject")
                })
                // http 出站不支持 UDP：用户显式开启 udp 捕获时，在路由层直接 reject（快速失败，
                // 避免 MASQUE 封装后上游 404 风暴）。socks5 有原生 UDP ASSOCIATE，不加此规则。
                if (isHttp && udpEnabled) {
                    add(JsonObject().apply {
                        add("network", JsonArray().apply { add("udp") })
                        addProperty("action", "reject")
                    })
                }
            })
            addProperty("final", outboundTag)
        }

        val root = JsonObject().apply {
            add("log", log)
            add("dns", dns)
            add("route", route)
            add("inbounds", JsonArray().apply { add(inbound) })
            add("outbounds", JsonArray().apply { add(outbound) })
        }
        val json = prettyGson.toJson(root)
        Log.d(
            TAG,
            "build: 配置生成完成 type=$proxyType network=$networkMode dataPlane=$dataPlane " +
                "dnsFinal=dns-group routeFinal=$outboundTag 长度=${json.length}"
        )
        return json
    }

    /** 单个 DoH 服务器（sing-box 1.12+ 新格式：type + server，旧 address 写法已移除） */
    private fun dohServer(tag: String, host: String, detour: String): JsonObject = JsonObject().apply {
        addProperty("tag", tag)
        addProperty("type", "https")
        addProperty("server", host)
        addProperty("detour", detour)
    }

    /** 通知栏用的摘要，如 `socks5 192.168.0.27:8080` */
    fun summaryOf(config: Map<String, Any?>): String {
        val type = (config["proxyType"] ?: "").toString()
        val host = (config["proxyHost"] ?: "").toString()
        val port = (config["proxyPort"] ?: "").toString()
        return "$type $host:$port"
    }

    /**
     * 数据面解析：
     *   - 显式配置：cgroup / socket_assign 原样使用；旧值 tc → socket_assign（唯一兼容映射）；
     *     其它值抛异常（不静默回落到默认值，否则用户以为切换生效了）。
     *   - 未配置（空）：按本机检测能力选择，优先 cgroup，其次 socket_assign，都没有则 cgroup（默认）。
     *
     * 注意：显式配置与检测能力冲突时不在生成阶段纠正，统一由 [EbpfProxyManager.start] 做
     * 双向回退（socket_assign ↔ cgroup），保证 UI 路径（Dart 生成）与 MCP 路径行为一致。
     */
    private fun resolveDataPlane(context: Context, raw: String): String {
        val value = raw.trim().lowercase()
        if (value.isEmpty()) {
            val support = try {
                EbpfProxyManager.get(context.applicationContext).getSupportStatus()
            } catch (e: Exception) {
                Log.w(TAG, "resolveDataPlane: 读检测缓存失败: ${e.message}")
                null
            }
            val plane = when {
                support?.cgroup == true -> "cgroup"
                support?.socketAssign == true -> "socket_assign"
                else -> "cgroup"
            }
            Log.d(
                TAG,
                "resolveDataPlane: 未配置，按检测能力选择 $plane " +
                    "(cgroup=${support?.cgroup} socket_assign=${support?.socketAssign})"
            )
            return plane
        }
        if (value == "tc") {
            // sing-box 1.15 起旧 tc 必须改为 socket_assign（不保留别名），直接替换
            Log.w(TAG, "resolveDataPlane: 旧数据面 tc 已废弃，改用 socket_assign")
            return "socket_assign"
        }
        require(value in VALID_DATA_PLANES) {
            "ebpfDataPlane 无效: $value（仅支持 cgroup / socket_assign）"
        }
        return value
    }

    /** 兼容两种入参：List<String>（MCP 路径）与 JSON 字符串（Flutter 路径） */
    private fun packageListOf(value: Any?): List<String> = when (value) {
        null -> emptyList()
        is List<*> -> value.mapNotNull { it?.toString() }
        is String -> try {
            gson.fromJson<List<String>>(value, object : TypeToken<List<String>>() {}.type) ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
        else -> emptyList()
    }
}
