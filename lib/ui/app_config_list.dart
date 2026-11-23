import 'dart:convert';
import 'dart:isolate';

import 'package:appproxy/data/app_proxy_config_data.dart';
import 'package:appproxy/events/app_events.dart';
import 'package:appproxy/generated/l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinyin/pinyin.dart';

class AppConfigList extends StatefulWidget {
  const AppConfigList({super.key});

  /// 创建 State
  @override
  State<AppConfigList> createState() => AppConfigState();
}

enum AppOption {
  // 全选
  selectAll,
  // 用户app
  showUserApp,
  // 系统app
  showSystemApp,
  // 扫描分身/多开（隐藏用户，需要 root）
  scanClones,
}

Future<List> invokeGetAppList(token, {bool includeRoot = false}) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  /**
   * 静态常量平台通道定义
   * 该方法不接受任何参数，也不返回任何值。
   * 它主要用于定义与原生平台通信的方法通道名称。
   */
  const platform = MethodChannel('cn.ys1231/appproxy');
  // 远程调用获取应用列表（includeRoot=true 时会额外枚举隐藏用户，可能请求 root）
  final appListString = await platform.invokeMethod(
    'getAppList',
    {'includeRoot': includeRoot},
  );
  List<dynamic> rawList = jsonDecode(appListString);

  // 处理每个应用的信息，包括 base64 解码
  List<Map<String, dynamic>> processedList = rawList.map((item) {
    Map<String, dynamic> processedItem = Map<String, dynamic>.from(item);

    // 检查并解码 iconBytes
    if (processedItem.containsKey("iconBytes") && processedItem["iconBytes"] != null) {
      try {
        Uint8List iconData = base64Decode(processedItem["iconBytes"]);
        processedItem["iconBytes"] = iconData.isEmpty ? null : iconData;
      } catch (e) {
        debugPrint("Error decoding iconBytes for app: ${processedItem["packageName"]}: $e");
        // 如果解码失败，可以设置为 null 或保留原始 base64 字符串
        processedItem["iconBytes"] = null;
      }
    }

    return processedItem;
  }).toList();

  return processedList;
}

Future<List> getAppListInIsolate({bool includeRoot = false}) async {
  RootIsolateToken rootIsolateToken = RootIsolateToken.instance!;
  // 其它线程获取应用列表
  return Isolate.run(
      () => invokeGetAppList(rootIsolateToken, includeRoot: includeRoot));
}

class AppConfigState extends State<AppConfigList> {
  var _itemCount = 0;

  // 所有app列表
  List _jsonAppListInfo = [];

  // 缓存列表
  List _cachedAppListInfo = [];

  // 用户app列表
  List _userAppListInfo = [];

  // 系统app列表
  List _systemAppListInfo = [];

  // 搜索结果列表
  List _searchAppListInfo = [];

  // 默认显示用户安装的app
  bool _isShowUserApp = true;

  // 默认不显示系统app
  bool _isShowSystemApp = false;

  // 是否使用缓存数据
  bool _useCached = false;

  // 是否已请求过扫描隐藏用户（分身/多开）；由右上角菜单主动触发，避免启动即弹 root
  bool _scanRootClones = false;

  // 包名 -> 出现在几个用户里（>1 表示有分身；只用于决定是否显示用户号徽标）
  Map<String, int> _packageUserCounts = {};

  // 新增菜单项支持选择用户app和系统app以及全选等动态避免刷新ui时始终不变
  bool _showUserAppSelected = true;
  bool _showSystemAppSelected = false;

  // 是否全选
  bool _selectAll = false;

  // 显示搜索框
  bool _showSearch = false;

  // 搜索框控制器
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // 当前选中的 app：key = UID 字符串（同一包名的主应用/分身 UID 不同）
  Map<String, bool> _selectedItemsMap = {};

  // app列表配置文件
  final AppProxyConfigData _appfile = AppProxyConfigData("proxyconfig.json");

  // 远程调用通道
  final platform = const MethodChannel('cn.ys1231/appproxy');

  // 用于更新调用子控件列表项选择状态
  List<GlobalKey<CardCheckboxState>> _cardKeys = [];

  // app bar
  bool _appActionSearchHide = false;

  /// 初始化数据：勾选表现在按 UID 存储（key = uid 字符串）
  Future<void> _initData() async {
    _selectedItemsMap = await _appfile.readAppConfig();
    // 先用已保存的 UID 填充全局选择，eBPF 在列表加载完成前也能拿到准确 UID；
    // 包名/用户等元数据等 getAppList 后由 _rebuildSelection 补齐。
    final uids = <int>[];
    for (final entry in _selectedItemsMap.entries) {
      if (entry.value != true) continue;
      final uid = int.tryParse(entry.key);
      if (uid != null && uid > 0) uids.add(uid);
    }
    if (uids.isNotEmpty) {
      appProxySelection.replaceUids(uids);
    }
  }

  /// 初始化：注册原生"应用列表已刷新"回调 + 载入已保存的分应用勾选
  @override
  void initState() {
    super.initState();
    debugPrint("iyue-> initState");
    _initData().then((_) {
      if (mounted) getAppList();
    });
    platform.setMethodCallHandler((call) async {
      if (call.method == 'onRefresh') {
        // 执行Flutter逻辑
        _useCached = false;
        getAppList();
      }
    });
  }

  String _uidKey(Map<dynamic, dynamic> app) =>
      '${(app['uid'] as num?)?.toInt() ?? 0}';

  /// 旧版本按包名保存勾选；加载列表后迁移成“所有同名实例的 UID 都选中”
  void _migrateLegacySelection() {
    var changed = false;
    final legacyKeys = _selectedItemsMap.keys
        .where((k) => int.tryParse(k) == null)
        .toList();
    for (final key in legacyKeys) {
      final selected = _selectedItemsMap[key] == true;
      if (selected) {
        for (final app in _cachedAppListInfo) {
          if ((app['packageName'] ?? '').toString() == key) {
            final uid = (app['uid'] as num?)?.toInt() ?? 0;
            if (uid > 0) _selectedItemsMap['$uid'] = true;
          }
        }
      }
      _selectedItemsMap.remove(key);
      changed = true;
    }
    if (changed) {
      _appfile.saveAppConfig(_selectedItemsMap);
      debugPrint('migrateLegacySelection: ${legacyKeys.length} legacy keys');
    }
  }

  /// 根据完整应用列表重建全局选择（含 UID/包名/是否分身）。
  ///
  /// 已选 UID 若当前列表里没有（重启后未扫描隐藏用户/分身），仍保留 UID：
  /// eBPF 可以继续按 UID 精确代理；VPN 则标记 metadataReady=false 让启动流程
  /// 提示先扫描，避免把“有选择”误当成“全机代理”。
  void _rebuildSelection() {
    final selected = <AppProxyEntry>[];
    final found = <int>{};
    for (final app in _cachedAppListInfo) {
      final uid = (app['uid'] as num?)?.toInt() ?? 0;
      if (uid <= 0) continue;
      if (_selectedItemsMap['$uid'] != true) continue;
      found.add(uid);
      selected.add(AppProxyEntry(
        uid: uid,
        userId: (app['userId'] as num?)?.toInt() ?? 0,
        packageName: (app['packageName'] ?? '').toString(),
        multiUser: app['multiUser'] == true,
      ));
    }
    var incomplete = false;
    for (final entry in _selectedItemsMap.entries) {
      if (entry.value != true) continue;
      final uid = int.tryParse(entry.key);
      if (uid == null || uid <= 0 || found.contains(uid)) continue;
      // 当前用户 id 由 UID 推算（app UID = userId*100000 + appId）
      final userId = uid ~/ 100000;
      selected.add(AppProxyEntry(
        uid: uid,
        userId: userId,
        packageName: '',
        multiUser: userId != 0,
      ));
      incomplete = true;
    }
    appProxySelection.replaceAll(selected, metadataReady: !incomplete);
    debugPrint('rebuildSelection: ${appProxySelection.debugSummary()} '
        'incomplete=$incomplete');
  }



  // 更新选项
  void updateShowUserApp(isShowUserApp) {
    _isShowUserApp = isShowUserApp;
    setState(() {
      getAppList();
      // _selectedItemsMap.clear();
      debugPrint("updateShowUserApp:$isShowUserApp");
    });
  }

  /// 切换"是否显示系统应用"（只影响展示与计数，不改勾选）
  void updateShowSystemApp(isShowSystemApp) {
    _isShowSystemApp = isShowSystemApp;
    setState(() {
      getAppList();
      // _selectedItemsMap.clear();
      debugPrint("updateShowSystemApp:$isShowSystemApp");
    });
  }

  /// 全选/全不选：批量更新勾选（按 UID），并同步全局选择
  void updateSelectAll(isSelectAll) {
    setState(() {
      debugPrint("updateSelectAll:$isSelectAll");
      if (isSelectAll) {
        for (var app in _jsonAppListInfo) {
          final uid = (app["uid"] as num?)?.toInt() ?? 0;
          if (uid > 0) _selectedItemsMap['$uid'] = true;
        }
      } else {
        _selectedItemsMap.clear();
      }
      _appfile.saveAppConfig(_selectedItemsMap);
      _rebuildSelection();
    });
  }

  /// 整理原生应用列表：**每个用户/分身单独一行**，每行有自己的 UID。
  ///
  /// 勾选按 UID 保存，所以主应用（用户 0）和分身（如用户 999）可以分别选择。
  List<Map<String, dynamic>> _prepareAppList(List raw) {
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    final counts = <String, int>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final pkg = (item['packageName'] ?? '').toString();
      if (pkg.isEmpty) continue;
      final userId = (item['userId'] as num?)?.toInt() ?? 0;
      final uid = (item['uid'] as num?)?.toInt() ?? 0;
      if (uid <= 0) continue;
      final key = '$userId/$pkg';
      if (!seen.add(key)) continue;
      final copy = Map<String, dynamic>.from(item);
      copy['userId'] = userId;
      copy['uid'] = uid;
      copy['multiUser'] = item['multiUser'] == true;
      result.add(copy);
      counts[pkg] = (counts[pkg] ?? 0) + 1;
    }
    // 让同一包名的原应用/分身相邻显示，便于对照
    result.sort((a, b) {
      final byPkg = (a['packageName'] ?? '')
          .toString()
          .compareTo((b['packageName'] ?? '').toString());
      if (byPkg != 0) return byPkg;
      return ((a['userId'] as num?)?.toInt() ?? 0)
          .compareTo((b['userId'] as num?)?.toInt() ?? 0);
    });
    _packageUserCounts = counts;
    debugPrint("prepareAppList: ${result.length} rows");
    return result;
  }

  /// 应用副标题：包名
  String _appSubtitle(S s, Map<String, dynamic> item) {
    return (item['packageName'] ?? '').toString();
  }

  // 远程调用获取Android 应用列表
  Future<bool> getAppList() async {
    try {
      if (!_useCached || _cachedAppListInfo.isEmpty) {
        // 清理缓存数据
        _cachedAppListInfo.clear();
        // 多线程获取应用列表
        debugPrint("iyue-> call  getAppListInIsolate");
        _cachedAppListInfo = _prepareAppList(
            await getAppListInIsolate(includeRoot: _scanRootClones));
        debugPrint("iyue-> call  getAppListInIsolate end");
        // 获取之后使用缓存数据
        _useCached = true;
        debugPrint("call update app list!");
        setState(() {});
      }

      // 旧包名勾选迁移到 UID，并重建全局选择（每行按 UID 独立）
      _migrateLegacySelection();
      _rebuildSelection();

      _jsonAppListInfo.clear();
      _systemAppListInfo.clear();
      _userAppListInfo.clear();
      for (Map<String, dynamic> appInfo in _cachedAppListInfo) {
        if (appInfo["isSystemApp"]) {
          _systemAppListInfo.add(appInfo);
        } else {
          _userAppListInfo.add(appInfo);
        }
      }

      // 是否显示系统应用
      if (_isShowSystemApp) {
        _jsonAppListInfo.addAll(_systemAppListInfo);
      }
      // 是否显示用户应用
      if (_isShowUserApp) {
        _jsonAppListInfo.addAll(_userAppListInfo);
      }

      // 把已选择的移到前面去（按 UID 判断，主应用/分身可独立）
      _jsonAppListInfo.sort((a, b) {
        bool? itemASelected = _selectedItemsMap[_uidKey(a)] ?? false;
        bool? itemBSelected = _selectedItemsMap[_uidKey(b)] ?? false;
        // 如果两个都未选中，保持原顺序
        if (!itemASelected && !itemBSelected) return 0;
        // 如果A被选中，放在前面
        if (itemASelected && !itemBSelected) return -1;
        // 如果B被选中，放在前面
        if (!itemASelected && itemBSelected) return 1;
        // 如果两个都已选中，按原始顺序
        return 0;
      });
      _itemCount = _jsonAppListInfo.length;

      return true;
    } on PlatformException catch (e) {
      debugPrint("Failed to get app list: '${e.message}'.");
      return false;
    } catch (e) {
      debugPrint('An unexpected error happened: $e');
      return false;
    }
  }

  /// 按关键字过滤列表（匹配应用名或包名）
  void _searchApp(String searchText) {
    _searchAppListInfo.clear();

    // 遍历当前显示的应用列表
    if (searchText.isNotEmpty) {
      _searchAppListInfo = _jsonAppListInfo.where((itemMap) {
        final label = itemMap["label"] +
            PinyinHelper.getShortPinyin(itemMap["label"]).toLowerCase() +
            itemMap["packageName"];
        final search = searchText.toLowerCase();
        return label.contains(search);
      }).toList();
    }
    if (_searchAppListInfo.isNotEmpty) {
      // _searchAppListInfo = _jsonAppListInfo;
      debugPrint("searchApp:${_searchAppListInfo.length} , all: $_searchAppListInfo");
    } else {
      _searchAppListInfo = _jsonAppListInfo.toList();
    }
    setState(() {});
  }

  /// 退出搜索：清空关键字、恢复完整列表
  void exitSearch() {
    setState(() {
      debugPrint("exitSearch");
      _showSearch = false;
      _appActionSearchHide = false;
    });
  }

  /// 构建应用列表（顶部搜索/过滤栏 + 应用卡片列表）
  @override
  Widget build(BuildContext context) {
    /**
     * 构建一个FutureBuilder，用于根据计算的状态显示不同的内容。
     * @return 返回一个FutureBuilder，根据计算的状态显示加载动画、错误信息或计算结果。
     */
    // 够建用于调用子控件CheckBox的key
    _cardKeys.clear();
    _cardKeys = List.generate(_itemCount, (index) => GlobalKey<CardCheckboxState>());

    return Scaffold(
        appBar: AppBar(
            title: Text('APP ${S.of(context).text_app_config_list}'),
            backgroundColor: Theme.of(context).primaryColor,
            actions: <Widget>[
              AnimatedCrossFade(
                  crossFadeState:
                      _showSearch ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  firstChild: IconButton(
                      key: const ValueKey(1),
                      autofocus: true,
                      onPressed: () {
                        debugPrint("click search");
                        setState(() {
                          _showSearch = !_showSearch;
                          if (_showSearch) {
                            _searchController.clear();
                            _searchApp("");
                            Future.delayed(const Duration(milliseconds: 100), () {
                              FocusScope.of(context).requestFocus(_searchFocusNode);
                            });
                          }
                        });
                      },
                      icon: const Icon(Icons.search)),
                  secondChild: SizedBox(
                    key: const ValueKey(2),
                    width: 150,
                    child: TextField(
                      key: const ValueKey(3),
                      controller: _searchController,
                      cursorColor: Colors.black54,
                      autofocus: true,
                      focusNode: _searchFocusNode,
                      decoration: InputDecoration(
                          hintText: S.of(context).text_search_app,
                          // hintStyle: TextStyle(color: Colors.white),
                          border: InputBorder.none),
                      style: const TextStyle(color: Colors.white),
                      onChanged: (value) {
                        debugPrint("search: -------- onChanged ----- $value");
                        _searchApp(value);
                      },
                      onTapOutside: (PointerDownEvent event) {
                        Future.delayed(const Duration(milliseconds: 200), () {
                          if (_appActionSearchHide) {
                            exitSearch();
                          }
                        });
                      },
                    ),
                  ),
                  duration: const Duration(microseconds: 10)),
              PopupMenuButton(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (AppOption value) {
                    switch (value) {
                      case AppOption.selectAll:
                        _selectAll = !_selectAll;
                        updateSelectAll(_selectAll);
                        break;
                      case AppOption.showUserApp:
                        _showUserAppSelected = !_showUserAppSelected;
                        updateShowUserApp(_showUserAppSelected);
                        _selectAll = false;
                        break;
                      case AppOption.showSystemApp:
                        _showSystemAppSelected = !_showSystemAppSelected;
                        updateShowSystemApp(_showSystemAppSelected);
                        _selectAll = false;
                        break;
                      case AppOption.scanClones:
                        // 隐藏用户（应用分身/多开）只有 root 能枚举；
                        // 只在用户主动选择时触发，避免打开 App 就弹授权框
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(S.of(context).text_scan_clones_hint)));
                        setState(() {
                          _scanRootClones = true;
                          _useCached = false;
                          getAppList();
                        });
                        break;
                    }
                  },
                  itemBuilder: (BuildContext context) {
                    return [
                      CheckedPopupMenuItem<AppOption>(
                        checked: _selectAll,
                        value: AppOption.selectAll,
                        child: Text(S.of(context).text_select_all),
                      ),
                      CheckedPopupMenuItem<AppOption>(
                        checked: _showUserAppSelected,
                        value: AppOption.showUserApp,
                        child: Text(S.of(context).text_show_user_app),
                      ),
                      CheckedPopupMenuItem<AppOption>(
                          checked: _showSystemAppSelected,
                          value: AppOption.showSystemApp,
                          child: Text(S.of(context).text_show_system_app)),
                      CheckedPopupMenuItem<AppOption>(
                          checked: _scanRootClones,
                          value: AppOption.scanClones,
                          child: Text(S.of(context).text_scan_clones))
                    ];
                  })
            ]),
        body: RefreshIndicator(
          onRefresh: () {
            // 当调用此函数时，会延迟1秒后执行[getAppList]函数
            return Future.delayed(const Duration(milliseconds: 500), () {
              debugPrint("onRefresh");
              setState(() {
                _useCached = false;
                getAppList();
              });
            });
          },
          // 带滚动条的列表
          child: _useCached
              ? Scrollbar(
                  // 列表
                  child: ListView.separated(
                    // 创建从边缘反弹的滚动物理效果。
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    // 返回一个零尺寸的SizedBox
                    separatorBuilder: (BuildContext context, int index) => const SizedBox.shrink(),
                    // 列表项数量
                    itemCount: _showSearch ? _searchAppListInfo.length : _itemCount,
                    // 列表项构建器
                    itemBuilder: (BuildContext context, int c_index) {
                      Map<String, dynamic> itemMap =
                          _showSearch ? _searchAppListInfo[c_index] : _jsonAppListInfo[c_index];
                      // 返回一个卡片
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 3.0),
                        key: ValueKey(c_index),
                        // 列表项内容
                        child: ListTile(
                            // 设置水平标题间距
                            horizontalTitleGap: 20,
                            // textColor:Colors.deepOrangeAccent,
                            // 设置内容内边距
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 0.0, horizontal: 16.0),
                            // 显示一个图标icon
                            leading: SizedBox(
                              width: 38, // 设置宽度
                              height: 38, // 设置高度
                              child: itemMap["iconBytes"] != null // 保持图片的宽高比
                                  ? Image.memory(itemMap["iconBytes"], fit: BoxFit.cover)
                                  : const Icon(Icons.accessibility),
                            ),
                            // 标题（含分身时加标识）
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    '${itemMap["label"]}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                // 分身行始终显示用户号；主应用仅在“同包名有分身”时显示，
                                // 方便区分“用户 0 / 用户 999”并分别勾选
                                if (itemMap["multiUser"] == true ||
                                    ((_packageUserCounts[
                                                '${itemMap["packageName"]}'] ??
                                            1) >
                                        1)) ...[
                                  const SizedBox(width: 6.0),
                                  Builder(builder: (context) {
                                    final isClone = itemMap["multiUser"] == true;
                                    final color =
                                        isClone ? Colors.deepPurple : Colors.blueGrey;
                                    final userId =
                                        (itemMap["userId"] as num?)?.toInt() ?? 0;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5.0, vertical: 1.0),
                                      decoration: BoxDecoration(
                                        color: color.withAlpha(30),
                                        borderRadius: BorderRadius.circular(4.0),
                                        border: Border.all(color: color.withAlpha(100)),
                                      ),
                                      child: Text(
                                        '${S.of(context).app_user_prefix} $userId',
                                        style: TextStyle(fontSize: 10.0, color: color),
                                      ),
                                    );
                                  }),
                                ],
                              ],
                            ),
                            // 副标题：包名 + 分身所在用户/资料
                            subtitle: Text(
                              _appSubtitle(S.of(context), itemMap),
                              overflow: TextOverflow.ellipsis,
                            ),
                            // 显示一个复选框（按 UID 独立保存，主应用/分身互不影响）
                            trailing: CardCheckbox(
                                key: _cardKeys[c_index],
                                isSelected:
                                    _selectedItemsMap[_uidKey(itemMap)] ?? false,
                                callbackOnChanged: (newValue) {
                                  _appActionSearchHide = true;
                                  _selectedItemsMap[_uidKey(itemMap)] = newValue;
                                  _appfile.saveAppConfig(_selectedItemsMap);
                                  _rebuildSelection();
                                  setState(() {
                                    getAppList();
                                  });
                                }),
                            onTap: () {
                              // 调用子控件选择或取消选中 并回调 callbackOnChanged 更新数据
                              _cardKeys[c_index].currentState!.toggleCheckbox();
                              // 同时刷新列表,选中的会移到最顶上,或取消置顶
                              setState(() {
                                getAppList();
                              });
                              debugPrint("onTap:${itemMap["packageName"]}");
                            }),
                      );
                    },
                  ),
                )
              : const Center(child: CircularProgressIndicator()),
        ));
  }
}

class CardCheckbox extends StatefulWidget {
  CardCheckbox({super.key, required this.isSelected, required this.callbackOnChanged});

  // 构造函数
  Function(bool) callbackOnChanged;
  bool isSelected;

  /// 创建 State
  @override
  State<StatefulWidget> createState() => CardCheckboxState();
}

class CardCheckboxState extends State<CardCheckbox> {
  // 外部调用刷新checkbox
  void toggleCheckbox() {
    setState(() {
      // 触发刷新当前选中状态
      widget.isSelected = !widget.isSelected;
      // 调用回调函数更新数据
      widget.callbackOnChanged(widget.isSelected);
    });
  }

  /// 构建应用列表（顶部搜索/过滤栏 + 应用卡片列表）
  @override
  Widget build(BuildContext context) {
    return Checkbox(
      value: widget.isSelected,
      onChanged: (bool? newValue) {
        widget.callbackOnChanged(newValue!);
        setState(() {
          widget.isSelected = newValue;
        });
        // 如果需要，这里可以处理选中项的变化逻辑
        debugPrint("index:$widget.index,newValue:$newValue");
      },
    );
  }
}
