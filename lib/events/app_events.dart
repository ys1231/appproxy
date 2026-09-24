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
