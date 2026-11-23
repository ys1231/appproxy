import 'dart:convert';

import 'package:flutter/foundation.dart';

// 创建一个全局的EventBus实例
// EventBus eventBus = EventBus();

// 传递需要代理的app包名
class AppProxyPackageList {
  final Set<String> _proxyPackageList = {};

  // AppProxyPackageList(this.appProxyPackageList);

  void add(String appPackageName) {
    if (kDebugMode) {
      print("add:$appPackageName");
    }
    _proxyPackageList.add(appPackageName);
  }

  /// 从"需要代理的包名集合"里移除一个包名
  void remove(String appPackageName) {
    if (kDebugMode) {
      print("remove:$appPackageName");
    }
    _proxyPackageList.remove(appPackageName);
  }

  /// 清空集合（"全不选"时调用）
  void clear() {
    if (kDebugMode) {
      print("clear appPackageName");
    }
    _proxyPackageList.clear();
  }

  /// 导出为 JSON 字符串（原生侧解析用）
  String getListString() {
    if (kDebugMode) {
      print("getList:${_proxyPackageList.toList()}");
    }
    return jsonEncode(_proxyPackageList.toList());
  }

  /// 原始列表（eBPF 的 config.json 生成用：直接写进 include_package）
  List<String> getList() {
    return _proxyPackageList.toList();
  }
}
// 保存已选择的app
AppProxyPackageList appProxyPackageList = AppProxyPackageList();

/// 当前设备上存在"分身/多开"（同包名在其它 Android 用户里也有安装）的包名集合。
/// 应用列表页扫描后刷新；启动 VPN 引擎时用于提示系统限制（VPN 无法接管其它用户）。
class MultiUserPackages {
  final Set<String> _packages = {};

  void replace(Iterable<String> names) {
    _packages
      ..clear()
      ..addAll(names);
  }

  bool intersects(Iterable<String> names) => names.any(_packages.contains);

  Set<String> get all => {..._packages};
}

MultiUserPackages multiUserPackages = MultiUserPackages();
