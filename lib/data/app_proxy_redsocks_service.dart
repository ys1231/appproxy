import 'dart:io';
import 'package:flutter/services.dart';

/// 通过 iptables + redsocks 实现按应用（UID）透明代理的控制类
/// 需要 root 权限
class AppProxyRedsocksService {
  /// redsocks、proxy.sh 等二进制文件所在目录，建议为 /data/data/org.proxydroid/
  final String basePath;

  /// redsocks 监听端口
  final int localPort;

  AppProxyRedsocksService({
    this.basePath = '/data/data/cn.ys1231.appproxy/files/',
    this.localPort = 8123,
  });

  /// 启动 redsocks 并为指定 app uids 添加 iptables 规则
  Future<bool> startProxyForUids(List<int> uids,
      {String? proxyHost,
      int? proxyPort,
      String? proxyType,
      String? user,
      String? password,
      String? auth}) async {
    // 1. 权限设置
    final List<String> chmodCmds = [
      'chmod 700 ${basePath}redsocks',
      'chmod 700 ${basePath}proxy.sh',
      'chmod 700 ${basePath}gost.sh',
      'chmod 700 ${basePath}cntlm',
      'chmod 700 ${basePath}gost',
    ];
    for (final cmd in chmodCmds) {
      await _runRootCmd(cmd);
    }

    // 2. 停止旧 redsocks
    await _runRootCmd('pkill redsocks');

    // 3. 调用 proxy.sh 生成 redsocks.conf 并启动 redsocks
    // 兼容 http/socks4/socks5 及认证参数
    final type = proxyType ?? 'http';
    final host = proxyHost ?? '127.0.0.1';
    final port = proxyPort?.toString() ?? '8123';
    final authFlag = (auth == 'true' || (user != null && user.isNotEmpty))
        ? 'true'
        : 'false';
    final userVal = user ?? '';
    final passVal = password ?? '';
    final proxyShCmd =
        '${basePath}proxy.sh $basePath start $type $host $port $authFlag "$userVal" "$passVal"';
    final proxyShResult = await _runRootCmd(proxyShCmd);
    if (!proxyShResult) return false;

    // 4. 清理旧 iptables 规则
    await _runRootCmd('iptables -t nat -F OUTPUT');

    // 5. 添加 iptables owner 规则（按应用 UID）
    bool allOk = true;
    for (final uid in uids) {
      final cmd =
          'iptables -t nat -A OUTPUT -p tcp -m owner --uid-owner $uid -j REDIRECT --to-ports $localPort';
      final ok = await _runRootCmd(cmd);
      if (!ok) allOk = false;
    }
    return allOk;
  }

  /// 停止 redsocks 并清理 iptables 规则
  Future<bool> stopProxy() async {
    // 杀掉 redsocks 进程
    await _runRootCmd('pkill redsocks');
    // 清理 nat OUTPUT 规则
    final ok = await _runRootCmd('iptables -t nat -F OUTPUT');
    return ok;
  }

  /// 获取本地 IP
  Future<String?> getLocalIpAddress() async {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (!addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return null;
  }

  /// 执行 root shell 命令
  Future<bool> _runRootCmd(String cmd) async {
    final result = await Process.run('su', ['-c', cmd]);
    return result.exitCode == 0;
  }

  /// 初始化并释放 assets/armeabi-v7a 下的二进制到 basePath
  /// [abis] 可选，优先按 abi 顺序查找（如 arm64-v8a, armeabi-v7a, x86...）
  Future<void> initBinaries({List<String> abis = const ['armeabi-v7a']}) async {
    final binaries = ['redsocks', 'proxy.sh', 'gost.sh', 'cntlm', 'gost'];
    for (final bin in binaries) {
      String? assetPath;
      for (final abi in abis) {
        final tryPath = 'assets/$abi/$bin';
        try {
          await rootBundle.load(tryPath);
          assetPath = tryPath;
          break;
        } catch (_) {}
      }
      if (assetPath == null) {
        // 未找到该架构下的二进制
        continue;
      }
      final bytes = await rootBundle.load(assetPath);
      final file = File('$basePath$bin');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await _runRootCmd('chmod 700 $basePath$bin');
    }
  }
}

/// 说明：
/// 1. redsocks、proxy.sh、gost.sh、cntlm 等二进制建议放在 /data/data/org.proxydroid/ 并赋予 700 权限。
/// 2. redsocks.conf 配置文件也应放在 basePath 目录下。
/// 3. 需 root 权限执行 iptables 及 redsocks。
