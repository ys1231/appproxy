package cn.ys1231.appproxy.data

import android.Manifest.permission.INTERNET
import android.content.Context
import android.content.pm.ApplicationInfo.FLAG_SYSTEM
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.PixelFormat
import android.graphics.drawable.Drawable
import android.os.Build
import android.util.Base64
import android.util.Log
import com.google.gson.Gson
import java.io.ByteArrayOutputStream
import androidx.core.graphics.createBitmap

class Utils(private val context: Context) {
    private val TAG = "iyue->${this.javaClass.simpleName} "

    //val sharedPreferences = context.getSharedPreferences("vpnconfig", Context.MODE_PRIVATE)
    private var appList: String? = null
    private var isFirstGetApps: Boolean = true

    init {
        Log.d(TAG, "Utils init !")
    }

    /**
     * 获取已安装应用的列表信息。
     *
     * 该方法通过查询PackageManager获取已安装应用的信息
     * 对于每个符合条件的应用，收集其标签、包名、是否为系统应用以及应用图标，并将这些信息转换为JSON字符串返回。
     *
     * @return 返回包含已安装应用信息的JSON字符串，如果无应用满足条件或发生错误，则返回null。
     */
    fun initAppList() {
        Log.d(TAG, "initAppList: start")
        // 通过上下文获取PackageManager对象，用于管理安装的应用程序
        val pm = context.packageManager

        // 获取已安装应用的PackageInfo列表，包括应用的权限信息
        val resolveInfos: List<PackageInfo> =
            pm.getInstalledPackages(PackageManager.GET_PERMISSIONS)

        // 创建一个列表，用于存储应用信息的Map对象
        val appInfoList = mutableListOf<MutableMap<String, Any>>()

        // 遍历已安装的应用列表
        for (info in resolveInfos) {
            // 排除当前应用或未请求INTERNET权限的应用
            if (info.packageName == context.applicationInfo.packageName ||
                info.requestedPermissions == null ||
                !(info.requestedPermissions as Array<out Any?>).contains(INTERNET)
                ) {
                continue
            }

            // 创建一个Map对象，用于存储单个应用的信息
            val appInfoMap = mutableMapOf<String, Any>()

            // 获取并添加应用的标签信息
            appInfoMap["label"] = pm.getApplicationLabel(info.applicationInfo!!)

            // 获取并添加应用的包名
            appInfoMap["packageName"] = info.packageName

            // 获取并添加应用是否为系统应用的信息
            // Chrome 浏览器强制标记为非系统应用
            appInfoMap["isSystemApp"] = if (info.packageName == "com.android.chrome") false else info.isSystemApp

            // 获取应用的图标，并将其转换为Base64编码的字符串
            // 应用可能在遍历过程中被卸载，需捕获 NameNotFoundException
            try {
                val TARGET_SIZE = 48
                val iconDrawable = pm.getApplicationIcon(info.packageName)
                val scaledBitmap = createBitmap(TARGET_SIZE, TARGET_SIZE, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(scaledBitmap)
                iconDrawable.setBounds(0, 0, TARGET_SIZE, TARGET_SIZE)
                iconDrawable.draw(canvas)
                val byteArrayOutputStream = ByteArrayOutputStream()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    scaledBitmap.compress(Bitmap.CompressFormat.WEBP_LOSSY, 75, byteArrayOutputStream)
                }else{
                    scaledBitmap.compress(Bitmap.CompressFormat.PNG, 75, byteArrayOutputStream)
                }
                scaledBitmap.recycle()
                appInfoMap["iconBytes"] = Base64.encodeToString(byteArrayOutputStream.toByteArray(), Base64.NO_WRAP)
            } catch (e: PackageManager.NameNotFoundException) {
                Log.w(TAG, "getApplicationIcon failed for ${info.packageName}: ${e.message}")
                appInfoMap["iconBytes"] = ""
            }

            // 将应用信息的Map对象添加到应用信息列表中
            appInfoList.add(appInfoMap)
        }

        // 使用Gson将应用信息列表转换为JSON字符串并返回
        appList = Gson().toJson(appInfoList)
        Log.d(TAG, "initAppList: end")
    }

    /**
     * 取应用列表（JSON 字符串）。
     * 首次命中缓存直接返回（省去遍历+取图标的重活）；之后每次都重新扫描，
     * 这样用户在"配置"页看到的是最新的安装/卸载情况。
     */
    fun getAppList(): String? {
        if (isFirstGetApps && appList != null) {
            isFirstGetApps = false
            return appList
        } else {
            initAppList()
            return appList
        }
    }

    /** 只取包名（不带图标/标签），供 MCP 校验参数里的包名是否为本机已装应用 */
    fun getPackageList(): List<String> {
        val pm = context.packageManager

        // 获取已安装应用的PackageInfo列表，包括应用的权限信息
        val resolveInfos: List<PackageInfo> =
            pm.getInstalledPackages(PackageManager.GET_PERMISSIONS)

        // 创建一个列表，用于存储应用信息的Map对象
        val packageList = mutableListOf<String>()

        // 遍历已安装的应用列表
        for (info in resolveInfos) {
            // 排除当前应用或未请求INTERNET权限的应用
            if (info.packageName == context.applicationInfo.packageName ||
                info.requestedPermissions == null ||
                !(info.requestedPermissions as Array<out Any?>).contains(INTERNET)
            ) {
                continue
            }
            // 获取并添加应用的包名
            packageList.add(info.packageName)
        }
        return packageList.toList()
    }

    private val PackageInfo.isSystemApp: Boolean
        get() = applicationInfo!!.flags and FLAG_SYSTEM != 0

}