package cn.ys1231.appproxy

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.util.Log
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
    private var intentVPNService: Intent? = null
    private val ACTION_STOP_SERVICE = "cn.ys1231.appproxy.STOP_VPN_SERVICE"
    private var proxyName: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
       if ( intent.getBooleanExtra("iyue_vpn_channel", false)){
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

}
