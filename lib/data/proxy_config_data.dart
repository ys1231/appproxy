import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

class ProxyConfigData {

  // List<Map<String, dynamic>> dataConfiglists = [ ];

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/proxyConfig.json');
  }

  Future<void> addProxyConfig(List<Map<String, dynamic>>  data) async {
    final file = await _localFile;
    // Write the file
    if (data.isEmpty ){
      return ;
    }
    // if (dataConfiglists.any((item) => item['proxyName'] == data['proxyName'])) {
    //   if (kDebugMode) {
    //     print("addProxyConfig Data already exists in the list, skipping.");
    //   }
    // }else{
    //   dataConfiglists.add(data);
    // }
    if (kDebugMode) {
      print("addProxyConfig:$data");
    }
    String jsonString = jsonEncode(data);
    file.writeAsStringSync(jsonString);
    return ;
  }

  Future<void> deleteProxyConfig(List<Map<String, dynamic>>  data) async {
    final file = await _localFile;
    // Write the file
    if (data.isEmpty ){
      return;
    }
    if (kDebugMode) {
      print("delete ProxyConfig:$data");
    }
    String jsonString = jsonEncode(data);
    file.writeAsStringSync(jsonString);
    return;
  }

  // 获取打印所有配置 只能执行一次
  Future<List<Map<String, dynamic>>?> readProxyConfig() async {
    try {
      final file = await _localFile;
      String contents = file.readAsStringSync();
      List<dynamic> decodedList = jsonDecode(contents);
      List<Map<String, dynamic>> dataConfiglists=[];
      for (var item in decodedList) {
        assert(item is Map<String, dynamic>);
        dataConfiglists.add(item);
      }
      if (dataConfiglists.isEmpty) {
        return null;
      }
      if(kDebugMode){
        for (var i = 0; i < dataConfiglists.length; i++){
          print("readProxyConfig:${dataConfiglists[i]}");
        }
      }
      return dataConfiglists;
    } catch (e) {
      // If we encounter an error, return 0
      if(kDebugMode){
        print("readProxyConfig: fail $e");
      }
      return null;
    }
  }

}
