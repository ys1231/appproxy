package cn.ys1231.appproxy.mcpserver

import android.annotation.SuppressLint
import android.content.Context
import android.net.VpnService
import cn.ys1231.appproxy.EbpfService.EbpfProxyController
import cn.ys1231.appproxy.IyueService.VpnServiceController
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.install
import io.ktor.server.auth.authenticate
import io.ktor.server.auth.bearer
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.plugins.cors.routing.CORS
import io.ktor.server.routing.delete
import io.ktor.server.routing.post
import io.ktor.server.routing.route
import io.ktor.server.routing.routing
import io.ktor.server.sse.SSE
import io.ktor.server.sse.sse
import io.modelcontextprotocol.kotlin.sdk.types.McpJson
import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.google.gson.reflect.TypeToken
import java.io.File
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.application.ApplicationCall
import io.ktor.server.auth.Authentication
import io.ktor.server.auth.UserIdPrincipal
import io.ktor.server.engine.EmbeddedServer
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.netty.NettyApplicationEngine
import io.ktor.server.request.header
import io.ktor.server.response.respond
import io.modelcontextprotocol.kotlin.sdk.server.Server
import io.modelcontextprotocol.kotlin.sdk.server.ServerOptions
import io.modelcontextprotocol.kotlin.sdk.types.Implementation
import io.modelcontextprotocol.kotlin.sdk.types.ServerCapabilities
import io.ktor.util.collections.ConcurrentMap
import io.modelcontextprotocol.kotlin.sdk.server.StreamableHttpServerTransport
import io.modelcontextprotocol.kotlin.sdk.types.CallToolResult
import io.modelcontextprotocol.kotlin.sdk.types.GetPromptResult
import io.modelcontextprotocol.kotlin.sdk.types.PromptMessage
import io.modelcontextprotocol.kotlin.sdk.types.Role
import io.modelcontextprotocol.kotlin.sdk.types.TextContent
import io.modelcontextprotocol.kotlin.sdk.types.ToolSchema
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject


/**
 * MCP 服务端（单例）。
 *
 * ─────────────────────────────────────────────────────────────────────────
 * 【它是干什么的】
 * 用 Ktor + MCP Kotlin SDK 起一个 HTTP 服务（默认 `0.0.0.0:12345/mcp`，Bearer 鉴权），
 * 把外部 MCP 客户端（Claude 等）的工具调用转成对本机代理引擎的操作：
 *
 *     MCP 客户端 ──HTTP/JSON-RPC──> 本类注册的 tools/list、tools/call
 *                                    ├─ tun2socks 引擎 → VpnServiceController → IyueVPNService
 *                                    └─ eBPF 引擎      → EbpfProxyController  → EbpfProxyManager(root 起 sing-box)
 *
 * 「引擎」由调用方通过 `proxyEngine` 参数选择（默认 tun2socks）；两个引擎互斥，
 * 同一时刻只会有一个在跑（见 anyEngineRunning）。
 *
 * 【两个容易踩的点】
 *   1. `startMcpServer()` / `stopMcpServer()` 是**进程内启停**：Ktor 的绑定是异步的，
 *      旧实现既不校验绑定结果、也不等旧实例释放，导致"显示已启动却连不上"（详见 fix(mcp) 那个提交）。
 *      改动这里要连带验证：关→开循环、改端口、划掉任务卡片后再打开。
 *   2. 工具回调里若做耗时/root 操作（eBPF 的 getStatus 会跑 `kill -0`），
 *      注意它会占住 Ktor 的请求线程。
 * ─────────────────────────────────────────────────────────────────────────
 */
class MCPServer private constructor(
    val context: Context,
) {
    companion object {
        @Volatile
        private var instance: MCPServer? = null

        /** 取单例（双检锁）：全局只有一份服务端状态（鉴权 token、端口、nettyServer） */
        fun getInstance(context: Context): MCPServer {
            return instance ?: synchronized(this) {
                instance ?: MCPServer(context).also {
                    instance = it
                }
            }
        }

        /** 丢弃单例：先停服务再置空，避免留下还在监听的旧实例 */
        fun resetInstance() {
            instance?.stopMcpServer()
            instance = null
        }
    }

    private val TAG = "iyue->${this.javaClass.simpleName}"

    /** tun2socks(VPN) 引擎的入口，由 MainActivity 在绑定 IyueVPNService 成功后注入 */
    private var vpnController: VpnServiceController? = null

    /**
     * eBPF(sing-box) 引擎控制器。
     * 工具调用里传 `proxyEngine = "ebpf"` 时走它；不传/传 tun2socks 时行为与原来完全一致。
     */
    private val ebpfController: EbpfProxyController by lazy { EbpfProxyController(context) }

    /** 当前是否有引擎在运行（两个引擎互斥，用于「已在运行」判断） */
    private fun anyEngineRunning(): Boolean {
        // 两个引擎各自探测，任何一个抛异常都当作"没在跑"，不影响另一个的判断
        val vpn = try { vpnController?.getVpnStatus() == true } catch (e: Exception) { false }
        val ebpf = try { ebpfController.getStatus() } catch (e: Exception) { false }
        return vpn || ebpf
    }

    /** MCP 会话头：客户端在 initialize 之后，后续请求都要带上它 */
    private val MCP_SESSION_ID_HEADER = "mcp-session-id"

    /** 鉴权 token（Bearer）。用 getter/setter 只为在变更时打日志，便于排查客户端 401 */
    private var _authToken: String = ""
    private var authToken: String
        get() = _authToken
        set(value) {
            _authToken = value
            Log.d(TAG, "MCP auth token changed to $value")
        }

    /** 监听端口（默认 12345）。同上，setter 打日志 */
    private var _mcpPort: Int = 0
    private var mcpPort: Int
        get() = _mcpPort
        set(value) {
            _mcpPort = value
            Log.d(TAG, "MCP server port changed to $value")
        }

    /** 注入 VPN 引擎控制器（MainActivity 在服务连接成功后调用） */
    fun setVpnController(vpnController: VpnServiceController?) {
        this.vpnController = vpnController
        Log.d(TAG, "setVpnController: ${vpnController.toString()}")
    }

    private var nettyServer: EmbeddedServer<NettyApplicationEngine, NettyApplicationEngine.Configuration>? = null

    /**
     * 启动 MCP 服务（进程内启停，注意开头类注释里的两个坑）。
     *
     * 绑定是**异步**的（`start(wait=false)` 立刻返回，真正的 bind 在后台完成），
     * 所以这里的日志只代表"已发起启动"，不代表端口已经可连 —— 调用方要判断可用性，
     * 应实际发一个请求（见 fix(mcp) 提交里讨论过的自检思路）。
     */
    fun startMcpServer() {
        nettyServer = embeddedServer(Netty, host = "0.0.0.0", port = mcpPort) {
            configureServer()
        }
        nettyServer?.start(wait = false)
        Log.d(TAG, "MCP server started on port $mcpPort")
    }

    /** 停止 MCP 服务：先停引擎再置空引用（幂等，未启动时调用也安全） */
    fun stopMcpServer() {
        if (nettyServer != null) {
            nettyServer?.stop()
        }
        Log.d(TAG, "MCP server stopped")
        nettyServer = null
    }

    /** 改端口：仅当端口真的变了、且服务在跑时才重启（端口没变就不要白白抖一次） */
    fun updateMcpPort(port: Int?) {
        if (port != null && port != mcpPort) {
            mcpPort = port
            if (nettyServer != null) {
                nettyServer?.stop()
                Log.d(TAG, "Restart MCP Server port $mcpPort")
                startMcpServer()
            }
        }
    }

    /** 改鉴权 token：同 updateMcpPort，仅在值变化且服务在跑时重启（否则老客户端会 401） */
    fun updateMcpAuth(auth: String?) {
        if (auth != null && auth != authToken) {
            authToken = auth
            if (nettyServer != null) {
                nettyServer?.stop()
                Log.d(TAG, "Restart MCP Server auth $authToken")
                startMcpServer()
            }
        }
    }

    /** Ktor 应用装配：跨域 → JSON 序列化（用 MCP 自己的 McpJson）→ 鉴权与路由 */
    fun Application.configureServer() {
        // 安装 CORS 跨域支持，如果启用了认证则需要配置
        installCors(authEnabled = true)
        // 安装内容协商插件，使用 MCP 自定义的 JSON 序列化配置
        install(ContentNegotiation) {
            json(McpJson)
        }
        // 需要认证的复杂配置
        configureAuthenticatedMcp(authToken)
    }

    /**
     * 装 SSE 插件、Bearer 鉴权，并注册 MCP 的三个端点。
     *
     * @param authToken 期望的 Bearer token（空串也会装鉴权，即"必须带空 token" ——
     *                  实际使用中由设置页保证了非空默认值 appproxy）
     */
    private fun Application.configureAuthenticatedMcp(authToken: String) {
        // 安装 SSE（Server-Sent Events）支持：GET /mcp 那条长连接要用
        install(SSE)
        install(Authentication) {
            // 定义名为 "mcp-bearer" 的鉴权方案，下面路由用 authenticate("mcp-bearer") 引用
            bearer("mcp-bearer") {
                authenticate { credential ->
                    // 命中则认证通过（principal 名字不重要，只是标识"这个请求来自 mcp 客户端"）；
                    // 不命中返回 null → Ktor 自动回 401，客户端据此知道 token 不对
                    if (credential.token == authToken) {
                        UserIdPrincipal("mcp-client")
                    } else {
                        null
                    }
                }
            }
        }

        // 会话表：sessionId → transport。放在这里（而不是类字段）是因为它属于**某个 Ktor 应用**，
        // 每次 startMcpServer() 都会新建一套，随服务停止一起丢弃
        val transports = ConcurrentMap<String, StreamableHttpServerTransport>()

        routing {
            // 整个 /mcp 子树都要求 Bearer 鉴权（下面三个端点都受此约束）
            authenticate("mcp-bearer") {
                route("/mcp") {
                    // GET：建立 SSE 长连接（服务器主动推消息用）。必须有会话，见下面端点分工说明
                    sse {
                        val transport = findTransport(call, transports) ?: return@sse
                        // 传 this（SSE 会话）进去：SDK 会把这条长连接与该会话的 transport 关联
                        transport.handleRequest(this, call)
                    }

                    // POST：客户端发消息（initialize / tools/call 全走这里）。允许新建会话
                    post {
                        val transport = getOrCreateTransport(call, transports) ?: return@post
                        // 普通消息走这个重载：request 传 null（不用 SSE 推回，用 JSON 响应，见 enableJsonResponse）
                        transport.handleRequest(null, call)
                    }

                    // DELETE：客户端显式结束会话（transport 会从 transports 里移除）
                    delete {
                        val transport = findTransport(call, transports) ?: return@delete
                        transport.handleRequest(null, call)
                    }
                }
            }
        }
    }

    // --- 三个端点的分工（MCP streamable HTTP 规范）---
    //   POST   —— 客户端发消息（含 initialize）。**没有会话就新建**，这是唯一能开新会话的方法
    //   GET    —— 建立 SSE 长连接，服务器用它主动推消息（必须有会话；本项目客户端基本不用）
    //   DELETE —— 显式结束会话
    // 所以：POST 走 getOrCreateTransport（可新建），GET/DELETE 走 findTransport（必须已存在）

    /**
     * 按会话 ID 取**已存在**的传输通道；取不到就直接回响应并返回 null（调用方负责 return）。
     *
     * 为什么区分 400/404：400 = 客户端压根没带会话头（用错方式），404 = 带了但服务端不认识
     * （会话过期/服务重启过）。排查问题时这两种情况含义完全不同，所以没有合并。
     */
    private suspend fun findTransport(
        call: ApplicationCall,
        transports: ConcurrentMap<String, StreamableHttpServerTransport>,
    ): StreamableHttpServerTransport? {
        val sessionId = call.request.header(MCP_SESSION_ID_HEADER)
        if (sessionId.isNullOrEmpty()) {
            call.respond(HttpStatusCode.BadRequest, "Bad Request: No valid session ID provided")
            return null
        }
        val transport = transports[sessionId]
        if (transport == null) {
            call.respond(HttpStatusCode.NotFound, "Session not found")
            return null
        }
        return transport
    }

    /**
     * 取会话对应的传输通道；**没有会话头时创建一个新会话**（POST initialize 走这条）。
     *
     * 一个"会话"= 一个 StreamableHttpServerTransport + 一个 MCP Server 实例：
     *   - 新会话建立后，SDK 会回调 setOnSessionInitialized 把 sessionId 告诉我们，存进 transports
     *   - 会话结束（DELETE 或 server 关闭）时移除，避免 transports 无限增长
     *
     * @param call 当前请求
     * @param transports 会话表（sessionId → transport）
     * @return 可用的 transport；出错时已回响应并返回 null（调用方直接 return）
     */
    private suspend fun getOrCreateTransport(
        call: ApplicationCall,
        transports: ConcurrentMap<String, StreamableHttpServerTransport>,
    ): StreamableHttpServerTransport? {
        val sessionId = call.request.header(MCP_SESSION_ID_HEADER)

        // 带了会话头 = 复用已有会话（找不到就 404，让客户端重新 initialize）
        if (sessionId != null) {
            val transport = transports[sessionId]
            if (transport == null) {
                call.respond(HttpStatusCode.NotFound, "Session not found")
            }
            return transport
        }

        // 没带会话头 = 新会话。enableJsonResponse = 每个请求直接回 JSON，
        // 而不是挂一条 SSE 流（对 Claude 这类"请求-响应"式客户端更简单、也更省连接）
        val configuration = StreamableHttpServerTransport.Configuration(
            enableJsonResponse = true,
        )
        val transport = StreamableHttpServerTransport(configuration)

        // 会话建立后 SDK 才分配 sessionId，所以这里用回调把 transport 登记进表
        transport.setOnSessionInitialized { initializedSessionId ->
            transports[initializedSessionId] = transport
        }
        // 会话关闭：从表里移除（否则内存只涨不降）
        transport.setOnSessionClosed { closedSessionId ->
            transports.remove(closedSessionId)
        }

        // 每个会话一个 Server 实例：工具/提示词的注册在 createMcpServer() 里完成
        val server = createMcpServer()
        // server 被关闭时兜底清理（有些关闭路径不会走 onSessionClosed）
        server.onClose {
            transport.sessionId?.let { transports.remove(it) }
        }
        // 把 transport 与 server 绑起来：之后该会话的请求都会路由到这个 server 的处理逻辑
        server.createSession(transport)

        return transport
    }

    private fun Application.installCors(authEnabled: Boolean = false) {
        // 安装 CORS 插件
        install(CORS) {
            // 允许任何主机访问（生产环境中应该限制具体的域名）
            anyHost() // Don't do this in production if possible. Try to limit it.
            // 允许的 HTTP 方法
            allowMethod(HttpMethod.Options)
            allowMethod(HttpMethod.Get)
            allowMethod(HttpMethod.Post)
            allowMethod(HttpMethod.Delete)
            // 允许非简单的 Content-Type（如 application/json）
            allowNonSimpleContentTypes = true
            // 允许的请求头
            allowHeader("Mcp-Session-Id")      // MCP 会话 ID 头部
            allowHeader("Mcp-Protocol-Version") // MCP 协议版本头部
            // 暴露给浏览器的响应头
            exposeHeader("Mcp-Session-Id")      // 让浏览器可以读取会话 ID
            exposeHeader("Mcp-Protocol-Version") // 让浏览器可以读取协议版本
            // 如果启用了认证，还需要允许 Authorization 头部
            if (authEnabled) {
                allowHeader(HttpHeaders.Authorization)
            }
        }
    }

    /**
     * 从 Flutter 的 proxyConfig.json 读取某条代理配置已保存的 eBPF 可调项。
     *
     * 为什么需要它：MCP 的 update_proxy_config 是「停旧进程 → 用新参数重建配置 → 再启动」，
     * 调用方通常只改地址/账号，不会重复传 ebpfNetwork/ebpfDataPlane。若不继承旧值，
     * 生成器会回落到默认值（例如 http 默认按新规则取 all），接管范围会被悄悄改掉。
     *
     * 文件位置：Dart 的 `getApplicationDocumentsDirectory()` 在 Android 上映射为
     * `context.getDir("flutter", MODE_PRIVATE)`（app_flutter 目录）；这里再兼容 filesDir /
     * dataDir 两种历史布局。文件不存在或解析失败时安静返回 (null, null)。
     *
     * 选择顺序：显式传了 proxyName 时**只按名称精确匹配**，未命中直接不继承（不拿 host/单条
     * 兜底去猜，避免把别的配置的 eBPF 参数套过来）；未传时按 请求里的 host+port 匹配（单条）
     * → 同 host 单条 → 全表仅一条时用它。
     */
    private fun readStoredEbpfOptions(
        proxyName: String?,
        proxyHost: String,
        proxyPort: String,
    ): Pair<String?, String?> {
        val file = proxyConfigFile() ?: return null to null
        return try {
            val entries = JsonParser.parseString(file.readText()).asJsonArray
                .mapNotNull { it as? JsonObject }
            val picked = if (proxyName != null) {
                // 显式指定名称却未命中：直接不继承，不用 host/单条兜底猜测
                entries.firstOrNull { it.stringValue("proxyName") == proxyName } ?: return null to null
            } else {
                entries.filter {
                    it.stringValue("proxyHost") == proxyHost &&
                        it.stringValue("proxyPort") == proxyPort
                }.singleOrNull()
                    ?: entries.filter { it.stringValue("proxyHost") == proxyHost }.singleOrNull()
                    ?: entries.singleOrNull()
            }
            if (picked == null) {
                null to null
            } else {
                picked.stringValue("ebpfNetwork") to picked.stringValue("ebpfDataPlane")
            }
        } catch (e: Exception) {
            Log.w(TAG, "readStoredEbpfOptions: ${e.message}")
            null to null
        }
    }

    /** proxyConfig.json 路径（Flutter 文档目录优先，兼容历史布局）；不存在返回 null */
    private fun proxyConfigFile(): File? = listOf(
        File(context.getDir("flutter", Context.MODE_PRIVATE), "proxyConfig.json"),
        File(context.filesDir, "proxyConfig.json"),
        File(context.dataDir, "proxyConfig.json"),
    ).firstOrNull { it.isFile }

    /** 读 JSON 对象里的字符串字段；缺失/空串/非标量都返回 null */
    private fun JsonObject.stringValue(key: String): String? =
        get(key)?.takeIf { it.isJsonPrimitive }?.asString?.takeIf { it.isNotBlank() }

    /**
     * 日志脱敏：代理账号/密码不允许以明文写入 logcat。
     *
     * 兼容两种入参：MCP 请求参数（JsonObject / Map<String, JsonElement>）与内部 config Map。
     * 只替换这两个键的值，其余字段原样保留，便于排查。
     */
    private fun maskSecrets(args: Map<String, *>?): Map<String, *>? = args?.mapValues { (key, value) ->
        if (key == "proxyUser" || key == "proxyPass") "***" else value
    }

    @SuppressLint("SuspiciousIndentation")
    // ---------------------------------------------------------------- MCP Server（工具 / 提示词注册）
    //
    // 【为什么每个会话都新建一个 Server】
    // SDK 的 Server 承载会话状态（能力协商结果、已注册工具的快照等），复用同一实例会串会话。
    // 实例本身很轻，新建开销可忽略；真正的重活（起代理进程）在工具回调里。
    //
    // 【工具清单（5 个）与共同约定】
    //   start_proxy          启代理（参数：代理地址/类型/账号 + 分应用列表 + 引擎）
    //   stop_proxy           停代理（按"实际在跑的引擎"停，不需要调用方传引擎）
    //   get_proxy_status     查是否在跑
    //   get_proxy_config     查当前配置（含引擎名）
    //   update_proxy_config  改配置并重启（eBPF 引擎下会重建 config.json 再起进程）
    // 约定：① 引擎由参数 proxyEngine 选择，缺省 tun2socks（老客户端行为不变）
    //       ② 两个引擎互斥：任一在跑时 start 都会被拒（返回 "Proxy is already running"）
    //       ③ 参数校验失败一律返回 CallToolResult(isError = true) + 可读原因，不抛异常

    /** 装配一个会话用的 MCP Server：声明能力 + 注册 5 个工具与 1 个提示词 */
    private fun createMcpServer(): Server {
        val server = Server(
            Implementation(
                name = "appproxy-mcp-server",
                version = "1.0.0",
            ),
            ServerOptions(
                capabilities = ServerCapabilities(
                    prompts = ServerCapabilities.Prompts(listChanged = true),
                    tools = ServerCapabilities.Tools(listChanged = true),
                    logging = ServerCapabilities.Logging,
                ),
            ),
        )

        // ----------
        // 启动 proxy
        server.addTool(
            name = "start_proxy",
            description = "Start proxy service with proxy configuration. Example: {proxyHost: '192.168.0.2', proxyPort: '8080', proxyType: 'http', proxyName: 'vpn', proxyUser: '', proxyPass: '', appProxyPackageList: '[\"com.qihoo.contents\", \"com.whatsapp\"]'}",
            inputSchema = ToolSchema(
                properties = buildJsonObject {
                    putJsonObject("proxyName") {
                        put("type", "string")
                        put("description", "Friendly name for this proxy configuration")
                        put("default", "test")
                        put("examples", buildJsonArray {
                            add("vpn")
                            add("Office Proxy")
                            add("Home Network")
                        })
                    }
                    putJsonObject("proxyHost") {
                        put("type", "string")
                        put("description", "Proxy server host address (IP or hostname)")
                        put("default", "192.168.0.2")
                        put("examples", buildJsonArray {
                            add("192.168.0.2")
                            add("www.example.com")
                        })
                    }
                    putJsonObject("proxyPort") {
                        put("type", "string")
                        put("description", "Proxy server port number")
                        put("default", "8080")
                        put("examples", buildJsonArray {
                            add("8080")
                            add("1080")
                        })
                    }
                    putJsonObject("proxyType") {
                        put("type", "string")
                        put("description", "Proxy protocol type")
                        put("default", "http")
                        put("enum", buildJsonArray {
                            add("http")
                            add("socks5")
                        })
                    }
                    putJsonObject("proxyUser") {
                        put("type", "string")
                        put(
                            "description",
                            "Proxy username for authentication (optional, leave empty if not needed)"
                        )
                        put("default", "")
                    }
                    putJsonObject("proxyPass") {
                        put("type", "string")
                        put(
                            "description",
                            "Proxy password for authentication (optional, leave empty if not needed)"
                        )
                        put("default", "")
                    }
                    putJsonObject("appProxyPackageList") {
                        put("type", "string")
                        put(
                            "description",
                            "[\"com.example\", \"com.whatsapp\"] Empty array [] means proxy all apps except this proxy app"
                        )
                        put("default", "[]")
                        put("examples", buildJsonArray {
                            add("[\"com.example\", \"com.whatsapp\"]")
                            add("[\"com.example\"]")
                            add("[]")
                        })
                    }
                    putJsonObject("proxyEngine") {
                        put("type", "string")
                        put(
                            "description",
                            "Proxy engine: 'tun2socks' (default, VpnService) or 'ebpf' (sing-box transparent proxy, requires root and a passed detection on the device)"
                        )
                        put("default", "tun2socks")
                        put("enum", buildJsonArray {
                            add("tun2socks")
                            add("ebpf")
                        })
                    }
                    // ---- 以下仅 eBPF 引擎使用（可选，不传则用默认值）----
                    putJsonObject("ebpfNetwork") {
                        put("type", "string")
                        put(
                            "description",
                            "eBPF only: capture network. Default: 'all' for both; http additionally rejects UDP at route layer. 'tcp' = TCP only (UDP bypasses the proxy), 'udp' = UDP only."
                        )
                        put("enum", buildJsonArray {
                            add("all")
                            add("tcp")
                            add("udp")
                        })
                    }
                    putJsonObject("ebpfDataPlane") {
                        put("type", "string")
                        put(
                            "description",
                            "eBPF only: kernel data plane. 'cgroup' (default) or 'socket_assign' (only if detection reports it supported)"
                        )
                        put("default", "cgroup")
                        put("enum", buildJsonArray {
                            add("cgroup")
                            add("socket_assign")
                        })
                    }
                },
                required = listOf("proxyHost", "proxyPort", "proxyType", "proxyName")
            ),
        ) { request ->
            try {
                // ① 先看有没有引擎在跑：两引擎互斥，重复启动会打架（端口/钩子冲突）
                if (anyEngineRunning()){
                    return@addTool CallToolResult(content = listOf(TextContent("Proxy is already running")), isError = true)
                }
                Log.d(TAG, "start_vpn called with arguments: ${maskSecrets(request.arguments)}")
                // ② 取参数（MCP 参数全按字符串传；缺省值就是文档里写的 default）
                val proxyHost = request.arguments?.get("proxyHost")?.jsonPrimitive?.content ?: ""
                val proxyPort = request.arguments?.get("proxyPort")?.jsonPrimitive?.content ?: ""
                val proxyType =
                    request.arguments?.get("proxyType")?.jsonPrimitive?.content ?: "http"
                val proxyName = request.arguments?.get("proxyName")?.jsonPrimitive?.content ?: "VPN"
                val proxyUser = request.arguments?.get("proxyUser")?.jsonPrimitive?.content ?: ""
                val proxyPass = request.arguments?.get("proxyPass")?.jsonPrimitive?.content ?: ""
                val appListJson =
                    request.arguments?.get("appProxyPackageList")?.jsonPrimitive?.content ?: "[]"

                // ③ 必填校验：名称/地址/端口不能空（账号密码可以为空 = 代理不需要鉴权）
                if (proxyName.isBlank() || proxyHost.isBlank() || proxyPort.isBlank()) {
                    Log.e(TAG, "Error: proxyName or proxyHost or proxyPort are required")
                    return@addTool CallToolResult(
                        content = listOf(
                            TextContent("Error: proxyName or proxyHost or proxyPort are required")
                        ),
                        isError = true
                    )
                }
                // ④ 长度校验：代理账号密码过长通常是"把别的东西粘进来了"，早报错比传到下游再失败好
                if (proxyUser.length > 30 || proxyPass.length > 30) {
                    Log.e(TAG, "Error: proxyUser or proxyPass is too long")
                    return@addTool CallToolResult(
                        content = listOf(
                            TextContent("Error: proxyUser or proxyPass is too long")
                        ),
                        isError = true
                    )
                }
                // ⑤ 分应用列表校验：必须是设备上真实存在的包名
                //    （注意这里借用了 vpnController 的包名表——它由 MainActivity 注入；两个引擎用的是同一份列表）
                val type = object : TypeToken<List<String>>(){}.type
                val appList: List<String> = Gson().fromJson(appListJson, type)
                val packageList = vpnController!!.getPackageList()

                if (!packageList.containsAll(appList)){
                    // 报出具体是哪些包名不合法，便于调用方修正
                    val missingPackages = appList.filter { it !in packageList }
                    Log.e(TAG, "Error: $missingPackages is not valid")
                    return@addTool CallToolResult(
                        content = listOf(
                            TextContent("Error: $missingPackages is not valid")
                        ),
                        isError = true
                    )
                }
                val config = buildMap {
                    put("proxyHost", proxyHost)
                    put("proxyPort", proxyPort)
                    put("proxyType", proxyType)
                    put("proxyName", proxyName)
                    put("proxyUser", proxyUser)
                    put("proxyPass", proxyPass)
                    put("appProxyPackageList", appList)
                    // eBPF 可调项（可选）：不传时由生成器使用默认值；
                    // 与编辑配置页写入 proxyConfig.json 的键保持一致
                    request.arguments?.get("ebpfNetwork")?.jsonPrimitive?.content?.let { put("ebpfNetwork", it) }
                    request.arguments?.get("ebpfDataPlane")?.jsonPrimitive?.content?.let { put("ebpfDataPlane", it) }
                }
                Log.d(TAG, "start_proxy config: ${maskSecrets(config)}")

                // 引擎分流：ebpf → sing-box(root 透明代理)；其余（默认）走原 tun2socks 路径，行为完全不变
                val proxyEngine =
                    request.arguments?.get("proxyEngine")?.jsonPrimitive?.content ?: "tun2socks"
                if (proxyEngine == "ebpf") {
                    val result = ebpfController.start(config)
                    Log.d(TAG, "start_proxy(ebpf) result: $result")
                    return@addTool CallToolResult(
                        content = listOf(TextContent(result)),
                        isError = result.startsWith("Error")
                    )
                }

                val intent = VpnService.prepare(context)
                if (intent != null) {
                    return@addTool CallToolResult(
                        content = listOf(
                            TextContent("You must start the proxy once, or authorize VPN manually.")
                        ),
                        isError = true
                    )
                }

                val result: String = vpnController!!.startVpn(config)
                vpnController!!.setVpnConfig(config)
                // 记录日志
                Log.i(TAG, "Proxy start result: $result")

                return@addTool CallToolResult(
                    content = listOf(
                        TextContent(result)
                    ),
                    isError = result.startsWith("Error") || result.contains("not granted")
                )
            } catch (e: Exception) {
                Log.e(TAG, "Error starting proxy: ${e.message}", e)
                return@addTool CallToolResult(
                    content = listOf(
                        TextContent("Error starting proxy: ${e.message}")
                    ),
                    isError = true
                )
            }
        }
        // 停止 proxy
        server.addTool(
            "stop_proxy",
            description = "Stop the proxy service",
            inputSchema = ToolSchema()
        ){
            _->
                // stop_proxy：**不需要**调用方说明停哪个引擎 —— 先问 eBPF 在不在跑，
                // 在跑就停它，否则走 tun2socks（两引擎互斥，所以这个二选一是确定的）
                try {
                    Log.d(TAG, "stop_proxy called")
                    val result: String =
                        if (ebpfController.getStatus()) ebpfController.stop() else vpnController!!.stopVpn()
                    Log.d(TAG, "Proxy stop result: $result")
                    return@addTool CallToolResult(
                        content = listOf(
                            TextContent(result)
                        ),
                        // 结果里带 "Error"/"not granted" 视为失败（VPN 未授权时是后一种）
                        isError = result.startsWith("Error") || result.contains("not granted")
                    )
                }catch (e: Exception){
                    Log.e(TAG, "Error stopping proxy: ${e.message}", e)
                    return@addTool CallToolResult(
                        content = listOf(
                            TextContent("Error stopping proxy: ${e.message}")
                        ),
                        isError = true
                    )
                }
        }
        // get_proxy_status：只回答"在不在跑"（两个引擎任一在跑即 true）
        server.addTool(
            "get_proxy_status",
            description = "Get the status of the proxy service",
            inputSchema = ToolSchema()
        ){
            _-> try {
                Log.d(TAG, "get_proxy_status called")
                val result: Boolean = anyEngineRunning()
                Log.d(TAG, "Proxy status: $result")
            return@addTool CallToolResult(
                    content = listOf(
                        TextContent(if (result) "Proxy is running" else "Proxy is not running")
                    ),
                    // 「没在跑」也算 isError=true：调用方通常期望"起来"，好区分成功与否
                    isError = !result
                )
            } catch (e: Exception) {
                return@addTool CallToolResult(
                    content = listOf(
                        TextContent("Error getting Proxy status: ${e.message}")
                    ),
                    isError = true
                )
            }
        }
        // get_proxy_config：回答"在不在跑 + 引擎名 + 当前配置"
        server.addTool(
            "get_proxy_config",
            description = "Get the current proxy configuration",
            inputSchema = ToolSchema()
        ){
            _ -> try {
            // 一次查询拿全：谁在跑 + engine 名（eBPF 的 getStatus 会跑 root 命令，避免重复调用）
            val ebpfRunning = ebpfController.getStatus()
            val running = ebpfRunning || vpnController?.getVpnStatus() == true
            // 引擎名仅用于展示/排查；注意"没在跑"时也会给出 tun2socks（默认引擎），
            // 所以调用方判断"有没有在跑"要看 running 的文案，而不是引擎名
            val engine = if (ebpfRunning) "ebpf" else "tun2socks"
                return@addTool CallToolResult(
                    content = listOf(
                        TextContent(
                            "${if (running) "Proxy is running" else "Proxy is not running"} (engine=$engine), Current proxy configuration:" +
                                (if (ebpfRunning) ebpfController.getConfig().toString() else vpnController!!.getVpvConfig().toString())
                        )
                    )
                )
            }catch (e: Exception){
                return@addTool CallToolResult(
                    content = listOf(
                        TextContent("Error getting proxy configuration: ${e.message}")
                    ),
                    isError = true
                )
            }
        }

        // 修改代理参数 可选 其一 可多选 {proxyHost: '192.168.0.2', proxyPort: '8080', proxyType: 'http', proxyUser: '', proxyPass: '', appProxyPackageList: '["com.qihoo.contents", "com.whatsapp"]'}
        server.addTool(
            "update_proxy_config",
            description = "Update the proxy configuration, proxyHost, proxyPort, proxyType cannot be empty, Tip: Ask user for required fields if not provided",
            inputSchema = ToolSchema(
                properties = buildJsonObject{
                    putJsonObject("proxyHost") {
                        put("type", "string")
                        put("description", "Proxy host address, default: device LAN IP")
                        put("default", "192.168.0.10")
                        put("examples", buildJsonArray {
                            add("192.168.0.2")
                            add("10.0.0.1")
                        })
                    }
                    putJsonObject("proxyPort") {
                        put("type", "string")
                        put("description", "Proxy port number")
                        put("default", "8080")
                        put("examples", buildJsonArray {
                            add("8080")
                            add("8081")
                        })
                    }
                    putJsonObject("proxyType") {
                        put("type", "string")
                        put("description", "Proxy type")
                        put("default", "http")
                        put("enum", buildJsonArray {
                            add("http")
                            add("socks5")
                        })
                    }
                    putJsonObject("proxyUser") {
                        put("type", "string")
                        put("description", "Proxy username")
                        put("default", "")
                    }
                    putJsonObject("proxyPass") {
                        put("type", "string")
                        put("description", "Proxy password")
                        put("default", "")
                    }
                    putJsonObject("appProxyPackageList") {
                        put("type", "string")
                        put(
                            "description",
                            "[\"com.example\", \"com.whatsapp\"] Empty array [] means proxy all apps except this proxy app"
                        )
                        put("default", "[]")
                        put("examples", buildJsonArray {
                            add("[\"com.example\", \"com.whatsapp\"]")
                            add("[\"com.example\"]")
                            add("[]")
                        })
                    }
                    putJsonObject("proxyEngine") {
                        put("type", "string")
                        put(
                            "description",
                            "Proxy engine: 'tun2socks' (default) or 'ebpf'. Updating an eBPF proxy rebuilds config.json and restarts sing-box."
                        )
                        put("enum", buildJsonArray {
                            add("tun2socks")
                            add("ebpf")
                        })
                    }
                    // ---- 以下仅 eBPF 引擎使用（可选）----
                    putJsonObject("proxyName") {
                        put("type", "string")
                        put(
                            "description",
                            "Optional: name of the proxy configuration. Used to find its saved ebpfNetwork/ebpfDataPlane in proxyConfig.json when those are not passed explicitly."
                        )
                    }
                    putJsonObject("ebpfNetwork") {
                        put("type", "string")
                        put(
                            "description",
                            "eBPF only: capture network. Omit to inherit the saved value from proxyConfig.json (fallback: 'all'). 'tcp' = TCP only, 'udp' = UDP only."
                        )
                        put("enum", buildJsonArray {
                            add("all")
                            add("tcp")
                            add("udp")
                        })
                    }
                    putJsonObject("ebpfDataPlane") {
                        put("type", "string")
                        put(
                            "description",
                            "eBPF only: kernel data plane. Omit to inherit the saved value from proxyConfig.json (fallback: cgroup or the plane supported by this device)."
                        )
                        put("enum", buildJsonArray {
                            add("cgroup")
                            add("socket_assign")
                        })
                    }
                }
            )
        ){
            request ->
            try {
                // ① 前提：必须有代理在跑 —— 这个工具的语义是"改运行中的配置并重启"，没在跑就没有可改的
                if (!anyEngineRunning()){
                    return@addTool CallToolResult(content = listOf(TextContent("Proxy is not running")), isError = true)
                }
                val proxyHost = request.arguments?.get("proxyHost")?.jsonPrimitive?.content ?: ""
                val proxyPort = request.arguments?.get("proxyPort")?.jsonPrimitive?.content ?: ""
                val proxyType =
                    request.arguments?.get("proxyType")?.jsonPrimitive?.content ?: "http"
                val proxyUser = request.arguments?.get("proxyUser")?.jsonPrimitive?.content ?: ""
                val proxyPass = request.arguments?.get("proxyPass")?.jsonPrimitive?.content ?: ""
                val appListJson =
                    request.arguments?.get("appProxyPackageList")?.jsonPrimitive?.content ?: "[]"

                // ② 分应用列表校验：空列表 = 全部接管（合法），非空则必须都是设备上真实存在的包名
                val type = object : TypeToken<List<String>>(){}.type
                val appList: List<String> = Gson().fromJson(appListJson, type)
                val packageList = vpnController!!.getPackageList()

                if (appList.isNotEmpty() && !packageList.containsAll(appList)){
                    val missingPackages = appList.filter { it !in packageList }
                    Log.e(TAG, "Error: $missingPackages is not valid")
                    return@addTool CallToolResult(
                        content = listOf(
                            TextContent("Error: $missingPackages is not valid")
                        ),
                        isError = true
                    )
                }
                if (proxyHost.isEmpty() || proxyPort.isEmpty() || proxyType.isEmpty()){
                    Log.e(TAG, "Error: proxyHost, proxyPort, proxyType cannot be empty")
                    return@addTool CallToolResult(
                        content = listOf(
                            TextContent("Error: proxyHost, proxyPort, proxyType cannot be empty")
                        ),
                        isError = true
                    )
                }

                // ---- eBPF 引擎：重建 config.json 并重启 sing-box ----
                // 触发条件：eBPF 正在运行，或调用方显式要求 proxyEngine=ebpf
                // （eBPF 是"改配置就重启进程"的模型，所以先 stop 再 start 即可，没有别的通路）
                val proxyEngine =
                    request.arguments?.get("proxyEngine")?.jsonPrimitive?.content
                if (ebpfController.getStatus() || proxyEngine == "ebpf") {
                    // eBPF 可调项：调用方没传时从 proxyConfig.json 的已有配置继承。
                    // 否则「只改地址/账号」这种局部更新会把 ebpfNetwork/ebpfDataPlane 重置成
                    // 生成器默认值：轻则接管范围被悄悄改掉，重则（设备只支持一种数据面）起不来。
                    val ebpfNetworkArg = request.arguments?.get("ebpfNetwork")
                        ?.jsonPrimitive?.content?.takeIf { it.isNotBlank() }
                    val ebpfDataPlaneArg = request.arguments?.get("ebpfDataPlane")
                        ?.jsonPrimitive?.content?.takeIf { it.isNotBlank() }
                    val proxyNameArg = request.arguments?.get("proxyName")
                        ?.jsonPrimitive?.content?.takeIf { it.isNotBlank() }
                    val stored = readStoredEbpfOptions(proxyNameArg, proxyHost, proxyPort)
                    val ebpfNetwork = ebpfNetworkArg ?: stored.first
                    val ebpfDataPlane = ebpfDataPlaneArg ?: stored.second
                    Log.d(
                        TAG,
                        "update_proxy_config(ebpf): network=$ebpfNetwork dataPlane=$ebpfDataPlane " +
                            "(stored network=${stored.first} dataPlane=${stored.second})"
                    )

                    // 旧进程先停：否则新进程会和它抢内核附着/端口
                    if (ebpfController.getStatus()) {
                        ebpfController.stop()
                    }
                    val ebpfConfig = buildMap {
                        put("proxyHost", proxyHost)
                        put("proxyPort", proxyPort)
                        put("proxyType", proxyType)
                        put("proxyUser", proxyUser)
                        put("proxyPass", proxyPass)
                        put("appProxyPackageList", appList)
                        if (ebpfNetwork != null) put("ebpfNetwork", ebpfNetwork)
                        if (ebpfDataPlane != null) put("ebpfDataPlane", ebpfDataPlane)
                        if (proxyNameArg != null) put("proxyName", proxyNameArg)
                    }
                    val result = ebpfController.start(ebpfConfig)
                    Log.i(TAG, "Proxy(ebpf) update result: $result")
                    return@addTool CallToolResult(
                        content = listOf(TextContent(result)),
                        isError = result.startsWith("Error")
                    )
                }

                // ---- tun2socks 引擎（原路径，行为不变）----
                var config = mapOf(
                    "proxyHost" to proxyHost,
                    "proxyPort" to proxyPort,
                    "proxyType" to proxyType,
                    "proxyUser" to proxyUser,
                    "proxyPass" to proxyPass,
                    "appProxyPackageList" to appList,
                )
                // setVpnConfig 返回 true = 有字段真的变了、需要重启 VPN 才生效
                val isRestartMcpServer = vpnController!!.setVpnConfig(config)
                if (isRestartMcpServer){
                    // tun2socks 没有热改能力：重启 = 停掉 VPN 服务再按新配置起来
                    vpnController!!.stopVpn()
                    config = vpnController!!.getVpvConfig()!!
                    val result: String = vpnController!!.startVpn(config)
                    // 记录日志
                    Log.i(TAG, "Proxy start result: $result")

                    return@addTool CallToolResult(
                        content = listOf(
                            TextContent(result)
                        ),
                        isError = result.startsWith("Error") || result.contains("not granted")
                    )
                }
                return@addTool CallToolResult(
                    content = listOf(
                        TextContent("Proxy no need update")
                    ),
                    isError = false
                )

            }catch (e: Exception) {
                return@addTool CallToolResult(
                    content = listOf(
                        TextContent("Error updating proxy configuration: ${e.message}")
                    ),
                    isError = true
                )
            }
        }
        // 提示词：给 MCP 客户端一段"怎么用这个服务"的说明书（客户端可主动拉取）
        server.addPrompt(
            "how_to_use_appproxy-mcp",
            description = "Guide for using appproxy-mcp",
        ){ _ ->
            GetPromptResult(
                description = "appproxy-mcp usage guide",
                messages = listOf(
                    PromptMessage(
                        role = Role.User,
                        content = TextContent("""
                            |## appproxy-mcp Guide
                            |Tools: start_proxy, stop_proxy, get_proxy_status, get_proxy_config, update_proxy_config
                            |start_proxy: proxyHost(default: device LAN IP), proxyPort, proxyType(http/socks5), proxyName, [proxyUser, proxyPass, appProxyPackageList]
                            |appProxyPackageList: JSON array e.g. ["com.whatsapp"], [] = all apps
                            |Note: VPN permission required first use; packages must be installed apps
                        """.trimMargin()),
                    ),
                ),
            )
        }
        return server
    }

}