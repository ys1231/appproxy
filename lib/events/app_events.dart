import 'dart:convert';

import 'package:event_bus/event_bus.dart';
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

  void remove(String appPackageName) {
    if (kDebugMode) {
      print("remove:$appPackageName");
    }
    _proxyPackageList.remove(appPackageName);
  }

  void clear() {
    if (kDebugMode) {
      print("clear appPackageName");
    }
    _proxyPackageList.clear();
  }

  String getListString() {
    if (kDebugMode) {
      print("getList:${_proxyPackageList.toList()}");
    }
    return jsonEncode(_proxyPackageList.toList());
  }
}

AppProxyPackageList appProxyPackageList = AppProxyPackageList();
