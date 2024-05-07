package cn.ys1231.appproxy

import cn.ys1231.appproxy.data.Utils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity(){
    private val CHANNEL = "cn.ys1231/appproxy"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getAppList"){
                try {
                    val appList = Utils(this).getAppList()
                    result.success(appList)
                }catch (e: Exception){
                    result.error("-1", e.message, null)
                }
            }
        }
    }
}
