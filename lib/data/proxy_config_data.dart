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
  Future<void> deleteProxyConfig(List<Map<String, dynamic>> data) async {
    final file = await _localFile;
    // 删除最后一条时也必须写入 []，否则旧 proxyConfig.json 会在下次启动时复活
    if (kDebugMode) {
      print("delete ProxyConfig:$data");
    }
    final jsonString = jsonEncode(data);
    file.writeAsStringSync(jsonString);
  }

  // 获取打印所有配置 只能执行一次
  Future<List<Map<String, dynamic>>?> readProxyConfig() async {
    try {
      final file = await _localFile;
      String contents = file.readAsStringSync();
      List<dynamic> decodedList = jsonDecode(contents);
      List<Map<String, dynamic>> dataConfiglists=[];
      for (var item in decodedList) {
        // 兼容手工编辑/异常备份：只接受对象条目，且必须有名称；
        // 旧代码用 assert 判断，debug 包遇到坏数据会直接崩溃
        if (item is Map) {
          final config = Map<String, dynamic>.from(item);
          if ((config['proxyName'] ?? '').toString().isEmpty) {
            continue;
          }
          dataConfiglists.add(config);
        }
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
  ///
  /// 覆盖前先校验备份内容：必须是 JSON 数组，且每个元素都是带非空 proxyName 的对象；
  /// 否则不写文件并返回 false。避免用户选错文件/异常备份导致「还原成功但列表为空」
  /// 或条目在读取时被静默丢弃。
  Future<bool> fromBytes(Uint8List bytes) async{
    try{
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! List) {
        debugPrint('fromBytes: 备份格式非法（不是 JSON 数组）');
        return false;
      }
      for (final item in decoded) {
        if (item is! Map ||
            (item['proxyName'] ?? '').toString().trim().isEmpty) {
          debugPrint('fromBytes: 备份格式非法（条目不是带 proxyName 的对象）');
          return false;
        }
      }
    }catch(e){
      debugPrint('fromBytes: 备份解析失败 $e');
      return false;
    }
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
