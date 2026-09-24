package cn.ys1231.appproxy.EbpfService

import android.content.Context
import com.google.gson.Gson
import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.google.gson.reflect.TypeToken

/**
 * MCP 路径用的 config.json 生成器（Kotlin 侧）。
 *
 * 为什么这里又有一份生成逻辑：config.json 由 **Dart 侧生成**（见 lib/data/ebpf_config_generator.dart），
 * 那条路径走 Flutter UI；而 MCP 是原生直接被调用、不经过 Dart，所以这里需要等价实现。
 * **两边的映射规则必须保持一致**：
 *
 *   outbounds[0].type        ← proxyType：http → http；socks5 → socks（并写 version=5）
 *   outbounds[0].server      ← proxyHost
 *   outbounds[0].server_port ← proxyPort
 *   username / password      ← proxyUser / proxyPass（为空则整字段省略）
 *   local.include_package    ← appProxyPackageList（为空则省略 ⇒ 全局接管）
 *   local.exclude_package    ← 本应用包名
 *   local.data_plane         ← 参数 > 设置页(SharedPreferences) > cgroup
 *
 * 注意 log.output 用相对路径 `box.log`：原生启动时会先 `cd <运行目录>`。
 */
object EbpfConfigBuilder {

    private val gson = Gson()

    /** MCP 用的 Flutter SharedPreferences 名（Flutter 侧会加 `flutter.` 前缀） */
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val KEY_DATA_PLANE = "flutter.ebpfDataPlane"

    /** 生成 config.json（MCP 路径用）：outbounds 跟随入参，inbounds 与 Dart 侧保持同一套规则 */
    fun build(context: Context, config: Map<String, Any?>, dataPlaneOverride: String? = null): String {
        val proxyType = (config["proxyType"] ?: "socks5").toString().lowercase()
        val isHttp = proxyType == "http"

        val outbound = JsonObject().apply {
            addProperty("type", if (isHttp) "http" else "socks")
            addProperty("tag", if (isHttp) "http-out" else "socks-out")
            addProperty("server", (config["proxyHost"] ?: "").toString())
            addProperty("server_port", (config["proxyPort"] ?: "0").toString().toIntOrNull() ?: 0)
            if (!isHttp) addProperty("version", "5")
            val user = (config["proxyUser"] ?: "").toString()
            val pass = (config["proxyPass"] ?: "").toString()
            if (user.isNotEmpty()) addProperty("username", user)
            if (pass.isNotEmpty()) addProperty("password", pass)
        }

        val local = JsonObject().apply {
            addProperty("enabled", true)
            addProperty("data_plane", resolveDataPlane(context, dataPlaneOverride))
            addProperty("dns_mode", "respect_policy")
            addProperty("ipv6", true)
            addProperty("bypass_private_address", true)
            val packages = packageListOf(config["appProxyPackageList"])
            if (packages.isNotEmpty()) {
                add("include_package", JsonArray().apply { packages.forEach { add(it) } })
            }
            add("exclude_package", JsonArray().apply { add(context.packageName) })
        }

        val inbound = JsonObject().apply {
            addProperty("type", "ebpf")
            addProperty("tag", "ebpf-in")
            add("network", JsonArray().apply { add("tcp"); add("udp") })
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

        val root = JsonObject().apply {
            add("log", log)
            add("inbounds", JsonArray().apply { add(inbound) })
            add("outbounds", JsonArray().apply { add(outbound) })
        }
        return gson.toJson(root)
    }

    /** 通知栏用的摘要，如 `socks5 192.168.0.27:8080` */
    fun summaryOf(config: Map<String, Any?>): String {
        val type = (config["proxyType"] ?: "").toString()
        val host = (config["proxyHost"] ?: "").toString()
        val port = (config["proxyPort"] ?: "").toString()
        return "$type $host:$port"
    }

    /** 数据面优先级：显式参数 > 设置页里存的值 > cgroup（默认，已实测） */
    private fun resolveDataPlane(context: Context, override: String?): String {
        if (!override.isNullOrBlank()) return override
        return try {
            context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
                .getString(KEY_DATA_PLANE, "cgroup") ?: "cgroup"
        } catch (e: Exception) {
            "cgroup"
        }
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
