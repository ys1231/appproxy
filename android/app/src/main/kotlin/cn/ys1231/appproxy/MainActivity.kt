package cn.ys1231.appproxy

import android.Manifest.permission.POST_NOTIFICATIONS
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import cn.ys1231.appproxy.IyueService.IyueVPNService
import cn.ys1231.appproxy.data.Utils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.Serializable


class MainActivity : FlutterActivity() {
    private val TAG = "iyue->${this.javaClass.simpleName}"
    private val CHANNEL = "cn.ys1231/appproxy"
    private val CHANNEL_VPN = "cn.ys1231/appproxy/vpn"
    private val CHANNEL_APP_UPDATE = "cn.ys1231/appproxy/appupdate"
    private var intentVPNService: Intent? = null
    private val ACTION_STOP_SERVICE = "cn.ys1231.appproxy.STOP_VPN_SERVICE"
    private var proxyName: String = ""
    private var utils: Utils? = null
    private val REQUEST_NOTIFICATION_PERMISSION = 1231

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        utils = Utils(this)
        if (intent.getBooleanExtra("iyue_vpn_channel", false)) {
            val data = intent.getStringExtra("proxyData")
            if (data != null) {
                proxyName = data
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        intentVPNService = Intent(this, IyueVPNService::class.java)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method == "getAppList") {
                try {
                    Log.d(TAG, "configureFlutterEngine ${call.method} ")
                    val appList = Utils(this).getAppList()
                    result.success(appList)
                } catch (e: Exception) {
                    result.error("-1", e.message, null)
                }

            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_VPN
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startVpn" -> {
                    try {
                        val proxy: Map<String, Any>? = call.arguments<Map<String, Any>>()
                        startVpn(this, proxy)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("-1", e.message, null)
                    }
                }

                "stopVpn" -> {
                    try {
                        stopVpnService(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("-1", e.message, null)
                    }
                }

                "getCurrentProxy" -> {
                    try {
                        val data = isVpnRunning()
                        result.success(data)
                    } catch (e: Exception) {
                        result.error("-1", e.message, null)
                    }
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_APP_UPDATE
        ).setMethodCallHandler { call, result ->
            if (call.method == "startDownload") {
                try {
                    Log.d(TAG, "configureFlutterEngine ${call.method} ")
                    val url: String? = call.arguments<String>()
                    startDownload(url)
//                    result.success(appList)
                } catch (e: Exception) {
                    result.error("-1", e.message, null)
                }

            }
        }
    }

    private fun isVpnRunning(): String? {
        return proxyName
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                // 用户授权成功，启动VPN服务
                Log.d(TAG, "onActivityResult: 用户授权成功，启动VPN服务 ")
                startService(intentVPNService)
            } else {
                // 用户拒绝授权，处理相应逻辑
                Log.d(TAG, "onActivityResult: 用户拒绝授权 ")
                // 在这里可以通知Flutter层授权失败 TODO
            }
        }
    }

    private val VPN_REQUEST_CODE = 100
    private fun startVpn(context: Context, proxy: Map<String, Any>?) {
        Log.d(TAG, "startVpn: $proxy")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(
                    this,
                    POST_NOTIFICATIONS
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(POST_NOTIFICATIONS),
                    REQUEST_NOTIFICATION_PERMISSION
                )
            } else {
                // 权限已被授予
                Log.d(TAG, "onCreate: 通知权限已授予!")
            }
        }
        // 传递数据
        intentVPNService?.putExtra("data", proxy as Serializable)
        // 准备建立 VPN 连接 检测用户是否同意
        var intent = VpnService.prepare(context)
        if (intent != null) {
            this.startActivityForResult(intent, VPN_REQUEST_CODE)
        } else {
            context.startService(intentVPNService)
        }
    }

    private fun stopVpnService(context: Context) {
        val intent = Intent(context, IyueVPNService::class.java)
        intent.setAction(ACTION_STOP_SERVICE)
        context.startService(intent)
        val result = context.stopService(intent)
        Log.d(TAG, "stopService: state:$result")
    }

    private fun startDownload(url: String?) {
        val downloadIntent = Intent(Intent.ACTION_VIEW)
        downloadIntent.setDataAndType(Uri.parse(url), "application/octet-stream")
        downloadIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        startActivity(downloadIntent)
    }

    override fun onDestroy() {
        super.onDestroy()
        if (utils != null) {
            utils!!.setVpnStatus(false)
            utils!!.setProxyName("")
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATION_PERMISSION) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                // 权限被授予
                Toast.makeText(this, "通知权限被授予", Toast.LENGTH_SHORT).show()
            } else {
                // 权限被拒绝
                Toast.makeText(this, "此应用程序需要通知权限", Toast.LENGTH_SHORT).show()
                startNotificationSetting()
            }
        }
    }

    private fun startNotificationSetting() {
        val applicationInfo = applicationInfo
        try {
            val intent = Intent()
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            intent.action = "android.settings.APP_NOTIFICATION_SETTINGS"
            intent.putExtra("app_package", applicationInfo.packageName)
            intent.putExtra("android.provider.extra.APP_PACKAGE", applicationInfo.packageName)
            intent.putExtra("app_uid", applicationInfo.uid)
            startActivity(intent)
        } catch (e: Exception) {
            val intent = Intent()
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            intent.action = "android.settings.APPLICATION_DETAILS_SETTINGS"
            intent.data = Uri.fromParts("package", applicationInfo.packageName, null)
            startActivity(intent)
        }
    }

}
