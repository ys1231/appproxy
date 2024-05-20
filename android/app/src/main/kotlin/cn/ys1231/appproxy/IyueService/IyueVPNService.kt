package cn.ys1231.appproxy.IyueService

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.InetSocketAddress
import java.nio.ByteBuffer
import java.nio.channels.DatagramChannel


class IyueVPNService : VpnService() {
    private val TAG = "iyue->${this.javaClass.simpleName}"
    private var vpnInterface: ParcelFileDescriptor? = null
    private lateinit var vpnThread: Thread

    override fun onCreate() {
        super.onCreate()
        // 初始化操作
        Log.d(TAG, "onCreate: ")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: ")
        // TODO 启动 VPN 连接
        return START_STICKY
    }

    private fun startVpn() {
        Log.d(TAG, "startVpn: ")
        val builder = Builder()

    }

    private fun stopVpn() {
        Log.d(TAG, "stopVpn: ")
        vpnInterface?.close()
        vpnThread.interrupt()
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy: ")
        super.onDestroy()
        // 释放资源
    }
}