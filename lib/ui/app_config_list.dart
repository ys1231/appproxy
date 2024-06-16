import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:appproxy/data/app_proxy_config_data.dart';
import 'package:appproxy/events/app_events.dart';
import 'package:lpinyin/lpinyin.dart';

class AppConfigList extends StatefulWidget {
  const AppConfigList({super.key});

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

  /**
   * 静态常量平台通道定义
   * 该方法不接受任何参数，也不返回任何值。
   * 它主要用于定义与原生平台通信的方法通道名称。
   */
  static const platform = MethodChannel('cn.ys1231/appproxy');

  // 当前选中的app列表
  late final Map<String, bool> _selectedItemsMap;

  // app列表配置文件
  final AppProxyConfigData _appfile = AppProxyConfigData("proxyconfig.json");

  // 用于更新调用子控件列表项选择状态
  List<GlobalKey<CardCheckboxState>> _cardKeys = [];

  @override
  void initState() {
    super.initState();
    debugPrint("iyue-> initState");
    _initData().then((value) => null);
  }

  // 初始化数据
  Future<void> _initData() async {
    _selectedItemsMap = await _appfile.readAppConfig();
    // 同步已选择历史数据
    for (var key in _selectedItemsMap.keys) {
      if (_selectedItemsMap[key] == true) {
        appProxyPackageList.add(key);
      }
    }
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

  void updateShowSystemApp(isShowSystemApp) {
    _isShowSystemApp = isShowSystemApp;
    setState(() {
      getAppList();
      // _selectedItemsMap.clear();
      debugPrint("updateShowSystemApp:$isShowSystemApp");
    });
  }

  void updateSelectAll(isSelectAll) {
    setState(() {
      debugPrint("updateSelectAll:$isSelectAll");
      if (isSelectAll) {
        for (var app in _jsonAppListInfo) {
          _selectedItemsMap[app["packageName"]] = true;
          // 添加到代理列表
          appProxyPackageList.add(app["packageName"]);
        }
      } else {
        _selectedItemsMap.clear();
        appProxyPackageList.clear();
      }
      // 并且更新本地数据
      _appfile.saveAppConfig(_selectedItemsMap);
    });
  }

  // 远程调用获取Android 应用列表
  Future<bool> getAppList() async {
    try {
      if (!_useCached || _cachedAppListInfo.isEmpty) {
        // 清理缓存数据
        _cachedAppListInfo.clear();
        // 远程调用获取应用列表
        final appList = await platform.invokeMethod('getAppList');
        _cachedAppListInfo = jsonDecode(appList);
        // 获取之后使用缓存数据
        _useCached = true;
        debugPrint("call update app list!");
      }

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

      // 把已选择的移到前面去
      _jsonAppListInfo.sort((a, b) {
        bool? itemASelected = _selectedItemsMap[a["packageName"]] ?? false;
        bool? itemBSelected = _selectedItemsMap[b["packageName"]] ?? false;
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

  void _searchApp(String searchText) {
    _searchAppListInfo.clear();

    // 遍历当前显示的应用列表
    if (searchText.isNotEmpty) {
      _searchAppListInfo = _jsonAppListInfo.where((itemMap) {
        String label =
            PinyinHelper.getShortPinyin(itemMap["label"]).toLowerCase();
        return label.startsWith(searchText.toLowerCase()) ||
            itemMap["label"].toLowerCase().startsWith(searchText.toLowerCase());
      }).toList();
    }
    if (_searchAppListInfo.isNotEmpty) {
      // _searchAppListInfo = _jsonAppListInfo;
      debugPrint(
          "searchApp:${_searchAppListInfo.length} , all: $_searchAppListInfo");
    } else {
      _searchAppListInfo = _jsonAppListInfo.toList();
    }
    setState(() {});
  }

  void exitSearch() {
    setState(() {
      debugPrint("exitSearch");
      _showSearch = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    /**
     * 构建一个FutureBuilder，用于根据计算的状态显示不同的内容。
     * @return 返回一个FutureBuilder，根据计算的状态显示加载动画、错误信息或计算结果。
     */
    return Scaffold(
      appBar: AppBar(
          title: const Text('AppConfigList'),
          backgroundColor: Theme.of(context).primaryColor,
          actions: <Widget>[
            AnimatedCrossFade(
                crossFadeState: _showSearch
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
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
                            FocusScope.of(context)
                                .requestFocus(_searchFocusNode);
                          });
                        }
                      });
                    },
                    icon: const Icon(Icons.search)),
                secondChild: SizedBox(
                  key: const ValueKey(2),
                  width: 150,
                  child: TextField(
                    controller: _searchController,
                    cursorColor: Colors.black54,
                    autofocus: true,
                    focusNode: _searchFocusNode,
                    decoration: const InputDecoration(
                        hintText: ' 搜索应用',
                        // hintStyle: TextStyle(color: Colors.white),
                        border: InputBorder.none),
                    style: const TextStyle(color: Colors.white),
                    onChanged: (value) {
                      debugPrint("search: -------- onChanged ----- $value");
                      _searchApp(value);
                    },
                    onTapOutside: (event) {
                      debugPrint("search: -------- onTapOutside ----- $event");
                      Future.delayed(const Duration(milliseconds: 100), () {
                        exitSearch();
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
                  }
                },
                itemBuilder: (BuildContext context) {
                  return [
                    CheckedPopupMenuItem<AppOption>(
                      checked: _selectAll,
                      value: AppOption.selectAll,
                      child: const Text('全选'),
                    ),
                    CheckedPopupMenuItem<AppOption>(
                      checked: _showUserAppSelected,
                      value: AppOption.showUserApp,
                      child: const Text('显示用户应用'),
                    ),
                    CheckedPopupMenuItem<AppOption>(
                        checked: _showSystemAppSelected,
                        value: AppOption.showSystemApp,
                        child: const Text('显示系统应用'))
                  ];
                })
          ]),
      body: FutureBuilder(
          future: getAppList(), // 用于FutureBuilder的异步计算
          builder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
            // 异步快照的构建器回调
            // 当计算状态为等待时，显示加载动画
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                // 显示一个加载动画
                child: CircularProgressIndicator(),
              );
            } else if (snapshot.hasError) {
              // 当计算出现错误时，显示错误信息
              return Center(
                child: Text('Error: ${snapshot.error}'),
              );
            } else {
              // 够建用于调用子控件CheckBox的key
              _cardKeys.clear();
              _cardKeys = List.generate(
                  _itemCount, (index) => GlobalKey<CardCheckboxState>());
              // 带刷新的动态列表
              return RefreshIndicator(
                onRefresh: () {
                  // 当调用此函数时，会延迟1秒后执行[getAppList]函数
                  return Future.delayed(const Duration(milliseconds: 500), () {
                    // 下拉刷新触发整个重新build
                    setState(() {
                      _useCached = false;
                      debugPrint("onRefresh");
                    });
                  });
                },
                // 带滚动条的列表
                child: Scrollbar(
                  // 列表
                  child: ListView.separated(
                    // 创建从边缘反弹的滚动物理效果。
                    physics: const BouncingScrollPhysics(),
                    // 返回一个零尺寸的SizedBox
                    separatorBuilder: (BuildContext context, int index) =>
                        const SizedBox.shrink(),
                    // 列表项数量
                    itemCount:
                        _showSearch ? _searchAppListInfo.length : _itemCount,
                    // 列表项构建器
                    itemBuilder: (BuildContext context, int c_index) {
                      Map<String, dynamic> itemMap = _showSearch
                          ? _searchAppListInfo[c_index]
                          : _jsonAppListInfo[c_index];
                      // 返回一个卡片
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 10.0, vertical: 3.0),
                        key: ValueKey(c_index),
                        // 列表项内容
                        child: ListTile(
                            // 设置水平标题间距
                            horizontalTitleGap: 20,
                            // textColor:Colors.deepOrangeAccent,
                            // 设置内容内边距
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 0.0, horizontal: 16.0),
                            // 显示一个图标icon
                            leading: SizedBox(
                              width: 38, // 设置宽度
                              height: 38, // 设置高度
                              child: Image.memory(
                                base64Decode(itemMap["iconBytes"]),
                                fit: BoxFit.cover, // 保持图片的宽高比
                              ),
                            ),
                            // 标题
                            title: Text(itemMap["label"]),
                            // 副标题
                            subtitle: Text(itemMap["packageName"]),
                            // 显示一个复选框
                            trailing: CardCheckbox(
                                key: _cardKeys[c_index],
                                // 根据是否选中列表初始化状态
                                isSelected:
                                    _selectedItemsMap[itemMap["packageName"]] ??
                                        false,
                                // 子控件回调这个函数更新界面对应的数据
                                callbackOnChanged: (newValue) {
                                  // 如果选中了，添加到代理列表
                                  _selectedItemsMap[itemMap["packageName"]] =
                                      newValue;
                                  // 并且更新本地数据
                                  _appfile.saveAppConfig(_selectedItemsMap);
                                  if (newValue) {
                                    // 添加到代理列表
                                    appProxyPackageList
                                        .add(itemMap["packageName"]);
                                  } else {
                                    appProxyPackageList
                                        .remove(itemMap["packageName"]);
                                  }
                                }),
                            onTap: () {
                              // 调用子控件选择或取消选中 并回调 callbackOnChanged 更新数据
                              _cardKeys[c_index].currentState!.toggleCheckbox();
                              debugPrint("onTap:${itemMap["packageName"]}");
                            }),
                      );
                    },
                  ),
                ),
              );
            }
          }),
    );
  }
}

class CardCheckbox extends StatefulWidget {
  CardCheckbox(
      {super.key, required this.isSelected, required this.callbackOnChanged});

  // 构造函数
  Function(bool) callbackOnChanged;
  bool isSelected;

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
