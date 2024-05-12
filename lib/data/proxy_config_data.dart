import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

class ProxyConfigData {

  Map<String, dynamic> dataConfigs = {};
  // 标记只运行一次
  bool isrunning = false;

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/proxyConfig.json');
  }

  Future<File> addProxyConfig(Map<String, dynamic> data) async {
    final file = await _localFile;
    // Write the file
    dataConfigs[data['proxyName']!] = data;
    if (kDebugMode) {
      print("addProxyConfig:$dataConfigs");
    }
    return file.writeAsString(jsonEncode(dataConfigs),flush: true);
  }

  // 获取打印所有配置 只能执行一次
  Future<Map<String, dynamic>> readProxyConfig() async {
    try {
      if (isrunning){
        return dataConfigs;
      }
      isrunning = true;
      final file = await _localFile;
      String contents = await file.readAsString();
      dataConfigs = jsonDecode(contents);
      if (dataConfigs.isEmpty) {
        return {};
      }
      for (var key in dataConfigs.keys) {
        if (kDebugMode) {
          print("readProxyConfig:$key,${dataConfigs[key]}");
        }
      }
      return dataConfigs;
    } catch (e) {
      // If we encounter an error, return 0
      return dataConfigs;
    }
  }

}
