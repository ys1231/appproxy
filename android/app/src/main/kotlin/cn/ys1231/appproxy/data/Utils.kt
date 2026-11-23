package cn.ys1231.appproxy.data

import android.Manifest.permission.INTERNET
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.ApplicationInfo.FLAG_SYSTEM
import android.content.pm.LauncherApps
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Process
import android.util.Base64
import android.util.Log
import androidx.core.graphics.createBitmap
import com.google.gson.Gson
import com.topjohnwu.superuser.Shell
import java.io.ByteArrayOutputStream

/**
 * 应用列表扫描。
 *
 * 默认 PackageManager 只能看到**当前用户**安装的应用；工作资料、系统“应用分身”/多开
 * 通常在其它 Android 用户里运行，普通扫描看不到。这里分三层枚举并合并：
 *
 *  1. 当前用户：PackageManager（带图标、INTERNET 过滤，行为与旧版一致）
 *  2. 其它资料：LauncherApps.getProfiles() + getActivityList（免 root，覆盖工作资料等）
 *  3. 隐藏用户：root 可用时 `pm list users` → `pm list packages -3 -U --user N`
 *     （覆盖 ColorOS/MIUI 等把分身放在隐藏 user 999 的情况；无 root 自动跳过）
 *
 * 同一个包名可能在多个用户里各有一份（原应用 + 分身），条目用 userId 区分；
 * Flutter 侧按包名合并展示并标注“含分身”，代理引擎仍以包名为粒度。
 */
class Utils(private val context: Context) {
    private val TAG = "iyue->${this.javaClass.simpleName} "

    private var appList: String? = null
    private var isFirstGetApps: Boolean = true

    // 用户拒绝过一次 root 授权后，本进程内不再重复弹窗（重启 App 后可再尝试）
    @Volatile
    private var rootScanDenied: Boolean = false

    init {
        Log.d(TAG, "Utils init !")
    }

    /**
     * 全量扫描：当前用户 + 其它资料（工作资料等）。
     *
     * [includeRoot] = true 时额外扫描隐藏用户（系统“应用分身”/多开），
     * 这时如果 su 可用会请求一次 root 授权（用户从“配置”页菜单主动触发，
     * 避免 App 冷启动就弹授权框）。
     */
    @Synchronized
    fun initAppList(includeRoot: Boolean = false) {
        Log.d(TAG, "initAppList: start includeRoot=$includeRoot")
        val keys = mutableSetOf<String>()
        val apps = mutableListOf<Map<String, Any>>()
        try {
            apps.addAll(scanCurrentUser(keys))
        } catch (e: Exception) {
            Log.w(TAG, "scanCurrentUser failed: ${e.message}")
        }
        try {
            apps.addAll(scanOtherProfiles(keys))
        } catch (e: Exception) {
            Log.w(TAG, "scanOtherProfiles failed: ${e.message}")
        }
        if (includeRoot) {
            try {
                apps.addAll(scanRootUsers(keys, allowPrompt = true))
            } catch (e: Exception) {
                Log.w(TAG, "scanRootUsers failed: ${e.message}")
            }
        }
        appList = Gson().toJson(apps)
        Log.d(TAG, "initAppList: end, ${apps.size} entries")
    }

    /**
     * 取应用列表（JSON 字符串）。
     * 首次命中缓存直接返回（省去遍历+取图标的重活）；之后每次都重新扫描，
     * 这样用户在"配置"页看到的是最新的安装/卸载情况。
     */
    @Synchronized
    fun getAppList(includeRoot: Boolean = false): String? {
        if (!includeRoot && isFirstGetApps && appList != null) {
            isFirstGetApps = false
            return appList
        }
        initAppList(includeRoot)
        return appList
    }

    /** 只取包名（不带图标/标签），供 MCP 校验参数里的包名是否为本机已装应用（含分身） */
    fun getPackageList(): List<String> {
        val keys = mutableSetOf<String>()
        val names = LinkedHashSet<String>()
        scanCurrentUser(keys).forEach { names.add(it["packageName"].toString()) }
        scanOtherProfiles(keys).forEach { names.add(it["packageName"].toString()) }
        // MCP 校验不走 root 授权弹窗：仅在本次会话已确认 root 时补充隐藏用户
        scanRootUsers(keys, allowPrompt = false)
            .forEach { names.add(it["packageName"].toString()) }
        return names.toList()
    }

    // ---------------------------------------------------------------- 扫描实现

    /** 当前用户：沿用旧版 PackageManager 扫描（含 INTERNET 过滤与图标） */
    private fun scanCurrentUser(keys: MutableSet<String>): List<Map<String, Any>> {
        val pm = context.packageManager
        val currentUserId = userIdOfUid(Process.myUid())
        val result = mutableListOf<Map<String, Any>>()

        val packages: List<PackageInfo> = pm.getInstalledPackages(PackageManager.GET_PERMISSIONS)
        for (info in packages) {
            if (info.packageName == context.applicationInfo.packageName) continue
            if (!hasInternet(info)) continue

            val ai = info.applicationInfo ?: continue
            val key = "$currentUserId/${info.packageName}"
            if (!keys.add(key)) continue

            val icon = try {
                encodeIcon(pm.getApplicationIcon(info.packageName))
            } catch (e: PackageManager.NameNotFoundException) {
                Log.w(TAG, "getApplicationIcon failed for ${info.packageName}: ${e.message}")
                ""
            }
            result.add(
                appMap(
                    label = safeLabel(ai, pm),
                    packageName = info.packageName,
                    isSystemApp = if (info.packageName == "com.android.chrome") false else isSystemApp(info),
                    iconBytes = icon,
                    userId = currentUserId,
                    userLabel = "",
                    multiUser = false,
                    uid = ai.uid,
                )
            )
        }
        return result
    }

    /** 其它 Android 资料/资料组：LauncherApps 免 root 枚举（工作资料、部分系统分身） */
    private fun scanOtherProfiles(keys: MutableSet<String>): List<Map<String, Any>> {
        val launcher = context.getSystemService(Context.LAUNCHER_APPS_SERVICE) as? LauncherApps
            ?: return emptyList()
        val current = Process.myUserHandle()
        val result = mutableListOf<Map<String, Any>>()

        val profiles = try {
            launcher.profiles
        } catch (e: Exception) {
            Log.w(TAG, "launcher.profiles failed: ${e.message}")
            emptyList()
        }
        for (profile in profiles) {
            if (profile == current) continue
            val activities = try {
                launcher.getActivityList(null, profile)
            } catch (e: Exception) {
                Log.w(TAG, "getActivityList($profile) failed: ${e.message}")
                continue
            }
            for (act in activities) {
                val ai = try {
                    act.applicationInfo
                } catch (e: Exception) {
                    null
                } ?: continue
                val pkg = ai.packageName
                if (pkg == context.applicationInfo.packageName) continue
                // UserHandle.getUserId(uid) 是隐藏 API；应用 UID = userId*100000+appId，
                // 这里用 profile.hashCode()（AOSP 中即 userId）作为条目所属用户
                val userId = profile.hashCode()
                val key = "$userId/$pkg"
                if (!keys.add(key)) continue
                // 跨用户权限查询需要隐藏 API；用当前用户同包名的权限做近似判断，
                // 查不到时保留（分身基本都是联网应用），避免漏项
                if (!hasInternetByCurrentUser(pkg)) continue

                val label = try {
                    act.label?.toString()?.takeIf { it.isNotBlank() }
                } catch (e: Exception) {
                    null
                } ?: pkg
                val icon = try {
                    encodeIcon(act.getBadgedIcon(context.resources.displayMetrics.densityDpi))
                } catch (e: Exception) {
                    ""
                }
                result.add(
                    appMap(
                        label = label,
                        packageName = pkg,
                        isSystemApp = if (pkg == "com.android.chrome") false else ((ai.flags and FLAG_SYSTEM) != 0),
                        iconBytes = icon,
                        userId = userId,
                        userLabel = "用户$userId",
                        multiUser = true,
                        uid = ai.uid,
                    )
                )
            }
        }
        return result
    }

    /**
     * root 可见的隐藏用户：`pm list users` 拿用户列表，`pm list packages -3 -U --user N`
     * 拿该用户的三方应用与 UID。无 root 授权时直接跳过（不弹 su）。
     */
    private fun scanRootUsers(
        keys: MutableSet<String>,
        allowPrompt: Boolean,
    ): List<Map<String, Any>> {
        if (!ensureRootForScan(allowPrompt)) return emptyList()
        val currentUserId = userIdOfUid(Process.myUid())
        val usersOut = try {
            val r = Shell.cmd("pm list users").exec()
            (r.out + r.err).joinToString("\n")
        } catch (e: Exception) {
            Log.w(TAG, "pm list users failed: ${e.message}")
            return emptyList()
        }
        val userRegex = Regex("UserInfo\\{(\\d+):([^:}]*):")
        val targets = userRegex.findAll(usersOut).mapNotNull { m ->
            val id = m.groupValues[1].toIntOrNull() ?: return@mapNotNull null
            if (id == currentUserId) return@mapNotNull null
            id to m.groupValues[2].trim()
        }.toList()
        if (targets.isEmpty()) return emptyList()

        val result = mutableListOf<Map<String, Any>>()
        val pm = context.packageManager
        val pkgRegex = Regex("package:(\\S+)\\s+uid:(\\d+)")
        for ((userId, userName) in targets) {
            val out = try {
                val r = Shell.cmd("pm list packages -3 -U --user $userId").exec()
                (r.out + r.err).joinToString("\n")
            } catch (e: Exception) {
                Log.w(TAG, "pm list packages --user $userId failed: ${e.message}")
                continue
            }
            for (line in out.lineSequence()) {
                val m = pkgRegex.find(line) ?: continue
                val pkg = m.groupValues[1]
                val uid = m.groupValues[2].toIntOrNull() ?: continue
                if (pkg == context.applicationInfo.packageName) continue
                val key = "$userId/$pkg"
                if (!keys.add(key)) continue

                // 隐藏用户里的包在“当前用户”下也常有一份（分身场景），借它取标签/图标；
                // 取不到（仅分身安装）就回退包名/无图标，保证条目仍可见可选
                var label = pkg
                var icon = ""
                var system = false
                try {
                    val ai = pm.getApplicationInfo(pkg, 0)
                    label = safeLabel(ai, pm).ifBlank { pkg }
                    icon = encodeIcon(pm.getApplicationIcon(ai))
                    system = (ai.flags and FLAG_SYSTEM) != 0
                } catch (e: Exception) {
                    Log.d(TAG, "load clone info $pkg@$userId failed: ${e.message}")
                }
                result.add(
                    appMap(
                        label = label,
                        packageName = pkg,
                        isSystemApp = system,
                        iconBytes = icon,
                        userId = userId,
                        userLabel = userName.ifEmpty { "用户$userId" },
                        multiUser = true,
                        uid = uid,
                    )
                )
            }
        }
        return result
    }

    // ---------------------------------------------------------------- 工具方法

    private fun appMap(
        label: String,
        packageName: String,
        isSystemApp: Boolean,
        iconBytes: String,
        userId: Int,
        userLabel: String,
        multiUser: Boolean,
        uid: Int,
    ): Map<String, Any> = mapOf(
        "label" to label,
        "packageName" to packageName,
        "isSystemApp" to isSystemApp,
        "iconBytes" to iconBytes,
        "userId" to userId,
        "userLabel" to userLabel,
        "multiUser" to multiUser,
        "uid" to uid,
    )

    private fun safeLabel(ai: ApplicationInfo, pm: PackageManager): String = try {
        ai.loadLabel(pm).toString().ifBlank { ai.packageName }
    } catch (e: Exception) {
        ai.packageName
    }

    private fun hasInternet(info: PackageInfo): Boolean {
        val perms = info.requestedPermissions ?: return false
        return perms.contains(INTERNET)
    }

    /**
     * root 可用性判断：
     *  - allowPrompt=false：只看已确认状态（不弹 su，App 启动/MCP 校验用）；
     *  - allowPrompt=true：su 存在但未确认时主动执行一次 `id -u`，用户从菜单
     *    “扫描分身”触发时允许弹出一次授权框。
     */
    private fun ensureRootForScan(allowPrompt: Boolean): Boolean {
        val state = Shell.isAppGrantedRoot()
        if (state == true) return true
        if (!allowPrompt || state == false || rootScanDenied) return false
        return try {
            val ok = Shell.cmd("id -u").exec().out.any { it.trim() == "0" }
            if (!ok) rootScanDenied = true
            ok
        } catch (e: Exception) {
            Log.w(TAG, "ensureRootForScan failed: ${e.message}")
            rootScanDenied = true
            false
        }
    }

    private fun hasInternetByCurrentUser(pkg: String): Boolean = try {
        hasInternet(context.packageManager.getPackageInfo(pkg, PackageManager.GET_PERMISSIONS))
    } catch (e: Exception) {
        // 仅存在于其它用户/资料时当前用户查不到，按“有网络权限”处理，避免漏项
        true
    }

    /** 应用 UID → Android 用户 id（应用 UID = userId * 100000 + appId） */
    private fun userIdOfUid(uid: Int): Int = if (uid < 10000) 0 else uid / 100000

    /// 其它资料的显示名：跨用户用户名是隐藏 API，这里统一用“用户<id>”；
    /// root 路径拿到的 `pm list users` 名称（如“应用分身”）会优先使用。
    private fun isSystemApp(info: PackageInfo): Boolean =
        (info.applicationInfo?.flags ?: 0) and FLAG_SYSTEM != 0

    /** 图标统一缩放到 48×48 并转 Base64（WEBP 或 PNG），与旧版输出格式一致 */
    private fun encodeIcon(drawable: Drawable?): String {
        if (drawable == null) return ""
        return try {
            val size = 48
            val bitmap = createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            val output = ByteArrayOutputStream()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                bitmap.compress(Bitmap.CompressFormat.WEBP_LOSSY, 75, output)
            } else {
                bitmap.compress(Bitmap.CompressFormat.PNG, 75, output)
            }
            bitmap.recycle()
            Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.w(TAG, "encodeIcon failed: ${e.message}")
            ""
        }
    }
}
