package cn.ys1231.appproxy.data

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class AppChangeReceiver(private val onAppChanged: (String?) -> Unit) : BroadcastReceiver() {
    private val TAG = "iyue->${this.javaClass.simpleName} "
    /** 收到应用安装/卸载/更新广播：回调宿主（MainActivity）通知 Flutter 刷新应用列表 */
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        // 获取发生变化的包名
        val packageName = intent.data?.schemeSpecificPart

        when (action) {
            Intent.ACTION_PACKAGE_ADDED -> {
                val isReplacing = intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
                onAppChanged(packageName)
                // 处理应用安装事件
                Log.d(TAG, "App installed: $packageName, isReplacing: $isReplacing")
            }
            Intent.ACTION_PACKAGE_REMOVED -> {
                val isReplacing = intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)
                onAppChanged(packageName)
                // 处理应用卸载事件
                Log.d(TAG, "App uninstalled: $packageName, isReplacing: $isReplacing")
            }
            Intent.ACTION_PACKAGE_REPLACED -> {
                // 处理应用更新事件（覆盖安装完成后触发）
                Log.d(TAG, "App updated: $packageName")
            }
        }
    }
}