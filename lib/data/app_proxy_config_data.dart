import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppProxyConfigData {
  // 定义一个路径变量
  final String _configName;

  // 创建一个构造方法 带一个路径参数
  AppProxyConfigData(this._configName) {
    if (kDebugMode) {
      print("AppData:$_configName");
    }
  }

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();

    return directory.path;
  }

  Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/$_configName');
  }

  Future<bool> saveAppConfig(Map<String, bool> data) async {
    final file = await _localFile;
    try {
      // 将数据转换为json字符串
      String jsonString = jsonEncode(data);
      // 将json字符串写入文件
      file.writeAsStringSync(jsonString);
      return true;
    } catch (e) {
      if (kDebugMode) {
        print("saveAppConfig:$e");
      }
      return false;
    }
  }

  Future<Map<String, bool>> readAppConfig() async {
    try {
      final file = await _localFile;
      // 读取文件内容
      String jsonString = file.readAsStringSync();
      // 将json字符串转换为Map对象
      Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      // 将Map对象转换为Map<String, bool>对象
      Map<String, bool> data = Map<String, bool>.from(jsonMap);
      return data;
    } catch (e) {
      if (kDebugMode) {
        print("readAppConfig:$e");
      }
      return {};
    }
  }
}
