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

  /// 整表写回代理配置（新增/修改/删除后都调它，覆盖写 proxyConfig.json）
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

  /// 整表写回代理配置（删除场景，与 addProxyConfig 同为覆盖写）
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

  /// 把配置文件读成字节（备份用，交给系统"保存文件"对话框写出）
  Future<Uint8List> toBytes() async{
    final file = await _localFile;
    try{
      return file.readAsBytesSync();
    }catch(e){
      debugPrint(e.toString());
      return Uint8List(0);
    }
  }

  /// 用备份文件的内容覆盖本地配置（还原用）
  Future<bool> fromBytes(Uint8List bytes) async{
    final file = await _localFile;
    try{
      file.writeAsBytesSync(bytes);
      return true;
    }catch(e){
      debugPrint(e.toString());
      return false;
    }
  }

}
