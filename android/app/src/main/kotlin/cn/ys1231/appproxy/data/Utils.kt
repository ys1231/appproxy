package cn.ys1231.appproxy.data

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.PixelFormat
import android.graphics.drawable.Drawable
import android.util.Base64
import android.util.Log
import java.io.ByteArrayOutputStream
import com.google.gson.Gson

class Utils(val context: Context) {
    val TAG = "iyue->${this.javaClass.simpleName} "
    val mContext: Context = context

    init {
        Log.d(TAG, ": Utils init !")
    }

    fun getAppList(): String? {
        val intent = Intent()
        intent.setAction(Intent.ACTION_MAIN)
        intent.addCategory(Intent.CATEGORY_LAUNCHER)
        val pm = mContext.packageManager
        //set MATCH_ALL to prevent any filtering of the results
        val resolveInfos = pm.queryIntentActivities(intent, PackageManager.MATCH_ALL)

        var appInfoList = mutableListOf<MutableMap<String, Any>>()
        for (info in resolveInfos) {
            if (info.loadLabel(pm).toString() == "appproxy"){
                continue
            }
            var appInfoMap = mutableMapOf<String, Any>()
            appInfoMap["label"] = info.loadLabel(pm).toString()
            appInfoMap["packageName"] = info.activityInfo.packageName
            if (info.activityInfo.applicationInfo.sourceDir.contains("/data")) {
                appInfoMap["isSystemApp"] = false
            } else {
                appInfoMap["isSystemApp"] = true
            }
            val iconDrawable = info.activityInfo.loadIcon(pm)
            if (iconDrawable != null) {
                val bitmap = drawableToBitmap(iconDrawable)
                val byteArrayOutputStream = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, byteArrayOutputStream)
                val iconBytes = byteArrayOutputStream.toByteArray()
                appInfoMap["iconBytes"] = Base64.encodeToString(iconBytes, Base64.NO_WRAP)
            }
            appInfoList.add(appInfoMap)
            // Log.d(TAG,"getAllAppInfo: name: " + info.loadLabel(pm) + " ,packageName:" + info.activityInfo.packageName)
        }

        return Gson().toJson(appInfoList)
    }

    fun drawableToBitmap(drawable: Drawable): Bitmap {
        val bitmapWidth = drawable.intrinsicWidth
        val bitmapHeight = drawable.intrinsicHeight
        val bitmapConfig = if (drawable.opacity != PixelFormat.OPAQUE) Bitmap.Config.ARGB_8888 else Bitmap.Config.RGB_565
        val bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, bitmapConfig)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }

}