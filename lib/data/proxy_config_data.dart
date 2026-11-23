import 'dart:io';
import 'package:appproxy/data/ebpf_options.dart';
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

  /// 解析备份文件内容（还原用）
  ///
  /// 必须是 JSON 数组，且每个元素都是带非空 proxyName 的对象；否则返回 null。
  /// 避免用户选错文件/异常备份导致「还原成功但列表为空」或条目在读取时被静默丢弃。
  List<Map<String, dynamic>>? _parseBackup(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! List) {
        debugPrint('restore: 备份格式非法（不是 JSON 数组）');
        return null;
      }
      final result = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is! Map ||
            (item['proxyName'] ?? '').toString().trim().isEmpty) {
          debugPrint('restore: 备份格式非法（条目不是带 proxyName 的对象）');
          return null;
        }
        result.add(Map<String, dynamic>.from(item));
      }
      return result;
    } catch (e) {
      debugPrint('restore: 备份解析失败 $e');
      return null;
    }
  }

  /// 还原备份。
  ///
  /// [append] = true：**追加还原** —— 保留本机现有配置，只新增备份中不存在的配置
  /// （按 proxyName 判重，同名跳过，本机已有条目不会被覆盖）。
  /// [append] = false：**覆盖还原** —— 清空本机原有配置，完全写入备份内容。
  ///
  /// 写盘前先校验备份格式；格式非法时不改动机上数据。
  Future<RestoreResult> restoreFromBytes(Uint8List bytes, {bool append = false}) async {
    final backup = _parseBackup(bytes);
    if (backup == null) return const RestoreResult(ok: false);
    final file = await _localFile;

    if (!append) {
      try {
        file.writeAsBytesSync(bytes);
        return RestoreResult(ok: true, added: backup.length);
      } catch (e) {
        debugPrint('restore(overwrite): $e');
        return const RestoreResult(ok: false);
      }
    }

    final current = await readProxyConfig() ?? <Map<String, dynamic>>[];
    final r = mergeAppend(current, backup);
    // 没有新增且本机文件已存在时不用重写，避免无意义落盘
    if (r.added > 0 || !file.existsSync()) {
      try {
        file.writeAsStringSync(jsonEncode(r.merged));
      } catch (e) {
        debugPrint('restore(append): $e');
        return const RestoreResult(ok: false);
      }
    }
    return RestoreResult(ok: true, added: r.added, skipped: r.skipped);
  }

  /// 新增/编辑列表（纯函数，便于单测）。
  ///
  /// [oldName] 为空 = 新增；非空 = 编辑原条目，且允许把名字改成 [data] 里的新名字。
  /// 编辑时会先删除旧条目里的 eBPF 可调项再合并表单数据，
  /// 保证「改成默认 = 表单不携带该键」能真正删掉旧值。
  ///
  /// 重名时返回 ok=false（不改列表）。返回的 renamed 表示名称是否变化，
  /// 调用方据此迁移设置侧 eBPF 标记与运行中选中名。
  static ({
    bool ok,
    bool renamed,
    String sourceName,
    List<Map<String, dynamic>> list,
  }) applyEdit(
    List<Map<String, dynamic>> current,
    Map<String, dynamic> data, {
    String? oldName,
  }) {
    final newName = (data['proxyName'] ?? '').toString();
    if (oldName == null) {
      if (current.any((e) => (e['proxyName'] ?? '').toString() == newName)) {
        return (ok: false, renamed: false, sourceName: newName, list: current);
      }
      return (
        ok: true,
        renamed: false,
        sourceName: newName,
        list: [...current, data],
      );
    }

    final sourceName = oldName;
    if (sourceName != newName &&
        current.any((e) => (e['proxyName'] ?? '').toString() == newName)) {
      return (ok: false, renamed: false, sourceName: sourceName, list: current);
    }
    final index = current
        .indexWhere((e) => (e['proxyName'] ?? '').toString() == sourceName);
    if (index < 0) {
      // 原条目不存在（理论上不会发生）：按新增兜底
      if (current.any((e) => (e['proxyName'] ?? '').toString() == newName)) {
        return (ok: false, renamed: false, sourceName: sourceName, list: current);
      }
      return (
        ok: true,
        renamed: sourceName != newName,
        sourceName: sourceName,
        list: [...current, data],
      );
    }
    final item = current[index];
    item.removeWhere((key, _) =>
        EbpfAdvancedOptions.storageKeys.contains(key) ||
        key == 'ebpfDataPlane' ||
        key == 'ebpfNetwork');
    item.addAll(data);
    return (
      ok: true,
      renamed: sourceName != newName,
      sourceName: sourceName,
      list: current,
    );
  }

  /// 追加合并（纯函数，便于单测）：保留本机条目与顺序，只追加备份中不存在的名称。
  static ({List<Map<String, dynamic>> merged, int added, int skipped}) mergeAppend(
      List<Map<String, dynamic>> current, List<Map<String, dynamic>> backup) {
    final names = current.map((e) => (e['proxyName'] ?? '').toString()).toSet();
    final merged = List<Map<String, dynamic>>.from(current);
    var added = 0;
    var skipped = 0;
    for (final item in backup) {
      final name = (item['proxyName'] ?? '').toString();
      if (names.contains(name)) {
        skipped++;
        continue;
      }
      names.add(name);
      merged.add(Map<String, dynamic>.from(item));
      added++;
    }
    return (merged: merged, added: added, skipped: skipped);
  }
}

/// 还原结果：added = 写入/新增条数，skipped = 追加模式下因同名跳过的条数
class RestoreResult {
  final bool ok;
  final int added;
  final int skipped;

  const RestoreResult({required this.ok, this.added = 0, this.skipped = 0});
}
