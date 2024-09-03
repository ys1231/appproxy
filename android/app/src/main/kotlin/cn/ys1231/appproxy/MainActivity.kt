package cn.ys1231.appproxy

//import cn.ys1231.appproxy.IyueService.IyueVPNService1
import android.Manifest.permission.POST_NOTIFICATIONS
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.util.Log
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import cn.ys1231.appproxy.IyueService.IyueVPNService
import cn.ys1231.appproxy.data.Utils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel


class MainActivity : FlutterActivity() {
    private val TAG = "iyue->${this.javaClass.simpleName}"
    private val CHANNEL = "cn.ys1231/appproxy"
    private val CHANNEL_VPN = "cn.ys1231/appproxy/vpn"
    private val CHANNEL_APP_UPDATE = "cn.ys1231/appproxy/appupdate"

    private var utils: Utils? = null
    private var intentVpnService: Intent? = null
    private var iyueVpnService: IyueVPNService? = null
    private var isBind: Boolean = false
    private var currentProxy: Map<String, Any>? = null

    private var conn: ServiceConnection? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        utils = Utils(this)
        intentVpnService = Intent(this, IyueVPNService::class.java)
        conn = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
                Log.d(TAG, "onServiceConnected: $name")

                if (service is IyueVPNService.VPNServiceBinder) {
                    iyueVpnService = service.getService()
                } else {
                    Log.d(TAG, "onServiceConnected: ClassCastException")
                }

            }

            override fun onServiceDisconnected(name: ComponentName?) {
                Log.d(TAG, "onServiceDisconnected: $name")
            }
        }
        if (bindService(intentVpnService!!, conn!!, Context.BIND_AUTO_CREATE)) {
            isBind = true
        }
    }

    private fun startVpnService() {
        Log.d(TAG, "startVpnService: ${currentProxy.toString()}")
        iyueVpnService?.startVpnService(currentProxy!!)
    }

    private fun stopVpnService() {
        Log.d(TAG, "stopVpnService: ...... ")
        iyueVpnService?.stopVpnService()
    }

    private fun startDownload(url: String?) {
        val downloadIntent = Intent(Intent.ACTION_VIEW)
        downloadIntent.data = Uri.parse(url)
        downloadIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        startActivity(downloadIntent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
                        currentProxy = call.arguments<Map<String, Any>>()
                        checkVpnPermissionAndStartVpnService(this)
                        result.success(iyueVpnService?.isRunning())
                    } catch (e: Exception) {
                        result.error("-1", e.message, null)
                    }
                }

                "stopVpn" -> {
                    try {
                        stopVpnService()
                        result.success(!iyueVpnService?.isRunning()!!)
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
                } catch (e: Exception) {
                    result.error("-1", e.message, null)
                }
            }
        }
    }

    private val VPN_REQUEST_CODE = 100
    private val REQUEST_NOTIFICATION_PERMISSION = 1231
    private fun checkVpnPermissionAndStartVpnService(context: Context) {
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
        // 准备建立 VPN 连接 检测用户是否同意
        var intent = VpnService.prepare(context)
        if (intent != null) {
            this.startActivityForResult(intent, VPN_REQUEST_CODE)
        } else {
            startVpnService()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                // 用户授权成功，启动VPN服务
                Log.d(TAG, "onActivityResult: 用户授权成功，启动VPN服务 ")
                startVpnService()
            } else {
                // 用户拒绝授权，处理相应逻辑
                Log.d(TAG, "onActivityResult: 用户拒绝授权 ")
                // 在这里可以通知Flutter层授权失败 TODO
            }
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

    override fun onDestroy() {
        super.onDestroy()
        if (isBind) {
            unbindService(conn!!)
            isBind = false
        }
    }
}
