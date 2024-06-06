package cn.ys1231.appproxy.data

import android.Manifest.permission.INTERNET
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo.FLAG_SYSTEM
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.PixelFormat
import android.graphics.drawable.Drawable
import android.util.Base64
import android.util.Log
import java.io.ByteArrayOutputStream
import com.google.gson.Gson

class Utils(private val context: Context) {
    private val TAG = "iyue->${this.javaClass.simpleName} "
    val sharedPreferences = context.getSharedPreferences("vpnconfig", Context.MODE_PRIVATE)

    init {
        Log.d(TAG, ": Utils init !")
    }

    /**
     * 获取已安装应用的列表信息。
     *
     * 该方法通过查询PackageManager获取已安装应用的信息
     * 对于每个符合条件的应用，收集其标签、包名、是否为系统应用以及应用图标，并将这些信息转换为JSON字符串返回。
     *
     * @return 返回包含已安装应用信息的JSON字符串，如果无应用满足条件或发生错误，则返回null。
     */
    fun getAppList(): String? {

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
                !info.requestedPermissions.contains(INTERNET)
                ) {
                continue
            }

            // 创建一个Map对象，用于存储单个应用的信息
            val appInfoMap = mutableMapOf<String, Any>()

            // 获取并添加应用的标签信息
            appInfoMap["label"] = pm.getApplicationLabel(info.applicationInfo)

            // 获取并添加应用的包名
            appInfoMap["packageName"] = info.packageName

            // 获取并添加应用是否为系统应用的信息
            appInfoMap["isSystemApp"] = info.isSystemApp

            // 获取应用的图标，并将其转换为Base64编码的字符串
            val iconDrawable = pm.getApplicationIcon(info.packageName)

            val bitmap = drawableToBitmap(iconDrawable)
            val byteArrayOutputStream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, byteArrayOutputStream)
            val iconBytes = byteArrayOutputStream.toByteArray()
            appInfoMap["iconBytes"] = Base64.encodeToString(iconBytes, Base64.NO_WRAP)

            // 将应用信息的Map对象添加到应用信息列表中
            appInfoList.add(appInfoMap)
        }

        // 使用Gson将应用信息列表转换为JSON字符串并返回
        return Gson().toJson(appInfoList)
    }

    private val PackageInfo.isSystemApp: Boolean
        get() = applicationInfo.flags and FLAG_SYSTEM != 0

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        val bitmapWidth = drawable.intrinsicWidth
        val bitmapHeight = drawable.intrinsicHeight
        val bitmapConfig =
            if (drawable.opacity != PixelFormat.OPAQUE) Bitmap.Config.ARGB_8888 else Bitmap.Config.RGB_565
        val bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, bitmapConfig)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }

    public fun setVpnStatus(status: Boolean){
        var edit = sharedPreferences.edit()
        edit.putBoolean("vpnStatus", status)
        edit.commit()
    }
    public fun getVpnStatus(): Boolean{
        return sharedPreferences.getBoolean("vpnStatus", false)
    }
    public fun setProxyName(name: String){
        var edit = sharedPreferences.edit()
        edit.putString("proxyName", name)
        edit.commit()
    }
    public fun getProxyName(): String{
        return sharedPreferences.getString("proxyName", "") ?: ""
    }
}