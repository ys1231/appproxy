package cn.ys1231.appproxy.EbpfService

import android.content.Context
import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonArray
import com.google.gson.JsonElement
import com.google.gson.JsonObject
import com.google.gson.JsonParser
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
 *   inbounds[0].local.dns_mode   ← ebpfDnsMode：空 → respect_policy（只接管被监听 app 的 DNS）；
 *                                  hijack = 全机 DNS；off = 不接管
 *   local.include_package    ← appProxyPackageList（为空则省略 ⇒ 全局接管）
 *   local.exclude_package    ← 本应用包名
 *   dns / route / local 其余项 ← 由 EbpfAdvancedOptions 从 ebpf* 键驱动
 *     （ebpfDnsServers/ebpfDnsStrategy/ebpfDnsRoute/ebpfIpv6/ebpfBypassPrivate/
 *     ebpfUdpTimeout/ebpfBypassPorts/ebpfHttpUdpAction/ebpfCustomJson）
 *
 * 【贯穿原则：不写进配置 = sing-box 默认值生效】只写用户显式选择的值；
 * sing-box 默认就合理的字段（ipv6=true、bypass_private=true、udp_timeout=5m）一律不写。
 *
 * 校验规则：proxyType 仅支持 http/socks5；host 不能为空；port 必须 1-65535；
 * ebpfNetwork / ebpfDataPlane / 高级选项非法值直接抛异常（不做静默映射，避免"配错了却以为生效"）。
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

    /** 生成 config.json（MCP 路径用）：outbounds 跟随入参，inbounds/dns/route 与 Dart 侧保持同一套规则 */
    fun build(context: Context, config: Map<String, Any?>): String {
        // ---- 入参校验（失败抛异常，由调用方转成可读错误，不做静默降级）----
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

        // ---- 接管网络：空/缺省 = all；仅接受 all / tcp / udp ----
        val networkMode = (config["ebpfNetwork"] ?: "").toString().trim().lowercase()
            .ifEmpty { "all" }
        require(networkMode in VALID_NETWORKS) {
            "ebpfNetwork 无效: $networkMode（仅支持 all / tcp / udp）"
        }
        val tcpEnabled = networkMode != "udp"
        val udpEnabled = networkMode != "tcp"
        Log.d(TAG, "build: network=$networkMode (tcp=$tcpEnabled udp=$udpEnabled)")

        val dataPlane = resolveDataPlane(context, (config["ebpfDataPlane"] ?: "").toString())

        // ---- 高级选项：统一从 ebpf* 键解析（非法值已回落默认）----
        val opts = EbpfAdvancedOptions.fromConfig(config)
        // 自定义 JSON 覆盖先解析一次：非法直接报错，不生成"以为生效了"的配置
        val customOverride = try {
            opts.parseCustomOverride()
        } catch (e: Exception) {
            throw IllegalArgumentException("ebpfCustomJson 非法: ${e.message}")
        }
        Log.d(
            TAG,
            "build: dnsMode=${opts.effectiveDnsMode()} dnsServers=${opts.dnsServers.size} " +
                "customOverride=${customOverride != null}"
        )

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
            // 默认 respect_policy：先过包名筛选，只有被监听 app 的 53 端口查询进 sing-box
            addProperty("dns_mode", opts.effectiveDnsMode())
            // 可选字段（ipv6/bypass_private/bypass_port*）：不写 = sing-box 默认
            opts.buildLocalExtras().forEach { (k, v) -> add(k, v) }
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
            // 只有非默认 udp_timeout 才写（默认 5m 由 sing-box 自己决定）
            opts.buildInboundExtras().forEach { (k, v) -> add(k, v) }
            add("local", local)
        }

        val log = JsonObject().apply {
            addProperty("disabled", false)
            addProperty("level", "debug")
            addProperty("output", "box.log")
            addProperty("timestamp", true)
        }

        // route/dns 由选项模型驱动：默认 respect_policy + 系统 DNS 应答，
        // 不再有全局 IPv6 reject 与固定双 DoH（那是旧版的固化行为）。
        val dns = opts.buildDnsSection(outboundTag)
        val route = JsonObject().apply {
            opts.buildRouteExtras(outboundTag).forEach { (k, v) -> add(k, v) }
            add("rules", JsonArray().apply {
                opts.buildRouteRules(isHttp, udpEnabled, outboundTag).forEach { add(it) }
            })
            addProperty("final", outboundTag)
        }

        val root = JsonObject().apply {
            add("log", log)
            // dns 段在 off 模式下整个省略（sing-box 兜底 local 供自身解析）
            if (dns != null) add("dns", dns)
            add("route", route)
            add("inbounds", JsonArray().apply { add(inbound) })
            add("outbounds", JsonArray().apply { add(outbound) })
        }

        // 自定义 JSON 覆盖：最后一步深度合并，用户显式写的字段优先级最高
        val finalRoot = if (customOverride != null) {
            Log.d(TAG, "build: 合并自定义 JSON 覆盖 (${customOverride.keySet().joinToString()})")
            deepMerge(root, customOverride)
        } else {
            root
        }

        val json = prettyGson.toJson(finalRoot)
        Log.d(
            TAG,
            "build: 配置生成完成 type=$proxyType network=$networkMode dataPlane=$dataPlane " +
                "dnsMode=${opts.effectiveDnsMode()} routeFinal=$outboundTag 长度=${json.length}"
        )
        return json
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

    /** 深度合并：override 的 JsonObject 递归合并，其余（含数组、标量）直接覆盖 */
    private fun deepMerge(base: JsonObject, override: JsonObject): JsonObject {
        val out = base.deepCopy()
        for ((key, value) in override.entrySet()) {
            val old = out.get(key)
            if (old is JsonObject && value is JsonObject) {
                out.add(key, deepMerge(old, value))
            } else {
                out.add(key, value)
            }
        }
        return out
    }

    /**
     * eBPF 高级选项（Kotlin 侧，与 Dart lib/data/ebpf_options.dart 规则一致）。
     *
     * 存储键与 Dart 完全相同（同一份 proxyConfig.json）；所有"空 = 自动"语义一致：
     * 只写用户显式选择的值，sing-box 默认就合理的字段一律不写。
     */
    class EbpfAdvancedOptions(
        var dnsMode: String = "",
        val dnsServers: MutableList<DnsServer> = mutableListOf(),
        var dnsStrategy: String = "",
        var dnsRoute: String = "",
        var ipv6: String = "",
        var bypassPrivate: String = "",
        var udpTimeout: String = "",
        val bypassPorts: MutableList<String> = mutableListOf(),
        var httpUdpAction: String = "",
        var customJson: String = "",
    ) {
        class DnsServer(val type: String, val server: String, val detour: String)

        /** 空 → respect_policy（sing-box 默认，先包名筛选再接管 53） */
        fun effectiveDnsMode(): String = dnsMode.ifEmpty { "respect_policy" }

        /** 是否接管 53 端口（off = DNS 留在内核直连，不进 sing-box） */
        fun capturesDns(): Boolean = effectiveDnsMode() != "off"

        /** local 块的可选字段（不写 = sing-box 默认 true/5m） */
        fun buildLocalExtras(): Map<String, JsonElement> {
            val out = mutableMapOf<String, JsonElement>()
            if (ipv6 == "off") out["ipv6"] = gson.toJsonTree(false)
            if (bypassPrivate == "off") out["bypass_private_address"] = gson.toJsonTree(false)
            if (bypassPorts.isNotEmpty()) {
                val singles = JsonArray()
                val ranges = JsonArray()
                for (p in bypassPorts) {
                    if (p.contains('-')) ranges.add(p) else singles.add(p.toInt())
                }
                if (singles.size() > 0) out["bypass_port"] = singles
                if (ranges.size() > 0) out["bypass_port_range"] = ranges
            }
            return out
        }

        /** inbound 的可选字段：只有非默认 udp_timeout 才写 */
        fun buildInboundExtras(): Map<String, JsonElement> =
            if (udpTimeout.isNotEmpty()) mapOf("udp_timeout" to gson.toJsonTree(udpTimeout))
            else emptyMap()

        /**
         * dns 段。返回 null = 不写 dns 段（dns_mode=off）：
         * sing-box 兜底仍会自动创建 local 传输供自身解析（box.go defaultTransportFallback）。
         */
        fun buildDnsSection(outboundTag: String): JsonObject? {
            if (!capturesDns()) return null
            val servers = JsonArray()
            if (dnsServers.isEmpty()) {
                // 默认档：系统 DNS 应答。不写 detour = 直连系统解析器（不经代理、零额外请求）。
                // 标签固定 dns-local（route.default_domain_resolver 引用它）
                servers.add(JsonObject().apply {
                    addProperty("tag", "dns-local")
                    addProperty("type", "local")
                })
                return JsonObject().apply {
                    add("servers", servers)
                    addProperty("final", "dns-local")
                    if (dnsStrategy.isNotEmpty()) addProperty("strategy", dnsStrategy)
                }
            }
            // 兜底：需要 local 解析器（dnsRoute=proxy 或经代理的 DoH/DoT/DoQ）但用户没选
            // local 时自动补一台，保证 default_domain_resolver 的 dns-local 引用有目标
            val effective = if (hasLocalResolver() || !needsLocalResolverBootstrap()) {
                dnsServers
            } else {
                dnsServers + DnsServer("local", "", "direct")
            }
            val groupMembers = JsonArray()
            effective.forEachIndexed { i, srv ->
                val tag = if (srv.type == "local") "dns-local" else "dns-$i"
                servers.add(JsonObject().apply {
                    addProperty("tag", tag)
                    addProperty("type", srv.type)
                    if (srv.type != "local") addProperty("server", srv.server)
                    if (srv.detour == "proxy") addProperty("detour", outboundTag)
                })
                groupMembers.add(tag)
            }
            if (servers.size() > 1) {
                servers.add(JsonObject().apply {
                    addProperty("tag", "dns-group")
                    addProperty("type", "group")
                    add("servers", groupMembers)
                })
            }
            return JsonObject().apply {
                add("servers", servers)
                addProperty(
                    "final",
                    if (effective.size > 1) "dns-group"
                    else servers.get(0).asJsonObject.get("tag").asString
                )
                if (dnsStrategy.isNotEmpty()) addProperty("strategy", dnsStrategy)
            }
        }

        /** 是否需要保证 dns 段里有 local 服务器（buildRouteExtras 恒引用 dns-local） */
        private fun needsLocalResolverBootstrap(): Boolean =
            capturesDns() && (dnsRoute == "proxy" || hasProxiedDomainServer())

        /**
         * route.rules 中由本模型决定的部分：DNS 劫持规则（仅 hijack）与
         * http+UDP 的 reject/masque 规则（off 模式下豁免 53，不接管就不误杀直连 DNS）。
         */
        fun buildRouteRules(isHttp: Boolean, capturesUdp: Boolean, outboundTag: String): List<JsonObject> {
            val rules = mutableListOf<JsonObject>()
            if (effectiveDnsMode() == "hijack") {
                rules.add(JsonObject().apply {
                    addProperty("port", 53)
                    addProperty("action", "hijack-dns")
                })
            }
            if (isHttp && capturesUdp) {
                // http 出站没有原生 UDP：默认 reject（快速失败，避免 MASQUE 404 风暴）；
                // masque = 显式路由给上游出站，尝试 CONNECT-UDP（用户显式选择即接受 404 风险）。
                // dns_mode=off 时 DNS 是内核直连流量（也走 eBPF UDP），必须豁免 53。
                rules.add(JsonObject().apply {
                    add("network", JsonArray().apply { add("udp") })
                    if (httpUdpAction == "masque") {
                        addProperty("action", "route")
                        addProperty("outbound", outboundTag)
                    } else {
                        addProperty("action", "reject")
                    }
                    if (!capturesDns()) {
                        add("port_range", JsonArray().apply {
                            add("54:65535")
                            add("1:52")
                        })
                    }
                })
            }
            return rules
        }

        /**
         * route.default_domain_resolver：sing-box 自身解析域名时（经代理的 DoH 服务器域名、
         * "经代理"的 DNS 路由）用哪台 DNS、走哪个出站。
         *
         */
        fun buildRouteExtras(outboundTag: String): Map<String, JsonElement> {
            // dns-local 标签由 buildDnsSection 保证存在（需要时自动补 local），恒可引用
            val needsBootstrap = dnsRoute == "proxy" || hasProxiedDomainServer()
            if (!needsBootstrap) return emptyMap()
            val resolver = JsonObject().apply { addProperty("server", "dns-local") }
            if (dnsRoute == "proxy") resolver.addProperty("detour", outboundTag)
            return mapOf("default_domain_resolver" to resolver)
        }

        private fun hasProxiedDomainServer(): Boolean = dnsServers.any {
            it.detour == "proxy" && (it.type == "https" || it.type == "tls" || it.type == "quic")
        }

        /** 自定义 JSON 覆盖：解析并校验必须是对象；非法抛异常（调用方包成可读错误） */
        fun parseCustomOverride(): JsonObject? {
            val raw = customJson.trim()
            if (raw.isEmpty()) return null
            val parsed = JsonParser.parseString(raw)
            require(parsed.isJsonObject) { "自定义 JSON 覆盖必须是对象（{...}）" }
            return parsed.asJsonObject
        }

        private fun hasLocalResolver(): Boolean =
            dnsServers.isEmpty() || dnsServers.any { it.type == "local" }

        companion object {
            private val VALID_DNS_MODES = setOf("respect_policy", "hijack", "off")
            private val VALID_DNS_STRATEGIES = setOf("ipv4_only", "ipv6_only", "prefer_ipv4")
            private val VALID_DNS_TYPES = setOf("https", "tls", "quic", "udp", "local")
            private val VALID_UDP_TIMEOUTS = setOf("30s", "1m", "5m", "10m")
            private val PORT_OR_RANGE = Regex("""^\d{1,5}(-\d{1,5})?$""")

            /** 从 MCP 入参解析（非法值一律回落自动，与 Dart fromProxyConfig 一致） */
            fun fromConfig(config: Map<String, Any?>): EbpfAdvancedOptions {
                fun str(key: String) = (config[key] ?: "").toString().trim()
                fun clean(key: String, valid: Set<String>): String {
                    val v = str(key).lowercase()
                    return if (v in valid) v else ""
                }

                val servers = mutableListOf<DnsServer>()
                val rawServers = str("ebpfDnsServers")
                if (rawServers.isNotEmpty()) {
                    try {
                        val arr = JsonParser.parseString(rawServers).asJsonArray
                        for (item in arr) {
                            if (!item.isJsonObject) continue
                            val o = item.asJsonObject
                            val type = o.get("type")?.asString?.trim()?.lowercase() ?: continue
                            if (type !in VALID_DNS_TYPES) continue
                            val server = o.get("server")?.asString?.trim() ?: ""
                            if (type != "local" && server.isEmpty()) continue
                            val detour = o.get("detour")?.asString?.trim()?.lowercase() ?: ""
                            servers.add(
                                DnsServer(
                                    type,
                                    server,
                                    if (detour == "proxy") "proxy" else "direct"
                                )
                            )
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "EbpfAdvancedOptions: ebpfDnsServers 解析失败: ${e.message}")
                    }
                }

                val ports = mutableListOf<String>()
                val rawPorts = str("ebpfBypassPorts")
                if (rawPorts.isNotEmpty()) {
                    try {
                        val arr = JsonParser.parseString(rawPorts).asJsonArray
                        for (item in arr) {
                            val p = item.asString.trim()
                            if (p.matches(PORT_OR_RANGE)) ports.add(p)
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "EbpfAdvancedOptions: ebpfBypassPorts 解析失败: ${e.message}")
                    }
                }

                return EbpfAdvancedOptions(
                    dnsMode = clean("ebpfDnsMode", VALID_DNS_MODES),
                    dnsServers = servers,
                    dnsStrategy = clean("ebpfDnsStrategy", VALID_DNS_STRATEGIES),
                    dnsRoute = clean("ebpfDnsRoute", setOf("proxy")),
                    ipv6 = clean("ebpfIpv6", setOf("off")),
                    bypassPrivate = clean("ebpfBypassPrivate", setOf("off")),
                    udpTimeout = clean("ebpfUdpTimeout", VALID_UDP_TIMEOUTS),
                    bypassPorts = ports,
                    httpUdpAction = clean("ebpfHttpUdpAction", setOf("masque")),
                    customJson = str("ebpfCustomJson"),
                )
            }
        }
    }
}
