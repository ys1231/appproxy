import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/app_proxy_config_data.dart';

class AppConfigList extends StatefulWidget {
  const AppConfigList({super.key});

  @override
  State<AppConfigList> createState() => AppConfigState();
}

class AppConfigState extends State<AppConfigList> {
  var _itemCount = 0;
  List _jsonAppListInfo = [];
  List _userAppListInfo = [];
  List _systemAppListInfo = [];
  bool _isShowUserApp = true;
  bool _isShowSystemApp = true;
  static const platform = MethodChannel('cn.ys1231/appproxy');
  late final Map<String, bool> _selectedItemsMap;
  final AppProxyConfigData _appfile = AppProxyConfigData("proxyconfig.json");

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      print("iyue-> initState");
    }
    _initData().then((value) => null);
  }

  // 初始化数据
  Future<void> _initData() async {
    _selectedItemsMap = await _appfile.readAppConfig();
  }

  // 更新选项
  void updateShowUserApp(isShowUserApp) {
    _isShowUserApp = isShowUserApp;
    setState(() {
      getAppList();
      if (kDebugMode) {
        print("updateShowUserApp:$isShowUserApp");
      }
    });
  }

  void updateShowSystemApp(isShowSystemApp) {
    _isShowSystemApp = isShowSystemApp;
    setState(() {
      getAppList();
      if (kDebugMode) {
        print("updateShowSystemApp:$isShowSystemApp");
      }
    });
  }

  void updateSelectAll(isSelectAll) {
    setState(() {
      if (kDebugMode) {
        print("updateSelectAll:$isSelectAll");
      }
      if (isSelectAll){
        for (var app in _jsonAppListInfo) {
          _selectedItemsMap[app["packageName"]] = true;
        }
      }else{
        _selectedItemsMap.clear();
      }
    });
  }

  // 远程调用获取Android 应用列表
  Future<bool> getAppList() async {

    try {
      if (kDebugMode) {
        print("iyue-> getAppList");
      }

      // 远程调用获取应用列表
      final appList = await platform.invokeMethod('getAppList');
      List tmp = jsonDecode(appList);
      _jsonAppListInfo.clear();
      _systemAppListInfo.clear();
      _userAppListInfo.clear();
      for (Map<String, dynamic> appInfo in tmp) {
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
      if (kDebugMode) {
        print("Failed to get app list: '${e.message}'.");
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('An unexpected error happened: $e');
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      //   在当前帧构建完成后，调用onTitleChange
    });
    if (kDebugMode) {
      print("iyue-<build> _itemCount:$_itemCount");
    }
    /**
     * 构建一个FutureBuilder，用于根据计算的状态显示不同的内容。
     *
     * @return 返回一个FutureBuilder，根据计算的状态显示加载动画、错误信息或计算结果。
     */
    return FutureBuilder(
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
            // 带刷新的动态列表
            return RefreshIndicator(
              onRefresh: () {
                // 当调用此函数时，会延迟1秒后执行[getAppList]函数
                return Future.delayed(const Duration(seconds: 1), () {
                  setState(() {
                    if (kDebugMode) {
                      print("onRefresh");
                    }
                  });
                });
              },
              // 带滚动条的列表
              child: Scrollbar(
                // 列表
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  // 返回一个零尺寸的SizedBox
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox.shrink(),
                  // 列表项数量
                  itemCount: _itemCount,
                  // 列表项构建器
                  itemBuilder: (BuildContext context, int c_index) {
                    Map<String, dynamic> listItem = _jsonAppListInfo[c_index];
                    // 返回一个卡片
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8.0, vertical: 4.0),
                      key: ValueKey(c_index),
                      // 列表项内容
                      child: ListTile(
                        // 设置水平标题间距
                        horizontalTitleGap: 20,
                        // 设置内容内边距
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 0.0, horizontal: 16.0),
                        // 显示一个图标icon
                        leading: SizedBox(
                          width: 38, // 设置宽度
                          height: 38, // 设置高度
                          child: Image.memory(
                            base64Decode(listItem["iconBytes"]),
                            fit: BoxFit.cover, // 保持图片的宽高比
                          ),
                        ),
                        // 标题
                        title: Text(listItem["label"]),
                        // 副标题
                        subtitle: Text(listItem["packageName"]),
                        // 显示一个复选框
                        trailing: CardCheckbox(
                            isSelected:
                                _selectedItemsMap[listItem["packageName"]] ??
                                    false,
                            index: c_index,
                            callbackOnChanged: (newValue) {
                              _selectedItemsMap[listItem["packageName"]] =
                                  newValue;
                              _appfile.saveAppConfig(_selectedItemsMap);
                            }),
                      ),
                    );
                  },
                ),
              ),
            );
          }
        });
  }
}

class CardCheckbox extends StatefulWidget {
  CardCheckbox(
      {super.key,
      required this.isSelected,
      required this.index,
      required this.callbackOnChanged});

  // 构造函数
  Function(bool) callbackOnChanged;
  bool isSelected;
  int index = 0;

  @override
  State<StatefulWidget> createState() => _CardCheckboxState();
}

class _CardCheckboxState extends State<CardCheckbox> {
  void toggleCheckbox() {
    setState(() {
      widget.isSelected = !widget.isSelected;
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
        if (kDebugMode) {
          print("index:$widget.index,newValue:$newValue");
        }
      },
    );
  }
}
