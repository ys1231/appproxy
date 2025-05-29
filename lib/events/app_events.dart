import 'dart:convert';

import 'package:flutter/foundation.dart';

// 保存包名和uid的类
class AppProxyPackage {
  final String packageName;
  final int uid;

  AppProxyPackage({required this.packageName, required this.uid});

  // 用于Set去重和比较
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppProxyPackage &&
          runtimeType == other.runtimeType &&
          packageName == other.packageName &&
          uid == other.uid;

  @override
  int get hashCode => packageName.hashCode ^ uid.hashCode;

  Map<String, dynamic> toJson() => {
        'packageName': packageName,
        'uid': uid,
      };
}

// 创建一个全局的EventBus实例
// EventBus eventBus = EventBus();

// 传递需要代理的app包名
class AppProxyPackageList {
  final Set<AppProxyPackage> _proxyPackageList = {};

  void add(String packageName, int uid) {
    if (kDebugMode) {
      print("add: $packageName, uid: $uid");
    }
    _proxyPackageList.add(AppProxyPackage(packageName: packageName, uid: uid));
  }

  void remove(String packageName, int uid) {
    if (kDebugMode) {
      print("remove: $packageName, uid: $uid");
    }
    _proxyPackageList
        .remove(AppProxyPackage(packageName: packageName, uid: uid));
  }

  void clear() {
    if (kDebugMode) {
      print("clear appPackageName");
    }
    _proxyPackageList.clear();
  }

  // 获取所有包名列表
  List<String> getPackageNames() {
    return _proxyPackageList.map((e) => e.packageName).toList();
  }

  // 获取所有uid列表
  List<int> getUids() {
    return _proxyPackageList.map((e) => e.uid).toList();
  }

  // 获取json字符串，包含packageName和uid
  String getPackagenameListString() {
    return jsonEncode(_proxyPackageList.map((e) => e.packageName).toList());
  }
}

// 保存已选择的app
AppProxyPackageList appProxyPackageList = AppProxyPackageList();
